import SwiftUI

// Accueil dans l'ordre de YouTube Music : puces d'humeur, Accès rapide, recommandations,
// « Mixés pour vous », puis les rangées de YouTube Music, les nouveautés du pays, les tendances et les clips.
// Sans compte, YouTube Music donne peu de rangées : le reste vient d'Explorer et de vos écoutes (sur le téléphone).
struct AccueilVue: View {
    @Environment(Historique.self) private var historique
    @State private var page = PageYTM()
    @State private var puce: Puce?
    @State private var radios: [(graine: Titre, titres: [Titre])] = []
    @State private var chargement = false
    @State private var erreur: String?
    @State private var derniereReco = Date.distantPast

    /// Un mix radio par artiste écouté récemment (dès la première écoute), précédé de « Mon supermix »
    /// (tout mélangé) quand l'app connaît assez vos goûts.
    private var mixes: [(nom: String, titres: [Titre])] {
        guard !radios.isEmpty else { return [] }
        let parArtiste = radios.map { (nom: "Mix \($0.graine.artiste)", titres: $0.titres) }
        guard historique.profilSuffisant, radios.count > 1 else { return parArtiste }
        var supermix: [Titre] = []
        let plusLongue = radios.map(\.titres.count).max() ?? 0
        for i in 0..<plusLongue { for r in radios where r.titres.indices.contains(i) { supermix.append(r.titres[i]) } }
        var vus = Set<String>()
        supermix = supermix.filter { vus.insert($0.idVideo).inserted }
        return [("Mon supermix", Array(supermix.prefix(50)))] + parArtiste
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                puces
                if puce == nil {
                    MixesPourVous(mixes: mixes)
                    if let r = radios.first, !r.titres.isEmpty {
                        RangeeVue(rangee: Rangee(titre: r.graine.nom, surtitre: "Parce que vous avez écouté", style: .grilleTitres,
                                                 elements: r.titres.map(Element.titre)))
                    }
                }
                ForEach(Array(page.sections.enumerated()), id: \.element.id) { i, rangee in
                    RangeeVue(rangee: rangee)
                    if puce == nil {
                        if i == 1 { RangeeNouveautes() }
                        if i == 3, radios.count > 2, let r = radios.last {
                            RangeeVue(rangee: Rangee(titre: r.graine.artiste, surtitre: "Dans le style de", style: .grilleTitres,
                                                     elements: r.titres.map(Element.titre)))
                        }
                        if i == 4, !historique.jaime.isEmpty {
                            RangeeVue(rangee: Rangee(titre: "Favoris à redécouvrir", style: .carrousel,
                                                     elements: historique.jaime.prefix(15).map(Element.titre)))
                        }
                    }
                }
                if let erreur, page.sections.isEmpty {
                    ContentUnavailableView {
                        Label("Pas de connexion", systemImage: "wifi.slash")
                    } description: {
                        Text(erreur)
                    } actions: {
                        Button("Réessayer") { Task { await charger() } }
                        NavigationLink("Mes téléchargements", value: Route.telechargements)
                    }
                } else if chargement && page.sections.isEmpty {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.fond)
        .refreshable { await charger(); await recommander() }
        .task { if page.sections.isEmpty { await charger() } }
        // Comme YouTube Music, l'accueil ne bouge pas pendant qu'on l'utilise (lancer un mix ne le reconstruit pas) :
        // les recommandations se rafraîchissent au retour sur l'accueil après 15 min, ou en tirant vers le bas.
        .task {
            guard radios.isEmpty || Date.now.timeIntervalSince(derniereReco) > 15 * 60 else { return }
            await recommander()
        }
        .barreYTM()
    }

    private var puces: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(page.puces) { p in
                    Button {
                        puce = puce == p ? nil : p
                        Task { await charger() }
                    } label: {
                        Text(p.nom).font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(puce == p ? Palette.surCitron : Palette.texte)
                            .background(Capsule().fill(puce == p ? Palette.citron : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func charger() async {
        chargement = true
        defer { chargement = false }
        do {
            async let complement = puce == nil ? try? InnerTube.partage.page("FEmusic_explore") : nil
            var nouvelle = try await InnerTube.partage.page("FEmusic_home", params: puce?.params)
            if let explorer = await complement {
                nouvelle.sections += explorer.sections.filter { $0.style != .boutons && !$0.titre.hasPrefix("Nouveaux albums") }
            }
            let puces = page.puces.isEmpty || puce == nil ? nouvelle.puces : page.puces
            page = nouvelle
            page.puces = puces
            page.suite = nil   // sans compte, la suite de l'accueil est vide
            PrechargeurFlux.partage.precharger(Array(nouvelle.sections.first { $0.style == .grilleTitres }?.titres.prefix(2) ?? []))
            erreur = nil
        } catch {
            erreur = "Vos téléchargements restent disponibles sans connexion."
        }
    }

    /// Recommandations : d'abord votre dernière écoute ; puis, quand l'app connaît assez vos goûts,
    /// vos artistes préférés (écoutes complètes, 👍, récence) pour « Mixés pour vous ».
    private func recommander() async {
        guard let derniere = historique.ecoutes.first else { radios = []; return }
        var graines = [derniere]
        // Derniers artistes écoutés, puis (si l'app vous connaît) vos artistes préférés.
        let candidats = historique.ecoutes + (historique.profilSuffisant ? historique.artistesPreferes(4) : [])
        for t in candidats where !graines.contains(where: { $0.artiste == t.artiste }) && !historique.artisteEvite(t) {
            graines.append(t)
            if graines.count == 5 { break }
        }
        let jaimePas = historique.jaimePas, zappes = historique.zappes
        let evites = Set(historique.ecoutes.filter { historique.artisteEvite($0) }.map(\.artiste))
        let resultat = await withTaskGroup(of: (Int, Titre, [Titre]).self) { groupe in
            for (i, graine) in graines.enumerated() {
                groupe.addTask {
                    let titres = (try? await InnerTube.partage.radio(graine.idVideo)) ?? []
                    let propres = titres.filter { $0.idVideo != graine.idVideo && !jaimePas.contains($0.idVideo)
                        && !zappes.contains($0.idVideo) && !evites.contains($0.artiste) }
                    return (i, graine, Array(propres.prefix(30)))
                }
            }
            var tous: [(Int, Titre, [Titre])] = []
            for await r in groupe where !r.2.isEmpty { tous.append(r) }
            return tous.sorted { $0.0 < $1.0 }.map { (graine: $0.1, titres: $0.2) }
        }
        radios = resultat
        derniereReco = .now
        PrechargeurFlux.partage.precharger(Array(resultat.first?.titres.prefix(2) ?? []))
    }
}

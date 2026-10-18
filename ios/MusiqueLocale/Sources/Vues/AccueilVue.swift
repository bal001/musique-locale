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
    @State private var derniereCharge = Date.distantPast
    @State private var duNouveau: [Element] = []        // sorties récentes de vos artistes
    @State private var aVenir: [Element] = []           // sorties annoncées (vos artistes + artistes du moment)
    @AppStorage("pays") private var pays: Pays = .france
    @Environment(\.scenePhase) private var phase
    @State private var restaure = false
    @State private var derniereVeille = Date.distantPast

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
                    if !duNouveau.isEmpty {
                        RangeeVue(rangee: Rangee(titre: "Du nouveau chez vos artistes", surtitre: "Sorties récentes", style: .carrousel, elements: duNouveau))
                    }
                    if let r = radios.first, !r.titres.isEmpty {
                        RangeeVue(rangee: Rangee(titre: r.graine.nom, surtitre: "Parce que vous avez écouté", style: .grilleTitres,
                                                 elements: r.titres.map(Element.titre)))
                    }
                }
                ForEach(Array(page.sections.enumerated()), id: \.element.id) { i, rangee in
                    RangeeVue(rangee: rangee)
                    if puce == nil {
                        if i == 1 {
                            RangeeNouveautes()   // « À venir » retiré à la demande du propriétaire
                        }
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
        .refreshable { await charger(); await recommander(); await veiller() }
        // Dernier accueil connu affiché tout de suite (rien ne clignote ni ne disparaît), puis mise à jour.
        .onAppear { if !restaure { restaurer(); restaure = true } }
        .task {
            if page.sections.isEmpty || Date.now.timeIntervalSince(derniereCharge) > 30 * 60 { await charger() }
        }
        .task {
            guard Date.now.timeIntervalSince(derniereVeille) > 30 * 60 else { return }
            await veiller()
        }
        // De retour dans l'app après plus de 30 min : tout se recharge (accueil, recommandations, sorties).
        .onChange(of: phase) { _, nouvelle in
            guard nouvelle == .active, Date.now.timeIntervalSince(derniereCharge) > 30 * 60 else { return }
            Task { await charger(); await recommander(); await veiller() }
        }
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
            // Réponse vide (réseau pas encore revenu…) : on garde ce qui est affiché.
            guard !nouvelle.sections.isEmpty else { return }
            let puces = page.puces.isEmpty || puce == nil ? nouvelle.puces : page.puces
            page = nouvelle
            page.puces = puces
            derniereCharge = .now
            // Suite de l'accueil (comme le site : Playlists de la communauté, Titres tendance, Nouveautés, 100% hits…).
            var jeton = nouvelle.suite
            for _ in 0..<3 {
                guard let j = jeton, let suite = try? await InnerTube.partage.suitePage(j), !suite.sections.isEmpty else { break }
                let connus = Set(page.sections.map(\.titre))
                page.sections += suite.sections.filter { !connus.contains($0.titre) }
                jeton = suite.suite
            }
            page.suite = nil
            if puce == nil { sauvegarder() }
            PrechargeurFlux.partage.precharger(Array(nouvelle.sections.first { $0.style == .grilleTitres }?.titres.prefix(1) ?? []))
            erreur = nil
        } catch {
            if page.sections.isEmpty { erreur = "Vos téléchargements restent disponibles sans connexion." }
        }
    }

    // MARK: Mémoire de l'accueil (affichage instantané à l'ouverture)

    private struct Memoire: Codable {
        var sections: [MemoireRangee]
        var puces: [Puce]
        var graines: [Titre]
        var radios: [[Titre]]
        var duNouveau: [Element]
        var aVenir: [Element]
    }
    private struct MemoireRangee: Codable {
        var titre: String; var surtitre: String?; var style: String; var elements: [Element]; var large: Bool; var vignette: URL?
    }
    private static let cleMemoire = "memoireAccueil"

    private func sauvegarder() {
        let rangees = page.sections.map { MemoireRangee(titre: $0.titre, surtitre: $0.surtitre, style: "\($0.style)",
                                                       elements: $0.elements, large: $0.large, vignette: $0.vignette) }
        let m = Memoire(sections: rangees, puces: page.puces, graines: radios.map(\.graine), radios: radios.map(\.titres),
                        duNouveau: duNouveau, aVenir: aVenir)
        if let donnees = try? JSONEncoder().encode(m) { UserDefaults.standard.set(donnees, forKey: Self.cleMemoire) }
    }

    private func restaurer() {
        guard let donnees = UserDefaults.standard.data(forKey: Self.cleMemoire),
              let m = try? JSONDecoder().decode(Memoire.self, from: donnees) else { return }
        let styles: [String: StyleSection] = ["carrousel": .carrousel, "grilleTitres": .grilleTitres, "liste": .liste, "boutons": .boutons]
        if page.sections.isEmpty {
            page.sections = m.sections.map { Rangee(titre: $0.titre, surtitre: $0.surtitre, style: styles[$0.style] ?? .carrousel,
                                                    elements: $0.elements, large: $0.large, vignette: $0.vignette) }
            page.puces = m.puces
        }
        if radios.isEmpty { radios = zip(m.graines, m.radios).map { (graine: $0, titres: $1) } }
        if duNouveau.isEmpty { duNouveau = m.duNouveau }
        if aVenir.isEmpty { aVenir = m.aVenir }
    }

    /// Veille des sorties : vos artistes (écoutes, profil, abonnements) pour « Du nouveau » ;
    /// eux + les artistes les plus écoutés du pays pour « À venir ».
    private func veiller() async {
        var vosArtistes = historique.artistesPreferes(15).map(\.artiste)
        vosArtistes += historique.enregistres.filter { $0.type == .artiste }.map(\.nom)
        vosArtistes += historique.ecoutes.prefix(20).map(\.artiste)
        vosArtistes = vosArtistes.map { $0.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? $0 }
        let duPays = ((try? await InnerTube.partage.classements(pays.rawValue))?.sections ?? []).flatMap(\.elements)
            .compactMap { e -> String? in if case .carte(let c) = e, c.type == .artiste { c.nom } else { nil } }.prefix(25)
        async let pourVous = VeilleSorties.partage.sorties(de: vosArtistes)
        async let annonces = VeilleSorties.partage.sorties(de: Array(duPays) + vosArtistes)
        let (v, a) = await (pourVous, annonces)
        // Jamais remplacé par du vide : un échec réseau garde les sorties déjà affichées.
        if !v.recentes.isEmpty { duNouveau = v.recentes.prefix(20).map { .carte($0.carte(aVenir: false)) } }
        if !a.aVenir.isEmpty { aVenir = a.aVenir.prefix(20).map { .carte($0.carte(aVenir: true)) } }
        derniereVeille = .now
        sauvegarder()
    }

    /// Recommandations : d'abord votre dernière écoute ; puis, quand l'app connaît assez vos goûts,
    /// vos artistes préférés (écoutes complètes, 👍, récence) pour « Mixés pour vous ».
    private func recommander() async {
        guard let derniere = historique.ecoutes.first else { return }
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
        guard !resultat.isEmpty else { return }   // échec réseau : on garde les mixes affichés
        radios = resultat
        derniereReco = .now
        sauvegarder()
        PrechargeurFlux.partage.precharger(Array(resultat.first?.titres.prefix(1) ?? []))
    }
}

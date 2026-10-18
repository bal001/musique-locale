import SwiftUI

// Nouveautés et classements par pays : France, États-Unis, Royaume-Uni, International (monde pour les classements).
/// Puces de choix du pays (le choix est retenu d'une fois sur l'autre).
struct PucesPays: View {
    @Binding var pays: Pays
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Pays.allCases) { p in
                    Button { pays = p } label: {
                        Text(p.nom).font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(pays == p ? Palette.surCitron : Palette.texte)
                            .background(Capsule().fill(pays == p ? Palette.citron : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Rangée « Nouveaux albums et singles » avec choix du pays (Explorer, Accueil).
struct RangeeNouveautes: View {
    @AppStorage("pays") private var pays: Pays = .france
    @State private var elements: [Element]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOUVEAUTÉS · \(pays.nom.uppercased())").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.texte2)
                    Text("Nouveaux albums et singles").font(.system(size: 22, weight: .bold))
                }
                Spacer()
                NavigationLink(value: Route.nouveautes) {
                    Text("Plus").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            PucesPays(pays: $pays)
            if let elements, !elements.isEmpty {
                RangeeVue(rangee: Rangee(titre: "", style: .carrousel, elements: elements))
            } else if elements == nil {
                ProgressView().tint(Palette.citron).frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Text("Aucune sortie trouvée pour ce pays.").font(.system(size: 14)).foregroundStyle(Palette.texte2).padding(.horizontal, 16)
            }
        }
        .task(id: pays) {
            elements = nil
            // Aperçu : les albums d'abord, puis les singles, chacun du plus récent au plus ancien.
            let sorties = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple, elargi: false) } ?? []
            let fiches = await GenresArtistes.partage.toutes()
            let parues = sorties.filter { !$0.aVenir && pays.accepte($0, fiche: fiches[GenresArtistes.cle($0.artiste)]) }
            elements = (parues.filter(\.album) + parues.filter { !$0.album }).prefix(30).map(\.element)
        }
    }
}

/// Page « Nouveautés » : sorties de l'année par pays, en grille, puis les nouveautés générales de YouTube Music.
struct NouveautesVue: View {
    @AppStorage("pays") private var pays: Pays = .france
    @AppStorage("nouveautesSingles") private var singles = false
    @State private var sorties: [Nouveautes.Sortie]?
    @State private var fiches: [String: GenresArtistes.Fiche] = [:]
    @State private var pourToi: [Nouveautes.Sortie] = []
    @Environment(Historique.self) private var historique

    /// Sorties du pays choisi (origine des artistes), albums ou singles selon la puce.
    private var choisies: [Nouveautes.Sortie] {
        (sorties ?? []).filter { $0.album != singles && !$0.aVenir && pays.accepte($0, fiche: fiches[GenresArtistes.cle($0.artiste)]) }
    }

    /// Une seule carte par artiste dans une rangée (sa sortie la plus récente), de la plus récente à la plus ancienne.
    private static func uneParArtiste(_ liste: [Nouveautes.Sortie]) -> [Element] {
        var vus = Set<String>()
        return liste.sorted { $0.date > $1.date }.filter { vus.insert(GenresArtistes.cle($0.artiste)).inserted }.map(\.element)
    }

    /// Verdict du conseil : « Cette semaine » (7 derniers jours, tous styles), « Pour toi » (tes artistes et leurs proches),
    /// puis une rangée par style précis (Rap français, Trap américaine…), sans fourre-tout « Autres styles ».
    private var rangees: [Rangee] {
        let liste = choisies
        var r: [Rangee] = []
        let semaine = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recentes = Self.uneParArtiste(liste.filter { $0.date >= semaine })
        if recentes.count >= 3 { r.append(Rangee(titre: "Cette semaine", style: .carrousel, elements: recentes, toutAfficher: true)) }
        let perso = Self.uneParArtiste(pourToi.filter { $0.album != singles })
        if perso.count >= 3 {
            r.append(Rangee(titre: "Pour toi", surtitre: "Tes artistes et leurs proches", style: .carrousel, elements: perso, toutAfficher: true))
        }
        let indice: String? = switch pays { case .france: "FR"; case .etatsUnis: "US"; case .royaumeUni: "GB"; case .international: nil }
        r += StyleMusical.ranger(liste) { StyleMusical.pour(fiches[GenresArtistes.cle($0.artiste)], univers: $0.univers, paysPage: indice) }
            .filter { $0.style.cle != "autres" }
            .map { Rangee(titre: $0.style.nom, style: .carrousel, elements: Self.uneParArtiste($0.sorties), toutAfficher: true) }
        return r
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    PucesPays(pays: $pays)
                    HStack(spacing: 8) {
                        puce("Albums et EP", choisie: !singles) { singles = false }
                        puce("Singles", choisie: singles) { singles = true }
                    }
                    .padding(.horizontal, 16)
                }
                if let sorties {
                    if rangees.isEmpty {
                        ContentUnavailableView(sorties.isEmpty ? "Nouveautés indisponibles" : "Aucune sortie récente",
                                               systemImage: "sparkles", description: Text("Réessaie dans un instant."))
                    }
                    ForEach(rangees, id: \.titre) { RangeeVue(rangee: $0) }
                } else {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.fond)
        .navigationTitle("Nouveautés")
        .task(id: pays) {
            sorties = nil
            fiches = await GenresArtistes.partage.toutes()
            // 1. Tout de suite : les sorties des artistes du moment. 2. Puis la page s'enrichit des artistes similaires.
            let rapide = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple, elargi: false) } ?? []
            sorties = rapide
            let liste = (try? await InnerTube.partage.nouveautes(pays.codesApple)) ?? rapide
            guard !Task.isCancelled else { return }
            if liste.count >= rapide.count { sorties = liste }
            // Artistes inconnus de la table : classés au fur et à mesure (1 par seconde), la page se range toute seule.
            if await GenresArtistes.partage.completer(liste.map(\.artiste)) { fiches = await GenresArtistes.partage.toutes() }
        }
        .task {
            // « Pour toi » seulement quand l'app connaît assez tes goûts (sinon la rangée n'apparaît pas).
            guard historique.profilSuffisant else { return }
            pourToi = await Nouveautes.pourToi(historique.artistesPreferes(20).map { GenresArtistes.premierArtiste($0.artiste) })
        }
    }

    private func puce(_ texte: String, choisie: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(texte).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(choisie ? Palette.fond : Palette.texte)
                .background(Capsule().fill(choisie ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Page « Classements » : top des artistes, clips et genres du pays choisi.
struct ClassementsVue: View {
    @AppStorage("pays") private var pays: Pays = .france
    @State private var page: PageYTM?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                PucesPays(pays: $pays)
                if let page {
                    if page.sections.isEmpty {
                        ContentUnavailableView("Classements indisponibles", systemImage: "wifi.slash",
                                               description: Text("Tire vers le bas pour réessayer."))
                    }
                    ForEach(page.sections) { RangeeVue(rangee: $0) }
                } else {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.fond)
        .navigationTitle("Classements")
        .task(id: pays) {
            page = nil
            page = await avecEssais(vide: { $0.sections.isEmpty }) { try await InnerTube.partage.classements(pays.rawValue) } ?? PageYTM()
        }
    }
}

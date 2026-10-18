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
            let sorties = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple) } ?? []
            elements = (sorties.filter(\.album) + sorties.filter { !$0.album }).prefix(30).map(\.element)
        }
    }
}

/// Page « Nouveautés » : sorties de l'année par pays, en grille, puis les nouveautés générales de YouTube Music.
struct NouveautesVue: View {
    @AppStorage("pays") private var pays: Pays = .france
    @AppStorage("nouveautesSingles") private var singles = false
    @State private var sorties: [Nouveautes.Sortie]?
    @State private var general: PageYTM?

    /// Une rangée par univers (Rap français, Pop, Électro…), albums ou singles seulement, du plus récent au plus ancien.
    private var rangees: [Rangee] {
        let choisies = (sorties ?? []).filter { $0.album != singles }
        return Nouveautes.Univers.allCases.compactMap { u in
            let elements = choisies.filter { $0.univers == u }.map(\.element)
            return elements.isEmpty ? nil : Rangee(titre: u.nom(pays), style: .carrousel, elements: elements)
        }
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
                ForEach(general?.sections.filter { $0.titre.contains("Clips") } ?? []) { RangeeVue(rangee: $0) }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.fond)
        .navigationTitle("Nouveautés")
        .task(id: pays) {
            sorties = nil
            sorties = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple) } ?? []
        }
        .task { general = try? await InnerTube.partage.page("FEmusic_new_releases") }
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

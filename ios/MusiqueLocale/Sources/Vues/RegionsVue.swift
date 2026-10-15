import SwiftUI

// Nouveautés et classements par pays : France, États-Unis, Royaume-Uni, International (monde pour les classements).
enum Pays: String, CaseIterable, Identifiable {
    case france = "FR", etatsUnis = "US", royaumeUni = "GB", international = "ZZ"
    var id: String { rawValue }
    var nom: String {
        switch self {
        case .france: "France"
        case .etatsUnis: "États-Unis"
        case .royaumeUni: "Royaume-Uni"
        case .international: "International"
        }
    }
    /// Pays des classements Apple Music utilisés pour les nouveautés (International = États-Unis + Royaume-Uni).
    var codesApple: [String] {
        switch self {
        case .france: ["fr"]
        case .etatsUnis: ["us"]
        case .royaumeUni: ["gb"]
        case .international: ["us", "gb"]
        }
    }
}

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
            elements = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple) } ?? []
        }
    }
}

/// Page « Nouveautés » : sorties de l'année par pays, en grille, puis les nouveautés générales de YouTube Music.
struct NouveautesVue: View {
    @AppStorage("pays") private var pays: Pays = .france
    @State private var elements: [Element]?
    @State private var general: PageYTM?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                PucesPays(pays: $pays)
                if let elements {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)], spacing: 22) {
                        ForEach(elements) { e in
                            ToucheElement(element: e) { CarteVue(element: e, largeur: (UIScreen.main.bounds.width - 46) / 2) }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity, minHeight: 200)
                }
                ForEach(general?.sections.filter { $0.style != .carrousel || $0.titre.contains("Clips") } ?? []) { RangeeVue(rangee: $0) }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.fond)
        .navigationTitle("Nouveautés")
        .task(id: pays) {
            elements = nil
            elements = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.nouveautes(pays.codesApple) } ?? []
        }
        .task { general = try? await InnerTube.partage.page("FEmusic_new_releases") }
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

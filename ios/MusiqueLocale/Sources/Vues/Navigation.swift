import SwiftUI

// Navigation commune aux onglets, comme YouTube Music : logo à gauche, loupe à droite,
// et pages poussées (artiste, album, playlist, genre, recherche, téléchargements).
enum Route: Hashable {
    case page(Carte)
    case recherche
    case telechargements
    case historique
    case nouveautes
    case classements
    case playlistPerso(UUID)
    case titresJaime
    case parametres
    case grille(String, [Element])   // « Tout afficher » d'une rangée

    /// Les pages Nouveautés et Classements de YouTube Music s'ouvrent avec le choix du pays.
    static func pour(_ carte: Carte) -> Route {
        switch carte.idPage {
        case "FEmusic_new_releases": .nouveautes
        case "FEmusic_charts": .classements
        default: .page(carte)
        }
    }
}

extension View {
    func destinationsYTM() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .page(let carte): PageVue(carte: carte)
            case .recherche: RechercheVue()
            case .telechargements: TelechargementsVue()
            case .historique: HistoriqueVue()
            case .nouveautes: NouveautesVue()
            case .classements: ClassementsVue()
            case .playlistPerso(let id): PlaylistPersoVue(id: id)
            case .titresJaime: TitresJaimeVue()
            case .parametres: ParametresVue()
            case .grille(let titre, let elements): GrilleVue(titre: titre, elements: elements)
            }
        }
    }

    /// Barre du haut des onglets : logo « Music » et bouton de recherche.
    func barreYTM() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Palette.citron).frame(width: 26, height: 26)
                        Image(systemName: "music.note").font(.system(size: 13, weight: .black)).foregroundStyle(Palette.surCitron)
                    }
                    Text("Music").font(.system(size: 21, weight: .heavy)).tracking(-0.6)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Musique Locale")
            }
            .sharedBackgroundVisibility(.hidden)   // pas de bulle de verre qui rognerait le logo
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.parametres) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Paramètres")
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
    }
}

/// Lecture d'un élément touché : un titre lance sa « radio » (titres du même style) ; une carte ouvre sa page.
struct ToucheElement<Contenu: View>: View {
    let element: Element
    var liste: [Titre] = []
    var source: String? = nil
    @ViewBuilder let contenu: () -> Contenu
    @Environment(Lecteur.self) private var lecteur
    @Environment(\.noterConsultation) private var noter
    @Environment(Navigateur.self) private var navigateur

    var body: some View {
        switch element {
        case .titre(let t):
            Button {
                noter?(element)
                if liste.count > 1, let i = liste.firstIndex(of: t) { lecteur.jouer(liste, depuis: i, source: source) } else { lecteur.lancerRadio(t) }
            } label: { contenu() }
            .buttonStyle(.plain)
            .contextMenu { ActionsTitre(titre: t) }
        case .carte(let c):
            if let cible = c.aChercher, !cible.album {
                // Single des nouveautés : retrouvé sur YouTube Music puis lancé avec sa radio.
                Button {
                    Task { if let t = try? await InnerTube.partage.trouverTitre(cible.requete) { lecteur.lancerRadio(t) } }
                } label: { contenu() }
                .buttonStyle(.plain)
            } else {
                // Navigation globale : marche aussi dans les fenêtres du lecteur (Similaires…), où un NavigationLink est grisé.
                Button {
                    noter?(element)
                    navigateur.ouvrir(Route.pour(c))
                } label: { contenu() }
                .buttonStyle(.plain)
            }
        }
    }
}


/// Dans la recherche : chaque résultat touché est noté dans « Recherches récentes ».
private struct CleConsultation: EnvironmentKey { static let defaultValue: (@MainActor (Element) -> Void)? = nil }
extension EnvironmentValues {
    var noterConsultation: (@MainActor (Element) -> Void)? {
        get { self[CleConsultation.self] }
        set { self[CleConsultation.self] = newValue }
    }
}

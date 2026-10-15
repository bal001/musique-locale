import Foundation

// Contenus des pages YouTube Music (accueil, explorer, artistes, albums, playlists, recherche),
// lus tels quels depuis InnerTube pour afficher exactement ce que montre l'app officielle.

enum TypeCarte: String, Hashable, Codable, Sendable {
    case album, playlist, artiste, page
}

/// Une carte qui ouvre une page : album, playlist, artiste, ou page d'exploration (genre, humeur…).
struct Carte: Identifiable, Hashable, Codable, Sendable {
    var idPage: String          // browseId (MPREb…, VL…, UC…, FEmusic_…)
    var params: String? = nil
    var type: TypeCarte
    var nom: String
    var sousTitre: String = ""
    var image: URL? = nil
    var couleur: UInt32? = nil  // boutons « Humeurs et genres »

    var id: String { idPage + (params ?? "") }
    var ronde: Bool { type == .artiste }
}

enum Element: Identifiable, Hashable, Codable, Sendable {
    case titre(Titre)
    case carte(Carte)

    var id: String {
        switch self {
        case .titre(let t): "t:" + t.idVideo
        case .carte(let c): "c:" + c.id
        }
    }
}

enum StyleSection: Sendable {
    case carrousel       // cartes carrées qui défilent à l'horizontale
    case grilleTitres    // « Sélection rapide » : colonnes de 4 titres qui défilent
    case liste           // titres les uns sous les autres
    case boutons         // « Nouveautés / Classements / Humeurs et genres », boutons de genres
}

struct Rangee: Identifiable, Sendable {
    let id = UUID()
    var titre: String
    var surtitre: String? = nil
    var style: StyleSection
    var elements: [Element]
    var lien: Carte? = nil        // « Tout afficher » / titre cliquable
    var large = false             // vignettes 16:9 (clips)
    var vignette: URL? = nil      // photo ronde à côté du titre (« En rapport avec … »)

    var titres: [Titre] { elements.compactMap { if case .titre(let t) = $0 { t } else { nil } } }
}

/// Puce de filtre (humeurs de l'accueil, catégories de la recherche).
struct Puce: Identifiable, Hashable, Sendable {
    var nom: String
    var params: String?
    var id: String { nom }
}

struct EntetePage: Sendable {
    var type: TypeCarte
    var nom: String
    var sousTitre: String = ""
    var detail: String = ""
    var artiste: String = ""
    var idArtiste: String? = nil
    var image: URL?
    var description: String? = nil
}

struct PageYTM: Sendable {
    var entete: EntetePage? = nil
    var puces: [Puce] = []
    var sections: [Rangee] = []
    var suite: String? = nil      // jeton pour charger la suite (accueil infini)

    /// Titres d'un album ou d'une playlist (première section en liste).
    var titresPrincipaux: [Titre] { sections.first { $0.style == .liste }?.titres ?? [] }
}

extension StyleSection: Equatable {}

/// Playlist créée sur le téléphone (« + Nouveau » dans la bibliothèque, « Enregistrer dans une playlist »).
struct PlaylistPerso: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var nom: String
    var titres: [Titre] = []
    var creeLe = Date.now
    var modifieLe = Date.now
}


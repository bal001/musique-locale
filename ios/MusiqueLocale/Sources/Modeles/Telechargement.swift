import Foundation

enum TypeTelechargement: String, Codable, Sendable {
    case audio   // m4a
    case clip    // mp4 vidéo + son

    var extensionFichier: String { self == .audio ? "m4a" : "mp4" }
}

// Entrée de l'index des téléchargements (Application Support/Telechargements/index.json).
struct Telechargement: Codable, Identifiable, Hashable, Sendable {
    var titre: Titre
    var type: TypeTelechargement
    var fichier: String     // nom du fichier dans le dossier Telechargements
    var date: Date

    var id: String { Self.cle(titre.idVideo, type) }

    static func cle(_ idVideo: String, _ type: TypeTelechargement) -> String { "\(idVideo)-\(type.rawValue)" }
}

// Téléchargement en cours (progression entre 0 et 1, nil si la taille est inconnue).
struct TelechargementEnCours: Identifiable, Hashable, Sendable {
    let titre: Titre
    let type: TypeTelechargement
    var fraction: Double?

    var id: String { Telechargement.cle(titre.idVideo, type) }
}

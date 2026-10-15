import Foundation

// Un titre YouTube (morceau ou clip), tel que renvoyé par la recherche.
struct Titre: Identifiable, Codable, Hashable, Sendable {
    let idVideo: String
    var nom: String
    var artiste: String
    var duree: Int?          // secondes
    var miniature: URL?
    var idArtiste: String? = nil   // pour « Accéder à l'artiste »
    var idAlbum: String? = nil     // pour « Accéder à l'album »
    var album: String? = nil
    var explicite: Bool? = nil     // badge « E »

    var id: String { idVideo }

    /// « Artiste • 3:45 »
    var sousTitre: String {
        [artiste, duree.map { formaterDuree(Double($0)) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

/// 225 → « 3:45 », 3723 → « 1:02:03 »
func formaterDuree(_ secondes: Double) -> String {
    guard secondes.isFinite, secondes >= 0 else { return "0:00" }
    let s = Int(secondes.rounded(.down))
    let h = s / 3600, m = (s % 3600) / 60, r = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
}

/// « 3:45 » ou « 1:02:03 » → secondes
func lireDuree(_ texte: String) -> Int? {
    let morceaux = texte.split(separator: ":").compactMap { Int($0) }
    guard (2...3).contains(morceaux.count), morceaux.count == texte.split(separator: ":").count else { return nil }
    return morceaux.reduce(0) { $0 * 60 + $1 }
}

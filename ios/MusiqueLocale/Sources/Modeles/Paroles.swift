import Foundation

// Paroles d'un titre. `lignes` n'existe que pour des paroles synchronisées (LRC).
struct Paroles: Codable, Hashable, Sendable {
    let texte: String
    let source: String
    var lignes: [LigneParole]?
}

struct LigneParole: Codable, Hashable, Sendable {
    let temps: Double   // secondes
    let texte: String
}

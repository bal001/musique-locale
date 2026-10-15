import Foundation

// Nouveautés par pays, vraiment récentes : les classements publics d'Apple Music (mis à jour chaque jour,
// avec la date de sortie) filtrés sur les 6 dernières semaines, du plus récent au plus ancien.
// Toucher une sortie ouvre l'album (ou lance le titre) sur YouTube Music.
enum Nouveautes {
    private struct Flux: Decodable {
        struct Contenu: Decodable { let results: [Sortie] }
        let feed: Contenu
    }
    private struct Sortie: Decodable {
        let artistName: String
        let name: String
        let releaseDate: String?
        let artworkUrl100: String?
    }

    /// `pays` : code Apple (fr, us, gb). Plusieurs pays → sorties fusionnées (« International »).
    static func sorties(_ pays: [String]) async throws -> [Element] {
        let aujourdhui = Date.now
        let limite = Calendar.current.date(byAdding: .day, value: -42, to: aujourdhui) ?? aujourdhui
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let affichage = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))

        var trouvees: [(date: Date, element: Element)] = []
        var vues = Set<String>()
        try await withThrowingTaskGroup(of: (String, [Sortie]).self) { groupe in
            for code in pays {
                for type in ["albums", "songs"] {
                    groupe.addTask {
                        let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(code)/music/most-played/100/\(type).json")!
                        // Le serveur d'Apple renvoie souvent des erreurs passagères (502, 504) : jusqu'à 4 essais.
                        for essai in 0..<4 {
                            var requete = URLRequest(url: url, timeoutInterval: 12)
                            requete.cachePolicy = .reloadIgnoringLocalCacheData
                            if let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
                               (reponse as? HTTPURLResponse)?.statusCode == 200,
                               let flux = try? JSONDecoder().decode(Flux.self, from: donnees) {
                                return (type, flux.feed.results)
                            }
                            try? await Task.sleep(for: .milliseconds(700 * (essai + 1)))
                        }
                        return (type, [])
                    }
                }
            }
            for try await (type, liste) in groupe {
                for s in liste {
                    guard let brute = s.releaseDate, let date = format.date(from: brute),
                          date >= limite, date <= aujourdhui else { continue }   // ni anciennes, ni précommandes
                    let cle = (s.artistName + "|" + s.name).lowercased()
                    guard vues.insert(cle).inserted else { continue }
                    let album = type == "albums"
                    let nature = album ? (s.name.contains(" - EP") ? "EP" : "Album") : "Single"
                    let image = s.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
                    let carte = Carte(idPage: "chercher:\(album ? "album" : "titre"):\(s.artistName) \(s.name.replacingOccurrences(of: " - EP", with: ""))",
                                      type: .album, nom: s.name.replacingOccurrences(of: " - EP", with: ""),
                                      sousTitre: "\(nature) • \(s.artistName) • \(date.formatted(affichage))", image: image)
                    trouvees.append((date, .carte(carte)))
                }
            }
        }
        return trouvees.sorted { $0.date > $1.date }.map(\.element)
    }
}

extension Carte {
    /// Sortie venue du classement Apple : à retrouver sur YouTube Music au moment où on la touche.
    var aChercher: (album: Bool, requete: String)? {
        guard idPage.hasPrefix("chercher:") else { return nil }
        let reste = idPage.dropFirst("chercher:".count)
        guard let deuxPoints = reste.firstIndex(of: ":") else { return nil }
        return (reste[..<deuxPoints] == "album", String(reste[reste.index(after: deuxPoints)...]))
    }
}

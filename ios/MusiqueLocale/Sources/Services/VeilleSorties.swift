import Foundation

// Veille des sorties : pour une liste d'artistes, les albums, EP et singles **avec leur date exacte**
// (annuaire public d'iTunes, précommandes comprises), triés en « sortis récemment » et « à venir ».
// Utilisé pour « Du nouveau chez vos artistes » et « À venir ». Toucher une sortie l'ouvre sur YouTube Music
// (`Carte.aChercher`). Résultats gardés 12 h par artiste (mémoire + téléphone).
actor VeilleSorties {
    static let partage = VeilleSorties()

    struct Sortie: Codable, Hashable, Sendable {
        var nom: String
        var artiste: String
        var date: Date
        var nature: String     // Album, EP, Single
        var image: URL?
    }

    private struct Fiche: Codable { var date: Date; var sorties: [Sortie] }
    private var fiches: [String: Fiche] = [:]           // par artiste (nom en minuscules)
    private let cleDisque = "veilleSorties"

    init() {
        if let donnees = UserDefaults.standard.data(forKey: cleDisque),
           let lues = try? JSONDecoder().decode([String: Fiche].self, from: donnees) { fiches = lues }
    }

    /// Sorties des 21 derniers jours (de la plus récente) et à venir dans les 4 mois (de la plus proche).
    func sorties(de artistes: [String], pays: String = "fr") async -> (recentes: [Sortie], aVenir: [Sortie]) {
        let noms = Array(NSOrderedSet(array: artistes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
            .compactMap { $0 as? String }.prefix(40)
        var toutes: [Sortie] = []
        // 6 artistes à la fois : rapide sans encombrer la connexion.
        for lot in stride(from: 0, to: noms.count, by: 6).map({ Array(noms[$0..<min($0 + 6, noms.count)]) }) {
            let resultats = await withTaskGroup(of: [Sortie].self) { groupe in
                for nom in lot { groupe.addTask { await self.sortiesArtiste(nom, pays: pays) } }
                var r: [Sortie] = []
                for await s in groupe { r += s }
                return r
            }
            toutes += resultats
        }
        let maintenant = Date.now
        let debut = Calendar.current.date(byAdding: .day, value: -21, to: maintenant)!
        let fin = Calendar.current.date(byAdding: .month, value: 4, to: maintenant)!
        let recentes = Self.sansDoublons(toutes.filter { $0.date >= debut && $0.date <= maintenant }).sorted { $0.date > $1.date }
        let aVenir = Self.sansDoublons(toutes.filter { $0.date > maintenant && $0.date <= fin }).sorted { $0.date < $1.date }
        if let donnees = try? JSONEncoder().encode(fiches) { UserDefaults.standard.set(donnees, forKey: cleDisque) }
        return (recentes, aVenir)
    }

    private func sortiesArtiste(_ nom: String, pays: String) async -> [Sortie] {
        let cle = nom.lowercased()
        if let f = fiches[cle], Date.now.timeIntervalSince(f.date) < 12 * 3600 { return f.sorties }
        do {
            let recherche = try await Self.json("https://itunes.apple.com/search?" + Self.requete(["term": nom, "entity": "musicArtist", "country": pays, "limit": "3"]))
            // L'artiste dont le nom correspond exactement, sinon le premier résultat.
            let candidats = recherche["results"] as? [[String: Any]] ?? []
            guard let artiste = candidats.first(where: { ($0["artistName"] as? String)?.lowercased() == cle }) ?? candidats.first,
                  let id = artiste["artistId"] as? Int else { return fiches[cle]?.sorties ?? [] }
            let albums = try await Self.json("https://itunes.apple.com/lookup?id=\(id)&entity=album&sort=recent&limit=15&country=\(pays)")
            let format = ISO8601DateFormatter()
            let sorties: [Sortie] = (albums["results"] as? [[String: Any]] ?? []).compactMap { a in
                guard a["wrapperType"] as? String == "collection", let brut = a["collectionName"] as? String,
                      let texteDate = a["releaseDate"] as? String, let date = format.date(from: texteDate) else { return nil }
                let pistes = a["trackCount"] as? Int ?? 0
                let nature = brut.hasSuffix(" - Single") ? "Single" : brut.hasSuffix(" - EP") ? "EP" : pistes <= 3 ? "Single" : "Album"
                let nomPropre = brut.replacingOccurrences(of: #" - (Single|EP)$"#, with: "", options: .regularExpression)
                let image = (a["artworkUrl100"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
                return Sortie(nom: nomPropre, artiste: a["artistName"] as? String ?? nom, date: date, nature: nature, image: image)
            }
            fiches[cle] = Fiche(date: .now, sorties: sorties)
            return sorties
        } catch {
            return fiches[cle]?.sorties ?? []   // service lent ou hors ligne : la dernière fiche connue
        }
    }

    /// « Patient Zero (Piano Version) » et « Patient Zero (Acoustic Version) » : une seule sortie, la première.
    private static func sansDoublons(_ sorties: [Sortie]) -> [Sortie] {
        var vues = Set<String>()
        return sorties.sorted { $0.date < $1.date }.filter { s in
            let base = s.nom.lowercased()
                .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return vues.insert(base + "|" + s.artiste.lowercased()).inserted
        }
    }

    private static func requete(_ p: [String: String]) -> String {
        p.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }.joined(separator: "&")
    }

    private static func json(_ adresse: String) async throws -> [String: Any] {
        guard let url = URL(string: adresse) else { throw ErreurReseau.indisponible }
        var requete = URLRequest(url: url, timeoutInterval: 10)
        requete.setValue("MusiqueLocale-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (donnees, _) = try await URLSession.shared.data(for: requete)
        return try JSONSerialization.jsonObject(with: donnees) as? [String: Any] ?? [:]
    }
}

extension VeilleSorties.Sortie {
    /// Carte à afficher ; touchée, elle est retrouvée sur YouTube Music (album, ou titre pour un single).
    func carte(aVenir: Bool) -> Carte {
        let jour = date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        let quand = aVenir ? "Sort le \(jour)" : jour
        return Carte(idPage: "chercher:\(nature == "Single" ? "titre" : "album"):\(artiste) \(nom)", type: .album, nom: nom,
                     sousTitre: "\(nature) • \(artiste) • \(quand)", image: image)
    }
}

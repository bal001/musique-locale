import Foundation

// Élargit les nouveautés « comme Spotify » : aux artistes les plus écoutés du pays s'ajoutent leurs artistes
// similaires (même style, connus ou moins connus), puis toutes leurs sorties récentes et à venir.
// Source : API publique de Deezer, sans clé (artistes similaires, discographie datée). Au plus ~8 demandes à la fois
// (Deezer accepte 50 demandes / 5 s). Identifiants et similaires gardés 7 jours, discographies 12 h, sur le téléphone.
actor ArtistesSimilaires {
    static let partage = ArtistesSimilaires()

    struct Artiste: Codable, Hashable, Sendable { var id: Int; var nom: String; var fans: Int }
    struct Disque: Codable, Sendable {
        var titre: String; var artiste: String; var date: String; var type: String; var genre: Int?; var image: String?
    }
    private struct Memoire: Codable {
        var ids: [String: Artiste?] = [:]
        var similaires: [Int: [Artiste]] = [:]
        var datesSimilaires: [Int: Date] = [:]
        var disques: [Int: [Disque]] = [:]
        var datesDisques: [Int: Date] = [:]
    }
    private var m = Memoire()
    private let fichier: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent("artistes-similaires.json")
    }()
    private var enVol = 0

    init() {
        if let donnees = try? Data(contentsOf: fichier), let lue = try? JSONDecoder().decode(Memoire.self, from: donnees) { m = lue }
    }

    func sauver() {
        if let donnees = try? JSONEncoder().encode(m) { try? donnees.write(to: fichier, options: .atomic) }
    }

    /// Artiste Deezer portant exactement ce nom (le plus suivi en cas d'homonymes).
    func artiste(_ nom: String) async -> Artiste? {
        let cle = GenresArtistes.cle(nom)
        if let connu = m.ids[cle] { return connu }
        guard let json = await demander("search/artist?q=\(nom.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nom)&limit=10"),
              let liste = json["data"] as? [[String: Any]] else { return nil }
        let trouve = liste.compactMap(Self.artiste(depuis:)).filter { GenresArtistes.cle($0.nom) == cle }.max { $0.fans < $1.fans }
        m.ids[cle] = trouve
        return trouve
    }

    func similaires(_ a: Artiste) async -> [Artiste] {
        if let s = m.similaires[a.id], let d = m.datesSimilaires[a.id], Date.now.timeIntervalSince(d) < 7 * 86400 { return s }
        guard let json = await demander("artist/\(a.id)/related?limit=20"), let liste = json["data"] as? [[String: Any]] else {
            return m.similaires[a.id] ?? []
        }
        let s = liste.compactMap(Self.artiste(depuis:))
        m.similaires[a.id] = s
        m.datesSimilaires[a.id] = .now
        return s
    }

    func disques(_ a: Artiste) async -> [Disque] {
        if let s = m.disques[a.id], let d = m.datesDisques[a.id], Date.now.timeIntervalSince(d) < 12 * 3600 { return s }
        guard let json = await demander("artist/\(a.id)/albums?limit=12"), let liste = json["data"] as? [[String: Any]] else {
            return m.disques[a.id] ?? []
        }
        let s: [Disque] = liste.compactMap { d in
            guard let titre = d["title"] as? String, let date = d["release_date"] as? String else { return nil }
            return Disque(titre: titre, artiste: a.nom, date: date, type: d["record_type"] as? String ?? "album",
                          genre: d["genre_id"] as? Int, image: d["cover_xl"] as? String ?? d["cover_big"] as? String)
        }
        m.disques[a.id] = s
        m.datesDisques[a.id] = .now
        return s
    }

    private static func artiste(depuis d: [String: Any]) -> Artiste? {
        guard let id = d["id"] as? Int, let nom = d["name"] as? String else { return nil }
        return Artiste(id: id, nom: nom, fans: d["nb_fan"] as? Int ?? 0)
    }

    /// Demande à Deezer, 8 à la fois au plus ; « quota dépassé » → courte pause et nouvel essai.
    private func demander(_ chemin: String) async -> [String: Any]? {
        while enVol >= 8 { try? await Task.sleep(for: .milliseconds(120)) }
        enVol += 1
        defer { enVol -= 1 }
        guard let url = URL(string: "https://api.deezer.com/" + chemin) else { return nil }
        for essai in 0..<3 {
            if let (donnees, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 12)),
               let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] {
                if json["error"] == nil { return json }
            }
            try? await Task.sleep(for: .milliseconds(800 * (essai + 1)))
        }
        return nil
    }

    /// Genre Deezer → univers de l'app.
    nonisolated static func univers(_ genre: Int?) -> Nouveautes.Univers {
        switch genre {
        case 116: .rap
        case 132, 52: .pop
        case 106, 113: .electro
        case 165, 169: .rnb
        case 197: .latino
        case 152, 85, 464: .rock
        case 84: .country
        case 144: .reggae
        case 2: .afro
        default: .autres
        }
    }
}

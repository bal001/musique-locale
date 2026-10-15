import Foundation

// Paroles en ligne, sans compte ni clé (même logique que server/paroles.mjs) :
// 0. fichier local (titre téléchargé) ;
// 1. LRCLIB → paroles synchronisées quand elles existent ;
// 2. sinon l'onglet « Paroles » de YouTube Music.
// Un « rien trouvé » n'est mémorisé que si aucune requête n'a échoué.
actor ServiceParoles {
    static let partage = ServiceParoles()
    private static let agent = "MusiqueLocale-iOS/1.0"

    private var cache: [String: Paroles] = [:]
    private var absentes: Set<String> = []

    func paroles(pour titre: Titre) async -> Paroles? {
        let id = titre.idVideo
        if let p = cache[id] { return p }
        if let p = Stockage.parolesLocales(id) { cache[id] = p; return p }
        if absentes.contains(id) { return nil }

        var echec = false
        var trouvees: Paroles?
        do { trouvees = try await Self.depuisLrclib(titre) } catch { echec = true }
        if trouvees == nil {
            do {
                if let r = try await InnerTube.partage.parolesYouTubeMusic(id) {
                    trouvees = Paroles(texte: r.texte, source: r.source, lignes: nil)
                }
            } catch { echec = true }
        }
        if let trouvees { cache[id] = trouvees } else if !echec { absentes.insert(id) }
        return trouvees
    }

    // MARK: LRCLIB

    private struct ResultatLrclib: Decodable {
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static func depuisLrclib(_ titre: Titre) async throws -> Paroles? {
        var composants = URLComponents(string: "https://lrclib.net/api/search")
        composants?.queryItems = [
            URLQueryItem(name: "track_name", value: nettoyerTitre(titre.nom)),
            URLQueryItem(name: "artist_name", value: premierArtiste(titre.artiste)),
        ]
        guard let url = composants?.url else { return nil }
        var requete = URLRequest(url: url, timeoutInterval: 8)
        requete.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        if let http = reponse as? HTTPURLResponse, http.statusCode != 200 { throw ErreurReseau.statut(http.statusCode) }
        let resultats = try JSONDecoder().decode([ResultatLrclib].self, from: donnees)
        let proches = resultats.filter { r in
            guard let d = titre.duree, let rd = r.duration else { return true }
            return abs(rd - Double(d)) <= 4
        }
        if let s = proches.first(where: { !($0.syncedLyrics ?? "").isEmpty }), let texte = s.syncedLyrics {
            return Paroles(texte: texte, source: "LRCLIB", lignes: analyserLRC(texte))
        }
        if let p = proches.first(where: { !($0.plainLyrics ?? "").isEmpty }), let texte = p.plainLyrics {
            return Paroles(texte: texte, source: "LRCLIB", lignes: nil)
        }
        return nil
    }

    /// « Jefe (Clip officiel) [4K] » → « Jefe »
    static func nettoyerTitre(_ t: String) -> String {
        t.replacingOccurrences(
            of: #"\s*[(\[][^)\]]*(clip|video|vidéo|audio|lyrics?|paroles|official|officiel|visuali[sz]er|4k|hd|remaster)[^)\]]*[)\]]"#,
            with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*[|｜].*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// « Ninho, Jul » → « Ninho » ; « NinhoVEVO » / « Ninho - Topic » → « Ninho »
    static func premierArtiste(_ a: String) -> String {
        var nom = a
        if let r = nom.range(of: #",| & | feat"#, options: [.regularExpression, .caseInsensitive]) {
            nom = String(nom[..<r.lowerBound])
        }
        return nom.replacingOccurrences(of: #"( - Topic|VEVO)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// « [01:02.34]texte » → lignes triées ; gère plusieurs repères par ligne.
    static func analyserLRC(_ lrc: String) -> [LigneParole]? {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#) else { return nil }
        var lignes: [LigneParole] = []
        for brute in lrc.components(separatedBy: .newlines) {
            let ns = brute as NSString
            let reperes = regex.matches(in: brute, range: NSRange(location: 0, length: ns.length))
            guard let dernier = reperes.last else { continue }
            let texte = ns.substring(from: dernier.range.upperBound).trimmingCharacters(in: .whitespaces)
            for m in reperes {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let secondes = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                lignes.append(LigneParole(temps: minutes * 60 + secondes, texte: texte))
            }
        }
        lignes.sort { $0.temps < $1.temps }
        return lignes.isEmpty ? nil : lignes
    }
}

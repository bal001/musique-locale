import Foundation

// Pays et styles précis de chaque artiste (« US · trap, southern hip hop », « FR · french hip hop »,
// « GB · uk drill », « house, deep house »…), pour ranger les nouveautés comme Spotify : Trap américaine,
// Drill UK, Rap français, House, Techno… Source : MusicBrainz (encyclopédie libre, 1 requête par seconde au plus).
// L'app embarque une table toute prête (Resources/genres-artistes.json, faite par outils/genres_artistes.py) et
// complète elle-même les artistes nouveaux, gardés sur le téléphone.
actor GenresArtistes {
    static let partage = GenresArtistes()

    struct Fiche: Codable, Sendable {
        var pays: String?
        var styles: [String]
        var date: Date? = nil      // artiste introuvable : on réessaie au bout de 30 jours
    }

    private var fiches: [String: Fiche] = [:]
    private var enCours = false
    private let fichier: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("genres-artistes.json")
    }()

    init() {
        if let url = Bundle.main.url(forResource: "genres-artistes", withExtension: "json"),
           let donnees = try? Data(contentsOf: url),
           let embarquees = try? JSONDecoder().decode([String: Fiche].self, from: donnees) { fiches = embarquees }
        if let donnees = try? Data(contentsOf: fichier),
           let locales = try? JSONDecoder().decode([String: Fiche].self, from: donnees) {
            fiches.merge(locales) { _, locale in locale }
        }
    }

    /// « Lil Baby & Future » → « lilbaby » (premier artiste, sans accents ni ponctuation).
    nonisolated static func cle(_ artistes: String) -> String {
        let premier = artistes.replacingOccurrences(of: #"\s*(,|&| feat\.? | ft\.? | x | X | et )\s*"#, with: "\u{1}", options: .regularExpression)
            .split(separator: "\u{1}").first.map(String.init) ?? artistes
        return premier.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    nonisolated static func premierArtiste(_ artistes: String) -> String {
        artistes.replacingOccurrences(of: #"\s*(,|&| feat\.? | ft\.? | x | X | et )\s*"#, with: "\u{1}", options: .regularExpression)
            .split(separator: "\u{1}").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? artistes
    }

    func fiche(_ artistes: String) -> Fiche? { fiches[Self.cle(artistes)] }
    func toutes() -> [String: Fiche] { fiches }

    /// Cherche les artistes encore inconnus (200 au plus par appel, 1 par seconde). Renvoie vrai si des fiches ont été ajoutées.
    func completer(_ artistes: [String]) async -> Bool {
        guard !enCours else { return false }
        enCours = true
        defer { enCours = false }
        var vus = Set<String>()
        let manquants = artistes.filter { a in
            let c = Self.cle(a)
            guard !c.isEmpty, vus.insert(c).inserted else { return false }
            guard let f = fiches[c] else { return true }
            if let d = f.date, f.styles.isEmpty, Date.now.timeIntervalSince(d) > 30 * 86400 { return true }
            return false
        }.prefix(200)
        guard !manquants.isEmpty else { return false }
        for nom in manquants {
            if Task.isCancelled { break }
            fiches[Self.cle(nom)] = await Self.chercher(Self.premierArtiste(nom)) ?? Fiche(pays: nil, styles: [], date: .now)
            try? await Task.sleep(for: .milliseconds(1100))
        }
        if let donnees = try? JSONEncoder().encode(fiches) { try? donnees.write(to: fichier, options: .atomic) }
        return true
    }

    private static func chercher(_ nom: String) async -> Fiche? {
        var composants = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")!
        composants.queryItems = [URLQueryItem(name: "query", value: "artist:\"\(nom)\""), URLQueryItem(name: "limit", value: "3"),
                                 URLQueryItem(name: "fmt", value: "json")]
        var requete = URLRequest(url: composants.url!, timeoutInterval: 12)
        requete.setValue("MusiqueLocale/1.0 (https://github.com/bal001/musique-locale)", forHTTPHeaderField: "User-Agent")
        guard let (donnees, _) = try? await URLSession.shared.data(for: requete),
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let artistes = json["artists"] as? [[String: Any]] else { return nil }
        let voulu = cle(nom)
        for a in artistes {
            let noms = [a["name"] as? String ?? ""] + ((a["aliases"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            guard noms.contains(where: { cle($0) == voulu }) else { continue }
            let tags = ((a["tags"] as? [[String: Any]]) ?? [])
                .sorted { ($0["count"] as? Int ?? 0) > ($1["count"] as? Int ?? 0) }
                .compactMap { $0["name"] as? String }.prefix(8)
            let pays = a["country"] as? String ?? ((a["area"] as? [String: Any])?["iso-3166-1-codes"] as? [String])?.first
            return Fiche(pays: pays, styles: Array(tags), date: .now)
        }
        return nil
    }
}

/// Catégorie précise d'une sortie (« Trap américaine », « Drill UK », « House »…).
struct StyleMusical: Hashable, Sendable {
    let cle: String        // « trap-us »
    let nom: String        // « Trap américaine »
    let famille: Int       // ordre des familles : rap, pop urbaine, R&B, afro, pop, électro, latino…

    private enum Origine { case fr, us, uk, autre }

    /// Style précis à partir de la fiche MusicBrainz ; à défaut, l'univers donné par Apple.
    /// `paysPage` : pays des nouveautés affichées, supposé être celui d'un artiste dont l'origine est inconnue.
    static func pour(_ fiche: GenresArtistes.Fiche?, univers: Nouveautes.Univers, paysPage: String? = nil) -> StyleMusical {
        let origine: Origine? = switch fiche?.pays ?? (univers == .rap || univers == .rnb ? paysPage : nil) {
        case "FR", "BE", "CH", "LU", "MC": .fr
        case "US": .us
        case "GB", "IE": .uk
        case nil: nil
        default: .autre
        }
        let tags = (fiche?.styles ?? []).map { $0.lowercased() }
        func a(_ mots: String...) -> Bool { tags.contains { t in mots.contains { t.contains($0) } } }
        func selon(_ cle: String, fr: String, us: String, uk: String, autre: String, famille: Int) -> StyleMusical {
            switch origine {
            case .fr: StyleMusical(cle: cle + "-fr", nom: fr, famille: famille)
            case .us: StyleMusical(cle: cle + "-us", nom: us, famille: famille)
            case .uk: StyleMusical(cle: cle + "-uk", nom: uk, famille: famille)
            default: StyleMusical(cle: cle, nom: autre, famille: famille)
            }
        }
        let rap = univers == .rap || a("hip hop", "hip-hop", "rap", "trap", "drill", "grime")

        // Styles qui priment, quel que soit l'univers donné par Apple.
        if a("k-pop", "korean") { return StyleMusical(cle: "kpop", nom: "K-pop", famille: 9) }
        if a("afrobeats", "afro trap", "afroswing", "afropop", "amapiano", "afrobeat", "coupé-décalé", "ndombolo", "afro") {
            return selon("afro", fr: "Afro et pop urbaine", us: "Afro", uk: "Afroswing UK", autre: "Afrobeats et amapiano", famille: 3)
        }
        if a("reggaeton", "latin trap", "dembow", "corrido", "regional mexican", "banda", "bachata", "salsa", "latin") {
            return StyleMusical(cle: "latino", nom: "Latino et reggaeton", famille: 7)
        }
        if rap {
            if a("drill") { return selon("drill", fr: "Drill française", us: "Drill américaine", uk: "Drill UK", autre: "Drill", famille: 0) }
            if a("grime") { return StyleMusical(cle: "grime", nom: "Grime et rap UK", famille: 0) }
            if a("trap", "mumble rap", "rage", "plugg", "southern hip hop", "cloud rap", "emo rap") {
                return selon("trap", fr: "Trap française", us: "Trap américaine", uk: "Trap UK", autre: "Trap", famille: 0)
            }
            if a("pop rap") && origine == .fr && !a("gangsta", "hardcore") {
                return StyleMusical(cle: "popurbaine-fr", nom: "Rap et pop urbaine", famille: 1)
            }
            if a("boom bap", "conscious", "jazz rap", "east coast hip hop", "abstract hip hop", "underground hip hop", "alternative hip hop") {
                return selon("boombap", fr: "Rap conscient et boom bap", us: "Boom bap et rap conscient US", uk: "Rap UK alternatif",
                             autre: "Rap alternatif", famille: 0)
            }
            return selon("rap", fr: "Rap français", us: "Rap américain", uk: "Rap UK", autre: "Rap du monde", famille: 0)
        }
        if a("r&b", "rnb", "soul") {
            return selon("rnb", fr: "R&B français", us: "R&B américain", uk: "R&B UK", autre: "R&B et soul", famille: 2)
        }
        if a("drum and bass", "drum & bass", "dnb", "jungle", "liquid funk") { return StyleMusical(cle: "dnb", nom: "Drum & bass", famille: 5) }
        if a("techno") { return StyleMusical(cle: "techno", nom: "Techno", famille: 5) }
        if a("hardstyle", "gabber", "hardcore techno", "hard dance") { return StyleMusical(cle: "hardstyle", nom: "Hardstyle", famille: 5) }
        if a("dubstep", "bass music", "riddim", "brostep") { return StyleMusical(cle: "bass", nom: "Dubstep et bass music", famille: 5) }
        if a("house") { return StyleMusical(cle: "house", nom: "House", famille: 5) }
        if a("trance") { return StyleMusical(cle: "trance", nom: "Trance", famille: 5) }
        if a("edm", "big room", "electro house", "future bass", "electronic", "electro", "dance") || univers == .electro {
            return StyleMusical(cle: "edm", nom: "Électro et dance", famille: 5)
        }
        if a("reggae", "dancehall", "soca") || univers == .reggae { return StyleMusical(cle: "reggae", nom: "Reggae et dancehall", famille: 8) }
        if a("country") || univers == .country { return StyleMusical(cle: "country", nom: "Country", famille: 10) }
        if a("metal") { return StyleMusical(cle: "metal", nom: "Metal", famille: 11) }
        if a("punk", "rock", "indie", "alternative", "grunge", "shoegaze") || univers == .rock {
            return StyleMusical(cle: "rock", nom: "Rock et indé", famille: 11)
        }
        if a("chanson", "variété", "french pop") || (origine == .fr && (a("pop") || univers == .pop)) {
            return StyleMusical(cle: "variete", nom: "Pop et variété française", famille: 4)
        }
        if a("pop") || univers == .pop {
            return selon("pop", fr: "Pop et variété française", us: "Pop américaine", uk: "Pop UK", autre: "Pop", famille: 4)
        }
        switch univers {
        case .rnb: return StyleMusical(cle: "rnb", nom: "R&B et soul", famille: 2)
        case .afro: return StyleMusical(cle: "afro", nom: "Afrobeats et amapiano", famille: 3)
        case .latino: return StyleMusical(cle: "latino", nom: "Latino et reggaeton", famille: 7)
        case .kpop: return StyleMusical(cle: "kpop", nom: "K-pop", famille: 9)
        default: return StyleMusical(cle: "autres", nom: "Autres styles", famille: 12)
        }
    }
}

extension StyleMusical {
    /// Range des sorties par style ; un style à moins de 3 sorties rejoint le plus gros style de sa famille
    /// (une drill isolée va dans « Rap français »), sinon « Autres styles ». Familles dans l'ordre, les plus fournies d'abord.
    static func ranger<T>(_ sorties: [T], style: (T) -> StyleMusical) -> [(style: StyleMusical, sorties: [T])] {
        var groupes = Dictionary(grouping: sorties, by: style)
        let autres = StyleMusical(cle: "autres", nom: "Autres styles", famille: 12)
        for (s, liste) in groupes where liste.count < 3 && s != autres {
            let cible = groupes.filter { $0.key.famille == s.famille && $0.key != s && $0.value.count >= 3 }
                .max { $0.value.count < $1.value.count }?.key ?? (s.famille <= 4 ? s : autres)
            guard cible != s else { continue }   // rap, R&B, afro, pop : une petite rangée vaut mieux que « Autres styles »
            groupes[s] = nil
            groupes[cible, default: []] += liste
        }
        return groupes.sorted { a, b in a.key.famille != b.key.famille ? a.key.famille < b.key.famille : a.value.count > b.value.count }
            .map { ($0.key, $0.value) }
    }
}


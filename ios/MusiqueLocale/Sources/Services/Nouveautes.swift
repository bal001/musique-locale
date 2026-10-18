import Foundation

// Nouveautés par pays, vraiment récentes, rangées par univers (rap, pop, électro…) et séparées en albums / singles.
// Sources publiques d'Apple, mises à jour chaque jour, avec la date de sortie et le style :
//  - les 100 albums et titres les plus écoutés du pays sur Apple Music ;
//  - les classements iTunes par style (rap, pop, électro, dance, R&B, latino, rock, variété française), qui donnent
//    assez de sorties dans chaque univers même quand il est peu présent dans le classement général.
// Filtrées sur les 6 dernières semaines, de la plus récente à la plus ancienne. Toucher une sortie l'ouvre
// (album) ou la lance (single) sur YouTube Music.
enum Nouveautes {
    /// Univers musicaux, dans l'ordre d'affichage.
    enum Univers: String, Codable, CaseIterable, Sendable {
        case rap, pop, rnb, electro, afro, latino, rock, country, reggae, kpop, autres

        /// Nom affiché selon le pays (« Rap français », « Rap US »…).
        func nom(_ pays: Pays) -> String {
            let origine: String? = switch pays {
            case .france: nil
            case .etatsUnis: "US"
            case .royaumeUni: "UK"
            case .international: nil
            }
            switch self {
            case .rap: return pays == .france ? "Rap français" : origine.map { "Rap \($0)" } ?? "Rap"
            case .pop: return pays == .france ? "Pop et variété française" : origine.map { "Pop \($0)" } ?? "Pop"
            case .rnb: return "R&B"
            case .electro: return "Électro et dance"
            case .afro: return "Afro"
            case .latino: return "Latino"
            case .rock: return "Rock et alternatif"
            case .country: return "Country"
            case .reggae: return "Reggae et dancehall"
            case .kpop: return "K-pop"
            case .autres: return "Autres styles"
            }
        }

        /// Style Apple (« Hip-hop/Rap », « Électronique », « Variété française »…) → univers.
        static func depuis(_ genres: [String]) -> Univers {
            for brut in genres {
                let g = brut.lowercased()
                if g == "musique" || g == "music" { continue }
                if g.contains("k-pop") { return .kpop }
                if g.contains("hip") || g.contains("rap") { return .rap }
                if g.contains("r&b") || g.contains("soul") { return .rnb }
                if g.contains("électro") || g.contains("electro") || g.contains("dance") || g.contains("house") || g.contains("techno") { return .electro }
                if g.contains("afro") || g.contains("africa") || g.contains("amapiano") { return .afro }
                if g.contains("latin") || g.contains("reggaeton") || g.contains("urbano") { return .latino }
                if g.contains("reggae") || g.contains("dancehall") { return .reggae }
                if g.contains("country") { return .country }
                if g.contains("rock") || g.contains("altern") || g.contains("metal") || g.contains("indie") || g.contains("punk") { return .rock }
                if g.contains("pop") || g.contains("variété") || g.contains("chanson") || g.contains("singer") { return .pop }
                return .autres
            }
            return .autres
        }
    }

    struct Sortie: Codable, Hashable, Sendable {
        var element: Element
        var date: Date
        var album: Bool
        var univers: Univers
    }

    // Classement Apple Music (flux récent).
    private struct Flux: Decodable {
        struct Contenu: Decodable { let results: [Brute] }
        let feed: Contenu
    }
    private struct Brute: Decodable {
        struct Genre: Decodable { let name: String }
        let artistName: String
        let name: String
        let releaseDate: String?
        let artworkUrl100: String?
        let genres: [Genre]?
    }

    /// Classements iTunes par style (identifiants de genre iTunes) ; 50000064 = Variété française.
    private static func stylesITunes(_ code: String) -> [Int] {
        var styles = [18, 14, 7, 17, 15, 12, 21]
        if code == "fr" { styles.append(50000064) }
        return styles
    }

    /// `codes` : pays Apple (fr, us, gb). Plusieurs pays → sorties fusionnées (« International »).
    static func sorties(_ codes: [String]) async -> [Sortie] {
        let aujourdhui = Date.now
        let limite = Calendar.current.date(byAdding: .day, value: -42, to: aujourdhui) ?? aujourdhui
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"

        // (album ?, artiste, nom, date, image, styles) de toutes les sources.
        typealias Ligne = (album: Bool, artiste: String, nom: String, date: String, image: String?, genres: [String])
        var prioritaires: [Ligne] = [], autres: [Ligne] = []
        await withTaskGroup(of: (Bool, [Ligne]).self) { groupe in
            for code in codes {
                for type in ["albums", "songs"] {
                    groupe.addTask {
                        let url = "https://rss.marketingtools.apple.com/api/v2/\(code)/music/most-played/100/\(type).json"
                        guard let donnees = await telecharger(url), let flux = try? JSONDecoder().decode(Flux.self, from: donnees) else { return (true, []) }
                        return (true, flux.feed.results.compactMap { b in
                            b.releaseDate.map { (type == "albums", b.artistName, b.name, $0, b.artworkUrl100, b.genres?.map(\.name) ?? []) }
                        })
                    }
                }
                for style in stylesITunes(code) {
                    for type in ["topalbums", "topsongs"] {
                        groupe.addTask {
                            guard let donnees = await telecharger("https://itunes.apple.com/\(code)/rss/\(type)/limit=100/genre=\(style)/json") else { return (false, []) }
                            return (false, lignesITunes(donnees, album: type == "topalbums"))
                        }
                    }
                }
            }
            for await (prioritaire, l) in groupe { if prioritaire { prioritaires += l } else { autres += l } }
        }

        var vues = Set<String>()
        var trouvees: [Sortie] = []
        let affichage = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))
        // Le classement Apple Music d'abord (styles plus fiables), puis les classements par style.
        for l in prioritaires + autres {
            guard let date = format.date(from: String(l.date.prefix(10))), date >= limite, date <= aujourdhui else { continue }
            let nomPropre = l.nom.replacingOccurrences(of: #" - (Single|EP)$"#, with: "", options: .regularExpression)
            let cle = (l.artiste + "|" + nomPropre).lowercased()
            guard vues.insert(cle).inserted else { continue }
            let estSingle = !l.album || l.nom.hasSuffix(" - Single")
            let nature = estSingle ? "Single" : (l.nom.hasSuffix(" - EP") ? "EP" : "Album")
            let image = l.image.flatMap {
                URL(string: $0.replacingOccurrences(of: #"\d+x\d+bb"#, with: "600x600bb", options: .regularExpression))
            }
            let carte = Carte(idPage: "chercher:\(estSingle ? "titre" : "album"):\(l.artiste) \(nomPropre)",
                              type: .album, nom: nomPropre,
                              sousTitre: "\(nature) • \(l.artiste) • \(date.formatted(affichage))", image: image)
            trouvees.append(Sortie(element: .carte(carte), date: date, album: !estSingle, univers: Univers.depuis(l.genres)))
        }
        return trouvees.sorted { $0.date > $1.date }
    }

    /// Ancien format des flux iTunes (« im:releaseDate », « category »…).
    private static func lignesITunes(_ donnees: Data, album: Bool) -> [(album: Bool, artiste: String, nom: String, date: String, image: String?, genres: [String])] {
        guard let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let entrees = (json["feed"] as? [String: Any])?["entry"] as? [[String: Any]] else { return [] }
        func libelle(_ e: [String: Any], _ cle: String) -> String? { (e[cle] as? [String: Any])?["label"] as? String }
        return entrees.compactMap { e in
            guard let nom = libelle(e, "im:name"), let artiste = libelle(e, "im:artist"), let date = libelle(e, "im:releaseDate") else { return nil }
            let image = ((e["im:image"] as? [[String: Any]])?.last)?["label"] as? String
            let genre = (((e["category"] as? [String: Any])?["attributes"]) as? [String: Any])?["label"] as? String
            return (album, artiste, nom, date, image, genre.map { [$0] } ?? [])
        }
    }

    /// Les serveurs d'Apple renvoient souvent des erreurs passagères (502, 504) : jusqu'à 4 essais.
    private static func telecharger(_ adresse: String) async -> Data? {
        guard let url = URL(string: adresse) else { return nil }
        for essai in 0..<4 {
            var requete = URLRequest(url: url, timeoutInterval: 12)
            requete.cachePolicy = .reloadIgnoringLocalCacheData
            if let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
               (reponse as? HTTPURLResponse)?.statusCode == 200 { return donnees }
            try? await Task.sleep(for: .milliseconds(700 * (essai + 1)))
        }
        return nil
    }
}

/// Pays des nouveautés et classements (choix retenu dans « pays »).
enum Pays: String, CaseIterable, Identifiable {
    case france = "FR", etatsUnis = "US", royaumeUni = "GB", international = "ZZ"
    var id: String { rawValue }
    var nom: String {
        switch self {
        case .france: "France"
        case .etatsUnis: "États-Unis"
        case .royaumeUni: "Royaume-Uni"
        case .international: "International"
        }
    }
    /// Pays des classements Apple Music utilisés pour les nouveautés (International = États-Unis + Royaume-Uni).
    var codesApple: [String] {
        switch self {
        case .france: ["fr"]
        case .etatsUnis: ["us"]
        case .royaumeUni: ["gb"]
        case .international: ["us", "gb"]
        }
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

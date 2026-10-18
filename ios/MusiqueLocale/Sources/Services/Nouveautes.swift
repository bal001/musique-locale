import Foundation

// Nouveautés par pays, vraiment récentes, rangées par univers (rap, pop, électro…) et séparées en albums / singles.
// Sources publiques d'Apple, mises à jour chaque jour, avec la date de sortie et le style :
//  - les 100 albums et titres les plus écoutés du pays sur Apple Music : uniquement des artistes réellement écoutés
//    (les classements iTunes par style, faits de ventes de téléchargements, remontaient des inconnus : retirés).
// Filtrées sur les 2 derniers mois, de la plus récente à la plus ancienne. Toucher une sortie l'ouvre
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
        var artiste: String
        var aVenir = false     // précommande : sortie datée dans les 4 prochains mois
    }

    // Classement Apple Music (flux récent).
    private struct Flux: Decodable {
        struct Contenu: Decodable { let results: [Brute] }
        let feed: Contenu
    }
    private struct Brute: Decodable {
        struct Genre: Decodable { let name: String }
        let artistName: String
        let artistId: String?
        let name: String
        let releaseDate: String?
        let artworkUrl100: String?
        let genres: [Genre]?
    }

    /// `codes` : pays Apple (fr, us, gb). Plusieurs pays → sorties fusionnées (« International »).
    /// Méthode « Release Radar » : les artistes les plus écoutés du pays (classements Apple Music), puis TOUTES leurs
    /// sorties des 2 derniers mois et à venir (annuaire iTunes, dates exactes, précommandes). Que des artistes connus.
    static func sorties(_ codes: [String]) async -> [Sortie] {
        let aujourdhui = Date.now
        let limite = Calendar.current.date(byAdding: .day, value: -61, to: aujourdhui) ?? aujourdhui
        let horizon = Calendar.current.date(byAdding: .month, value: 4, to: aujourdhui) ?? aujourdhui
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"

        typealias Ligne = (album: Bool, artiste: String, nom: String, date: String, image: String?, genres: [String], univers: Univers?)
        var lignes: [Ligne] = []
        for code in codes {
            // 1. Classements Apple Music du pays : sorties récentes + liste des artistes du moment.
            var ids: [String] = []
            var populaires: [String] = []
            await withTaskGroup(of: (String, [Brute]).self) { groupe in
                for type in ["albums", "songs"] {
                    groupe.addTask {
                        let url = "https://rss.marketingtools.apple.com/api/v2/\(code)/music/most-played/100/\(type).json"
                        guard let donnees = await telecharger(url), let flux = try? JSONDecoder().decode(Flux.self, from: donnees) else { return (type, []) }
                        return (type, flux.feed.results)
                    }
                }
                for await (type, liste) in groupe {
                    for b in liste {
                        if let id = b.artistId, !ids.contains(id) { ids.append(id) }
                        if let d = b.releaseDate { lignes.append((type == "albums", b.artistName, b.name, d, b.artworkUrl100, b.genres?.map(\.name) ?? [], nil)) }
                        populaires.append(b.artistName)
                    }
                }
            }
            // 2. Toutes les sorties récentes et à venir de ces artistes (40 artistes par demande).
            let lots = stride(from: 0, to: ids.count, by: 40).map { Array(ids[$0..<min($0 + 40, ids.count)]) }
            await withTaskGroup(of: [Ligne].self) { groupe in
                for lot in lots {
                    groupe.addTask {
                        let url = "https://itunes.apple.com/lookup?id=\(lot.joined(separator: ","))&entity=album&sort=recent&limit=8&country=\(code)"
                        guard let donnees = await telecharger(url),
                              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
                              let resultats = json["results"] as? [[String: Any]] else { return [] }
                        return resultats.compactMap { r in
                            guard r["wrapperType"] as? String == "collection", let nom = r["collectionName"] as? String,
                                  let artiste = r["artistName"] as? String, let date = r["releaseDate"] as? String,
                                  !nom.contains("Video Bundle") else { return nil }
                            let album = !nom.hasSuffix(" - Single") && (r["trackCount"] as? Int ?? 4) > 3
                            return (album, artiste, nom, date, r["artworkUrl100"] as? String,
                                    [r["primaryGenreName"] as? String].compactMap { $0 }, nil)
                        }
                    }
                }
                for await l in groupe { lignes += l }
            }
            // 3. Nouveautés Spotify du pays (si la clé est branchée dans Paramètres).
            for s in await Spotify.nouveautes(code) {
                let nom = s.type == "single" ? s.nom + " - Single" : s.type == "compilation" ? s.nom : s.nom
                lignes.append((s.type != "single", s.artiste, nom, s.date, s.image, [], nil))
                populaires.append(s.artiste)
            }
            // 4. Comme Spotify : les artistes similaires (même style, connus ou moins connus) et leurs sorties (Deezer).
            lignes += await sortiesSimilaires(populaires)
        }
        await ArtistesSimilaires.partage.sauver()

        var vues = Set<String>()
        var trouvees: [Sortie] = []
        let affichage = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))
        for l in lignes where !Self.parasite(l.artiste, l.nom, l.genres) {
            guard let date = format.date(from: String(l.date.prefix(10))), date >= limite, date <= horizon else { continue }
            let nomPropre = l.nom.replacingOccurrences(of: #" - (Single|EP)$"#, with: "", options: .regularExpression)
            // « Patient Zero », « Patient Zero (Piano Version) », « Patient Zero - Single » : une seule fois.
            let base = nomPropre.lowercased().replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard vues.insert(GenresArtistes.cle(l.artiste) + "|" + base).inserted else { continue }
            let estSingle = !l.album || l.nom.hasSuffix(" - Single")
            let nature = estSingle ? "Single" : (l.nom.hasSuffix(" - EP") ? "EP" : "Album")
            let image = l.image.flatMap {
                URL(string: $0.replacingOccurrences(of: #"\d+x\d+bb"#, with: "600x600bb", options: .regularExpression))
            }
            let aVenir = date > aujourdhui
            let quand = aVenir ? "Sort le \(date.formatted(affichage))" : date.formatted(affichage)
            let carte = Carte(idPage: "chercher:\(estSingle ? "titre" : "album"):\(l.artiste) \(nomPropre)",
                              type: .album, nom: nomPropre, sousTitre: "\(nature) • \(l.artiste) • \(quand)", image: image)
            trouvees.append(Sortie(element: .carte(carte), date: date, album: !estSingle, univers: l.univers ?? Univers.depuis(l.genres),
                                   artiste: l.artiste, aVenir: aVenir))
        }
        return trouvees.sorted { $0.date > $1.date }
    }

    /// Berceuses, bruits de la nature, compilations, livres audio, musiques de film : rien à faire dans les nouveautés.
    private static func parasite(_ artiste: String, _ nom: String, _ genres: [String]) -> Bool {
        let a = artiste.lowercased(), n = nom.lowercased()
        let mots = ["lullaby", "berceuse", "bedtime", "white noise", "bruit blanc", "sons de la nature", "nature sounds", "sleep", "therapy",
                    "relaxing", "relaxation", "meditation", "méditation", "workout", "karaoke", "karaoké"]
        if ["various artists", "multi-interprètes", "artistes divers", "verschiedene interpreten"].contains(a) { return true }
        if mots.contains(where: { a.contains($0) || n.contains($0) }) { return true }
        return genres.contains { g in ["children", "enfant", "jeunesse", "audiobook", "livres audio", "spoken", "fitness", "holiday", "fêtes"]
            .contains { g.lowercased().contains($0) } }
    }

    /// Artistes du moment → leurs similaires sur Deezer (12 chacun, 300 au plus) → sorties des uns et des autres.
    private static func sortiesSimilaires(_ populaires: [String]) async
        -> [(album: Bool, artiste: String, nom: String, date: String, image: String?, genres: [String], univers: Univers?)] {
        let service = ArtistesSimilaires.partage
        var vus = Set<String>()
        let noms = populaires.map(GenresArtistes.premierArtiste).filter { vus.insert(GenresArtistes.cle($0)).inserted }.prefix(100)
        let tetes = await withTaskGroup(of: ArtistesSimilaires.Artiste?.self) { g in
            for n in noms { g.addTask { await service.artiste(n) } }
            var r: [ArtistesSimilaires.Artiste] = []
            for await a in g { if let a { r.append(a) } }
            return r
        }
        var connus = Set(tetes.map(\.id))
        var cercle = tetes
        let voisins = await withTaskGroup(of: [ArtistesSimilaires.Artiste].self) { g in
            for a in tetes { g.addTask { Array(await service.similaires(a).prefix(12)) } }
            var r: [[ArtistesSimilaires.Artiste]] = []
            for await s in g { r.append(s) }
            return r
        }
        for v in voisins.flatMap({ $0 }) where connus.insert(v.id).inserted && cercle.count < 400 { cercle.append(v) }
        let disques = await withTaskGroup(of: [ArtistesSimilaires.Disque].self) { g in
            for a in cercle { g.addTask { await service.disques(a) } }
            var r: [ArtistesSimilaires.Disque] = []
            for await d in g { r += d }
            return r
        }
        return disques.map { d in
            let album = d.type != "single"
            let nom = d.type == "ep" ? d.titre + " - EP" : d.type == "single" ? d.titre + " - Single" : d.titre
            return (album, d.artiste, nom, d.date, d.image, [95, 457, 173].contains(d.genre ?? 0) ? ["jeunesse"] : [],
                    ArtistesSimilaires.univers(d.genre))
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

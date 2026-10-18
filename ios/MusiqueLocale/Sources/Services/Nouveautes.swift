import Foundation

// Nouveautés par pays, vraiment récentes, rangées par univers (rap, pop, électro…) et séparées en albums / singles.
// Sources publiques d'Apple, mises à jour chaque jour, avec la date de sortie et le style :
//  - les 100 albums et titres les plus écoutés du pays sur Apple Music : uniquement des artistes réellement écoutés
//    (les classements iTunes par style, faits de ventes de téléchargements, remontaient des inconnus : retirés).
// Filtrées sur les 4 derniers mois, de la plus récente à la plus ancienne. Toucher une sortie l'ouvre
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
        var similaire = false  // ajoutée par les artistes similaires (Deezer), pas par le classement du pays
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
    /// sorties des 4 derniers mois et à venir (annuaire iTunes, dates exactes, précommandes). Que des artistes connus.
    static func sorties(_ codes: [String], elargi: Bool = true) async -> [Sortie] {
        let aujourdhui = Date.now
        let limite = Calendar.current.date(byAdding: .day, value: -122, to: aujourdhui) ?? aujourdhui
        let horizon = aujourdhui   // déjà sorties seulement (« À venir » retiré à la demande du propriétaire)
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
            // 3. Comme Spotify : les artistes similaires (même style, connus ou moins connus) et leurs sorties (Deezer).
            if elargi { lignes += await sortiesSimilaires(populaires) }
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
            let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                         to: Calendar.current.startOfDay(for: aujourdhui)).day ?? 99
            let quand = aVenir ? "Sort le \(date.formatted(affichage))"
                : jours <= 0 ? "Aujourd'hui" : jours == 1 ? "Hier" : jours < 7 ? "Il y a \(jours) j" : date.formatted(affichage)
            let carte = Carte(idPage: "chercher:\(estSingle ? "titre" : "album"):\(l.artiste) \(nomPropre)",
                              type: .album, nom: nomPropre, sousTitre: "\(nature) • \(l.artiste) • \(quand)", image: image)
            trouvees.append(Sortie(element: .carte(carte), date: date, album: !estSingle, univers: l.univers ?? Univers.depuis(l.genres),
                                   artiste: l.artiste, aVenir: aVenir, similaire: l.univers != nil))
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

    /// « Pour toi » : sorties des 4 derniers mois de tes artistes préférés (profil de goûts du téléphone) et de
    /// 3 artistes proches de chacun (Deezer), de la plus récente à la plus ancienne, une carte par artiste au plus 2.
    static func pourToi(_ artistes: [String]) async -> [Sortie] {
        let service = ArtistesSimilaires.partage
        let limite = Calendar.current.date(byAdding: .day, value: -122, to: .now) ?? .now
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let tetes = await withTaskGroup(of: ArtistesSimilaires.Artiste?.self) { g in
            for n in artistes.prefix(20) { g.addTask { await service.artiste(n) } }
            var r: [ArtistesSimilaires.Artiste] = []
            for await a in g { if let a { r.append(a) } }
            return r
        }
        var cercle = tetes
        var vus = Set(tetes.map(\.id))
        for voisins in await withTaskGroup(of: [ArtistesSimilaires.Artiste].self, body: { g in
            for a in tetes { g.addTask { Array(await service.similaires(a).prefix(3)) } }
            var r: [[ArtistesSimilaires.Artiste]] = []
            for await s in g { r.append(s) }
            return r
        }) { for v in voisins where vus.insert(v.id).inserted { cercle.append(v) } }
        let disques = await withTaskGroup(of: [ArtistesSimilaires.Disque].self) { g in
            for a in cercle { g.addTask { await service.disques(a) } }
            var r: [ArtistesSimilaires.Disque] = []
            for await d in g { r += d }
            return r
        }
        await service.sauver()
        let affichage = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))
        var cles = Set<String>()
        return disques.compactMap { d -> Sortie? in
            guard let date = format.date(from: d.date), date >= limite, date <= .now,
                  !parasite(d.artiste, d.titre, [95, 457, 173].contains(d.genre ?? 0) ? ["jeunesse"] : []),
                  cles.insert(GenresArtistes.cle(d.artiste) + "|" + d.titre.lowercased()).inserted else { return nil }
            let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                         to: Calendar.current.startOfDay(for: .now)).day ?? 99
            let quand = jours <= 0 ? "Aujourd'hui" : jours == 1 ? "Hier" : jours < 7 ? "Il y a \(jours) j" : date.formatted(affichage)
            let single = d.type == "single"
            let nature = single ? "Single" : d.type == "ep" ? "EP" : "Album"
            let carte = Carte(idPage: "chercher:\(single ? "titre" : "album"):\(d.artiste) \(d.titre)", type: .album, nom: d.titre,
                              sousTitre: "\(nature) • \(d.artiste) • \(quand)", image: d.image.flatMap(URL.init(string:)))
            return Sortie(element: .carte(carte), date: date, album: !single, univers: ArtistesSimilaires.univers(d.genre), artiste: d.artiste)
        }.sorted { $0.date > $1.date }
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

    /// Le serveur des classements Apple reste souvent bloqué 30 s avant d'échouer (504) : chaque réponse est gardée
    /// sur le téléphone ; moins de 3 h → servie telle quelle ; sinon 2 demandes en parallèle (8 s au plus, 3 essais),
    /// et en cas d'échec la dernière réponse connue (moins de 3 jours).
    static func telecharger(_ adresse: String) async -> Data? {
        guard let url = URL(string: adresse) else { return nil }
        let dossier = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("FluxApple", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        // Nom de fichier stable (hashValue change à chaque lancement) : empreinte djb2 de l'adresse.
        let empreinte = adresse.utf8.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
        let fichier = dossier.appendingPathComponent(String(empreinte, radix: 36))
        let age = (try? fichier.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date.now.timeIntervalSince($0) }
        if let age, age < 3 * 3600, let d = try? Data(contentsOf: fichier) { return d }
        for essai in 0..<3 {
            let reponse = await withTaskGroup(of: Data?.self) { g -> Data? in
                for _ in 0..<2 {
                    g.addTask {
                        var r = URLRequest(url: url, timeoutInterval: 8)
                        r.cachePolicy = .reloadIgnoringLocalCacheData
                        guard let (d, rep) = try? await URLSession.shared.data(for: r), (rep as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                        return d
                    }
                }
                for await d in g { if let d { g.cancelAll(); return d } }
                return nil
            }
            if let reponse { try? reponse.write(to: fichier, options: .atomic); return reponse }
            try? await Task.sleep(for: .milliseconds(500 * (essai + 1)))
        }
        if let age, age < 3 * 86400 { return try? Data(contentsOf: fichier) }
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

extension Pays {
    /// Pays d'origine des artistes affichés dans les nouveautés de ce pays (comme Spotify : « France » = artistes français
    /// et francophones, « États-Unis » = artistes américains et canadiens…). `nil` = tous (International).
    var originesArtistes: Set<String>? {
        switch self {
        case .france: ["FR", "BE", "CH", "LU", "MC", "CI", "CM", "CD", "CG", "SN", "ML", "GN", "BF", "GA", "TG", "BJ", "MA", "DZ", "TN",
                       "HT", "RE", "GP", "MQ", "GF", "YT", "KM", "MG"]
        case .etatsUnis: ["US", "CA", "PR"]
        case .royaumeUni: ["GB", "IE"]
        case .international: nil
        }
    }

    /// Une sortie a-t-elle sa place dans les nouveautés de ce pays ? Origine connue (MusicBrainz) : elle doit correspondre ;
    /// inconnue : seulement si elle vient du classement du pays lui-même (jamais par les artistes similaires).
    func accepte(_ s: Nouveautes.Sortie, fiche: GenresArtistes.Fiche?) -> Bool {
        guard let origines = originesArtistes else { return true }
        if let pays = fiche?.pays { return origines.contains(pays) }
        return !s.similaire
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

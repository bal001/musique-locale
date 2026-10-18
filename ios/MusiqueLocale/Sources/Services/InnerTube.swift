import Foundation

// Recherche YouTube Music sans clé ni compte, directement depuis le téléphone,
// via l'API interne InnerTube (client WEB_REMIX, comme music.youtube.com).

struct ResultatsRecherche: Sendable {
    var titres: [Titre]
    var videos: [Titre]
}

enum ErreurReseau: LocalizedError {
    case statut(Int)
    case indisponible

    var errorDescription: String? {
        switch self {
        case .statut(let code): "Réponse inattendue du serveur (\(code))."
        case .indisponible: "YouTube ne répond pas. Vérifie ta connexion."
        }
    }
}

struct InnerTube: Sendable {
    static let partage = InnerTube()
    /// Filtre « Titres » de YouTube Music.
    static let filtreTitres = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    /// Version du client YouTube Music : lue sur music.youtube.com (une fois par jour, ou dès qu'une requête est refusée),
    /// pour que l'app suive toute seule les changements de YouTube.
    private static let cleVersion = "versionClientYTM"
    private static var client: [String: String] {
        ["clientName": "WEB_REMIX", "clientVersion": UserDefaults.standard.string(forKey: cleVersion) ?? "1.20261013.15.00", "hl": "fr", "gl": "FR"]
    }

    /// Identifiant de visiteur anonyme fourni par YouTube (gardé 1 jour), utilisé par l'extraction rapide.
    static func visiteur() async throws -> String {
        let defauts = UserDefaults.standard
        if let v = defauts.string(forKey: "visiteurYT"), let d = defauts.object(forKey: "visiteurYTDate") as? Date,
           Date.now.timeIntervalSince(d) < 86400 { return v }
        let json = try await partage.appel("music/get_search_suggestions", ["input": "a"])
        guard let v = ArbreJSON.valeur(json, "responseContext", "visitorData") as? String else { throw ErreurReseau.indisponible }
        defauts.set(v, forKey: "visiteurYT")
        defauts.set(Date.now, forKey: "visiteurYTDate")
        return v
    }

    static func actualiserVersion(forcer: Bool = false) async {
        let derniere = UserDefaults.standard.object(forKey: cleVersion + "Date") as? Date ?? .distantPast
        guard forcer || Date.now.timeIntervalSince(derniere) > 86400, let url = URL(string: "https://music.youtube.com/") else { return }
        var requete = URLRequest(url: url, timeoutInterval: 10)
        requete.setValue(agent, forHTTPHeaderField: "User-Agent")
        requete.setValue("fr", forHTTPHeaderField: "Accept-Language")
        requete.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")   // cookies refusés : pas de page de consentement
        guard let (donnees, _) = try? await URLSession.shared.data(for: requete),
              let page = String(data: donnees, encoding: .utf8),
              let r = page.range(of: #""INNERTUBE_CLIENT_VERSION":"([0-9.]+)""#, options: .regularExpression) else { return }
        let version = page[r].split(separator: "\"").last.map(String.init)   // …:"1.2026…"
        if let version, version.first == "1" {
            UserDefaults.standard.set(version, forKey: cleVersion)
            UserDefaults.standard.set(Date.now, forKey: cleVersion + "Date")
        }
    }
    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let typesIgnores: Set<String> = ["Titre", "Vidéo", "Song", "Video", "Épisode", "Episode", "Single"]

    // MARK: Appel brut

    func appel(_ point: String, _ corps: [String: Any], suite: String? = nil) async throws -> Any {
        var adresse = "https://music.youtube.com/youtubei/v1/\(point)?prettyPrint=false"
        if let suite, let jeton = suite.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            adresse += "&ctoken=\(jeton)&continuation=\(jeton)&type=next"
        }
        guard let url = URL(string: adresse) else {
            throw ErreurReseau.indisponible
        }
        var requete = URLRequest(url: url, timeoutInterval: 10)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        requete.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        requete.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        var complet = corps
        complet["context"] = ["client": Self.client]
        requete.httpBody = try JSONSerialization.data(withJSONObject: complet)
        var (donnees, reponse) = try await URLSession.shared.data(for: requete)
        if let http = reponse as? HTTPURLResponse, [400, 403].contains(http.statusCode) {
            // Refus : YouTube a peut-être changé de version → on la relit et on réessaie une fois.
            await Self.actualiserVersion(forcer: true)
            complet["context"] = ["client": Self.client]
            requete.httpBody = try JSONSerialization.data(withJSONObject: complet)
            (donnees, reponse) = try await URLSession.shared.data(for: requete)
        }
        if let http = reponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ErreurReseau.statut(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: donnees)
    }

    // MARK: Recherche

    /// Deux requêtes en parallèle : filtre « Titres », puis recherche simple (les clips en plus).
    func rechercher(_ requete: String) async throws -> ResultatsRecherche {
        async let filtres = try? listeTitres(requete, params: Self.filtreTitres)
        async let simples = try? listeTitres(requete, params: nil)
        let (titres, tout) = await (filtres, simples)
        guard titres != nil || tout != nil else { throw ErreurReseau.indisponible }
        let trouves = titres ?? []
        let deja = Set(trouves.map(\.idVideo))
        return ResultatsRecherche(titres: trouves, videos: (tout ?? []).filter { !deja.contains($0.idVideo) })
    }

    func suggestions(_ debut: String) async throws -> [String] {
        let json = try await appel("music/get_search_suggestions", ["input": debut])
        var vues = Set<String>()
        return ArbreJSON.tous("searchSuggestionRenderer", dans: json)
            .compactMap { ArbreJSON.texteRuns(ArbreJSON.valeur($0, "suggestion", "runs")) }
            .filter { vues.insert($0.lowercased()).inserted }
    }

    private func listeTitres(_ requete: String, params: String?) async throws -> [Titre] {
        var corps: [String: Any] = ["query": requete]
        if let params { corps["params"] = params }
        let json = try await appel("search", corps)
        var vus = Set<String>()
        return ArbreJSON.tous("musicResponsiveListItemRenderer", dans: json)
            .compactMap(Self.titre(depuis:))
            .filter { vus.insert($0.idVideo).inserted }
    }

    /// musicResponsiveListItemRenderer → Titre (nil pour artistes, albums, playlists).
    static func titre(depuis r: [String: Any]) -> Titre? {
        let colonnes = r["flexColumns"] as? [[String: Any]] ?? []
        func runs(_ i: Int) -> [[String: Any]] {
            guard colonnes.indices.contains(i) else { return [] }
            return ArbreJSON.valeur(colonnes[i], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [[String: Any]] ?? []
        }
        let runsTitre = runs(0)
        guard let nom = runsTitre.first?["text"] as? String else { return nil }
        let idVideo = (ArbreJSON.valeur(r, "playlistItemData", "videoId") as? String)
            ?? (ArbreJSON.valeur(r, "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                                 "playNavigationEndpoint", "watchEndpoint", "videoId") as? String)
            ?? (ArbreJSON.valeur(runsTitre.first, "navigationEndpoint", "watchEndpoint", "videoId") as? String)
        guard let idVideo else { return nil }

        // 2e colonne : « [Titre •] Artiste • Album • 3:45 » ou « Vidéo • Artiste • 12 M de vues • 3:45 »
        let infos = runs(1)
        let segments = infos.compactMap { $0["text"] as? String }.joined()
            .components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let artistesLies = infos.filter {
            (ArbreJSON.valeur($0, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
                              "browseEndpointContextMusicConfig", "pageType") as? String) == "MUSIC_PAGE_TYPE_ARTIST"
        }.compactMap { $0["text"] as? String }
        let artiste = artistesLies.isEmpty
            ? (segments.first { !typesIgnores.contains($0) && lireDuree($0) == nil && !$0.contains("lecture") && !$0.contains("vues") } ?? "")
            : artistesLies.joined(separator: ", ")

        let texteFixe = ArbreJSON.texteRuns(ArbreJSON.valeur(r, "fixedColumns", 0, "musicResponsiveListItemFixedColumnRenderer", "text", "runs"))
        let duree = segments.last.flatMap(lireDuree) ?? texteFixe.flatMap(lireDuree)

        let vignettes = ArbreJSON.valeur(r, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails") as? [[String: Any]]
        let miniature = grandeImage(vignettes?.last?["url"] as? String, idVideo: idVideo)
        let (idArtiste, idAlbum, album) = liens(infos)
        let explicite = (r["badges"] as? [[String: Any]])?.contains {
            (ArbreJSON.valeur($0, "musicInlineBadgeRenderer", "icon", "iconType") as? String) == "MUSIC_EXPLICIT_BADGE"
        } ?? false
        return Titre(idVideo: idVideo, nom: nom, artiste: artiste, duree: duree, miniature: miniature,
                     idArtiste: idArtiste, idAlbum: idAlbum, album: album, explicite: explicite ? true : nil)
    }

    /// Premier artiste et album liés dans une ligne de texte InnerTube.
    static func liens(_ runs: [[String: Any]]) -> (artiste: String?, album: String?, nomAlbum: String?) {
        func type(_ r: [String: Any]) -> String? {
            ArbreJSON.valeur(r, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
                             "browseEndpointContextMusicConfig", "pageType") as? String
        }
        let artiste = runs.first { type($0) == "MUSIC_PAGE_TYPE_ARTIST" }
        let album = runs.first { type($0) == "MUSIC_PAGE_TYPE_ALBUM" }
        return (ArbreJSON.valeur(artiste, "navigationEndpoint", "browseEndpoint", "browseId") as? String,
                ArbreJSON.valeur(album, "navigationEndpoint", "browseEndpoint", "browseId") as? String,
                album?["text"] as? String)
    }

    /// Les vignettes de recherche font 60 px : on demande une version 544 px.
    static func grandeImage(_ brute: String?, idVideo: String) -> URL? {
        let secours = URL(string: "https://i.ytimg.com/vi/\(idVideo)/hqdefault.jpg")
        guard var url = brute else { return secours }
        if let r = url.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
            url.replaceSubrange(r, with: "=w544-h544")
        } else if url.contains("i.ytimg.com") {
            return secours
        }
        return URL(string: url) ?? secours
    }

    // MARK: Pages YouTube Music (accueil, explorer, artistes, albums, playlists)

    func page(_ idPage: String, params: String? = nil) async throws -> PageYTM {
        var corps: [String: Any] = ["browseId": idPage]
        if let params { corps["params"] = params }
        return AnalyseYTM.page(try await appel("browse", corps), idPage: idPage)
    }

    func suitePage(_ jeton: String) async throws -> PageYTM {
        AnalyseYTM.suite(try await appel("browse", [:], suite: jeton))
    }

    /// Recherche façon YouTube Music : meilleur résultat, puis tout mélangé ; `params` = puce choisie.
    func recherchePage(_ requete: String, params: String? = nil) async throws -> PageYTM {
        var corps: [String: Any] = ["query": requete]
        if let params { corps["params"] = params }
        return AnalyseYTM.recherche(try await appel("search", corps))
    }

    // MARK: Classements et nouveautés par pays

    /// Classements YouTube Music d'un pays (« FR », « US »…, « ZZ » pour le monde).
    func classements(_ pays: String) async throws -> PageYTM {
        AnalyseYTM.page(try await appel("browse", ["browseId": "FEmusic_charts", "formData": ["selectedValues": [pays]]]))
    }

    /// Nouveautés vraiment récentes (voir Nouveautes.swift), gardées 3 heures.
    func nouveautes(_ codesApple: [String]) async throws -> [Nouveautes.Sortie] {
        let cle = codesApple.joined(separator: "+")
        if let connu = await CacheNouveautes.partage.lire(cle) { return connu }
        let sorties = await Nouveautes.sorties(codesApple)
        // Liste trop courte : le serveur d'Apple a répondu à moitié → on garde la précédente si elle est plus complète.
        if sorties.count < 5, let precedente = await CacheNouveautes.partage.secours(cle), precedente.count > sorties.count {
            return precedente
        }
        if !sorties.isEmpty { await CacheNouveautes.partage.ecrire(cle, sorties) }
        return sorties
    }

    /// Retrouve sur YouTube Music un album ou un titre connu par son nom (« Artiste Titre »).
    func trouverAlbum(_ requete: String) async throws -> Carte? {
        let page = try await recherchePage(requete, params: "EgWKAQIYAWoSEAUQAxAKEAkQBBAQEBUQERAO")
        return page.sections.flatMap(\.elements).lazy.compactMap { e -> Carte? in
            if case .carte(let c) = e, c.type == .album { c } else { nil }
        }.first
    }

    func trouverTitre(_ requete: String) async throws -> Titre? {
        try await recherchePage(requete, params: "EgWKAQIIAWoSEAUQAxAKEAkQBBAQEBUQERAO").sections.flatMap(\.titres).first
    }

    // MARK: Recommandations (« radio » de YouTube Music)

    /// Titres dans le même esprit que `idVideo` : la file « À suivre » que YouTube Music lance après un titre.
    func radio(_ idVideo: String) async throws -> [Titre] {
        let json = try await appel("next", ["videoId": idVideo, "playlistId": "RDAMVM" + idVideo, "isAudioOnly": true,
                                            "enablePersistentPlaylistPanel": true])
        var vus = Set<String>()
        return ArbreJSON.tous("playlistPanelVideoRenderer", dans: json)
            .compactMap(AnalyseYTM.titreFile)
            .filter { vus.insert($0.idVideo).inserted }
    }

    /// Onglet « Similaires » : titres, artistes et playlists proches.
    func similaires(_ idVideo: String) async throws -> [Rangee] {
        let suite = try await appel("next", ["videoId": idVideo])
        guard let id = ArbreJSON.premiereChaine(dans: suite, ou: { $0 == "browseId" && $1.hasPrefix("MPTR") }) else { return [] }
        return try await page(id).sections
    }

    // MARK: Paroles (onglet « Paroles » de YouTube Music)

    /// next → browseId « MPLY… » → browse → musicDescriptionShelfRenderer.
    func parolesYouTubeMusic(_ idVideo: String) async throws -> (texte: String, source: String)? {
        let suite = try await appel("next", ["videoId": idVideo])
        guard let idParoles = ArbreJSON.premiereChaine(dans: suite, ou: { $0 == "browseId" && $1.hasPrefix("MPLY") }) else {
            return nil
        }
        let page = try await appel("browse", ["browseId": idParoles])
        guard let bloc = ArbreJSON.tous("musicDescriptionShelfRenderer", dans: page).first,
              let texte = ArbreJSON.texteRuns(ArbreJSON.valeur(bloc, "description", "runs")) else { return nil }
        let source = ArbreJSON.texteRuns(ArbreJSON.valeur(bloc, "footer", "runs")) ?? "YouTube Music"
        return (texte, source)
    }
}

/// Nouveautés gardées 3 heures en mémoire, et la dernière liste valide sur le téléphone (3 jours) :
/// si le serveur d'Apple ne répond pas, on montre la liste précédente plutôt qu'un vide.
actor CacheNouveautes {
    static let partage = CacheNouveautes()
    private var memoire: [String: (date: Date, sorties: [Nouveautes.Sortie])] = [:]
    private struct Sauvegarde: Codable { var date: Date; var sorties: [Nouveautes.Sortie] }
    private static let prefixe = "nouveautesReleaseRadar-"

    func lire(_ pays: String) -> [Nouveautes.Sortie]? {
        guard let m = memoire[pays], Date.now.timeIntervalSince(m.date) < 3 * 3600 else { return nil }
        return m.sorties
    }
    func ecrire(_ pays: String, _ sorties: [Nouveautes.Sortie]) {
        memoire[pays] = (.now, sorties)
        if let donnees = try? JSONEncoder().encode(Sauvegarde(date: .now, sorties: sorties)) {
            UserDefaults.standard.set(donnees, forKey: Self.prefixe + pays)
        }
    }
    /// Spotify vient d'être branché : les nouveautés sont recalculées.
    func vider() { memoire = [:] }
    /// Dernière liste valide, si elle a moins de 3 jours.
    func secours(_ pays: String) -> [Nouveautes.Sortie]? {
        guard let donnees = UserDefaults.standard.data(forKey: Self.prefixe + pays),
              let s = try? JSONDecoder().decode(Sauvegarde.self, from: donnees),
              Date.now.timeIntervalSince(s.date) < 3 * 86400 else { return nil }
        return s.sorties
    }
}

/// Réessaie une demande réseau qui échoue ou revient vide (réseau pas encore revenu à l'ouverture de l'app…).
func avecEssais<T>(_ essais: Int = 3, vide: (T) -> Bool = { _ in false }, _ demande: () async throws -> T) async -> T? {
    for essai in 1...essais {
        if let r = try? await demande(), !vide(r) { return r }
        if essai < essais { try? await Task.sleep(for: .seconds(Double(essai))) }
    }
    return nil
}

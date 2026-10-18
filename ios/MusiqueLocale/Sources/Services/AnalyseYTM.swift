import Foundation

// Lecture des réponses InnerTube de YouTube Music → PageYTM (sections, cartes, titres, en-tête).
// Les clés suivent celles de music.youtube.com (musicCarouselShelfRenderer, musicTwoRowItemRenderer…).
enum AnalyseYTM {
    typealias Objet = [String: Any]
    private static func v(_ racine: Any?, _ chemin: Any...) -> Any? {
        var courant = racine
        for etape in chemin {
            if let cle = etape as? String { courant = (courant as? Objet)?[cle] }
            else if let i = etape as? Int, let t = courant as? [Any], t.indices.contains(i) { courant = t[i] }
            else { return nil }
        }
        return courant
    }
    private static func texte(_ o: Any?) -> String? { ArbreJSON.texteRuns(v(o, "runs")) ?? (v(o, "simpleText") as? String) }

    // MARK: Pages

    /// browse (accueil, explorer, artiste, album, playlist, genre…).
    static func page(_ json: Any, idPage: String = "") -> PageYTM {
        let carteAlbum = idPage.hasPrefix("MPREb")
        var page = PageYTM()
        let colonneUnique = v(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer")
            ?? v(json, "contents", "sectionListRenderer")   // onglet « Similaires »
        let deuxColonnes = v(json, "contents", "twoColumnBrowseResultsRenderer")
        if let liste = colonneUnique as? Objet {
            page.sections = sections(liste["contents"])
            page.puces = puces(v(liste, "header", "chipCloudRenderer", "chips"))
            page.suite = v(liste, "continuations", 0, "nextContinuationData", "continuation") as? String
        }
        if let deux = deuxColonnes as? Objet {
            // Album / playlist : en-tête à gauche, titres à droite.
            let gauche = v(deux, "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents", 0) as? Objet
            if let h = gauche?["musicResponsiveHeaderRenderer"] as? Objet { page.entete = enteteAlbum(h) }
            let droite = v(deux, "secondaryContents", "sectionListRenderer") as? Objet
            page.sections = sections(droite?["contents"])
            page.suite = v(droite, "contents", 0, "musicPlaylistShelfRenderer", "continuations", 0, "nextContinuationData", "continuation") as? String
            // Les titres d'album n'ont pas de vignette : on leur donne la pochette de l'album.
            if let image = page.entete?.image, let i = page.sections.firstIndex(where: { $0.style == .liste }) {
                page.sections[i].elements = page.sections[i].elements.map {
                    guard case .titre(var t) = $0 else { return $0 }
                    if t.miniature == nil || t.miniature?.host == "i.ytimg.com" { t.miniature = image }
                    if t.artiste.isEmpty, let e = page.entete { t.artiste = e.artiste; t.idArtiste = t.idArtiste ?? e.idArtiste }
                    if t.idAlbum == nil, carteAlbum { t.idAlbum = idPage; t.album = page.entete?.nom }
                    return .titre(t)
                }
            }
        }
        if let h = v(json, "header", "musicImmersiveHeaderRenderer") as? Objet ?? v(json, "header", "musicVisualHeaderRenderer") as? Objet {
            page.entete = EntetePage(type: .artiste, nom: texte(h["title"]) ?? "",
                                     sousTitre: texte(h["monthlyListenerCount"]) ?? "",
                                     image: image(v(h, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), largeur: 1200),
                                     description: texte(h["description"]))
        } else if let h = v(json, "header", "musicHeaderRenderer") as? Objet {
            page.entete = EntetePage(type: .page, nom: texte(h["title"]) ?? "")
        }
        return page
    }

    /// Suite de l'accueil (continuationContents).
    static func suite(_ json: Any) -> PageYTM {
        var page = PageYTM()
        if let c = v(json, "continuationContents", "sectionListContinuation") as? Objet {
            page.sections = sections(c["contents"])
            page.suite = v(c, "continuations", 0, "nextContinuationData", "continuation") as? String
        } else if let c = v(json, "continuationContents", "musicPlaylistShelfContinuation") as? Objet {
            page.sections = [Rangee(titre: "", style: .liste, elements: elements(c["contents"]))]
            page.suite = v(c, "continuations", 0, "nextContinuationData", "continuation") as? String
        }
        return page
    }

    /// search : meilleur résultat + liste mélangée (titres, artistes, albums, playlists, vidéos).
    static func recherche(_ json: Any) -> PageYTM {
        var page = PageYTM()
        let liste = v(json, "contents", "tabbedSearchResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer") as? Objet
        page.puces = puces(v(liste, "header", "chipCloudRenderer", "chips"))
        page.sections = sections(liste?["contents"])
        page.suite = v(liste, "contents", 0, "musicShelfRenderer", "continuations", 0, "nextContinuationData", "continuation") as? String
        return page
    }

    // MARK: Sections

    static func sections(_ contenus: Any?) -> [Rangee] {
        var resultat: [Rangee] = []
        var enVrac: [Element] = []   // la recherche renvoie un résultat par itemSectionRenderer
        func viderVrac() {
            if !enVrac.isEmpty { resultat.append(Rangee(titre: "", style: .liste, elements: enVrac)); enVrac = [] }
        }
        for bloc in contenus as? [Objet] ?? [] {
            if let s = bloc["musicCarouselShelfRenderer"] as? Objet {
                viderVrac()
                let h = v(s, "header", "musicCarouselShelfBasicHeaderRenderer") as? Objet
                let items = elements(s["contents"])
                // Lignes de titres → « Sélection rapide » ; lignes d'artistes (classements) → carrousel de cartes rondes.
                let estGrille = (s["contents"] as? [Objet])?.first?["musicResponsiveListItemRenderer"] != nil
                    && items.contains { if case .titre = $0 { true } else { false } }
                let boutons = (s["contents"] as? [Objet])?.first?["musicNavigationButtonRenderer"] != nil
                guard !items.isEmpty else { continue }
                let large = (v(s, "contents", 0, "musicTwoRowItemRenderer", "aspectRatio") as? String)?.contains("16_9") == true
                resultat.append(Rangee(titre: texte(h?["title"]) ?? "", surtitre: texte(h?["strapline"]),
                                        style: boutons ? .boutons : estGrille ? .grilleTitres : .carrousel,
                                        elements: items, lien: carte(depuisLien: v(h, "title", "runs", 0, "navigationEndpoint"), nom: texte(h?["title"]) ?? ""),
                                        large: large,
                                        vignette: image(v(h, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), largeur: 120)))
            } else if let s = bloc["musicShelfRenderer"] as? Objet ?? bloc["musicPlaylistShelfRenderer"] as? Objet {
                viderVrac()
                let items = elements(s["contents"])
                guard !items.isEmpty else { continue }
                resultat.append(Rangee(titre: texte(s["title"]) ?? "", style: .liste, elements: items,
                                        lien: carte(depuisLien: v(s, "title", "runs", 0, "navigationEndpoint"), nom: texte(s["title"]) ?? "")))
            } else if let s = bloc["gridRenderer"] as? Objet {
                viderVrac()
                let items = elements(s["items"])
                let boutons = (s["items"] as? [Objet])?.first?["musicNavigationButtonRenderer"] != nil
                if !items.isEmpty {
                    resultat.append(Rangee(titre: texte(v(s, "header", "gridHeaderRenderer", "title")) ?? "", style: boutons ? .boutons : .carrousel, elements: items))
                }
            } else if let s = bloc["musicCardShelfRenderer"] as? Objet {
                // Meilleur résultat de la recherche.
                viderVrac()
                var items: [Element] = []
                if let principal = carte(depuisLien: v(s, "title", "runs", 0, "navigationEndpoint"), nom: texte(s["title"]) ?? "",
                                         sousTitre: texte(s["subtitle"]) ?? "", image: image(v(s, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"))) {
                    items.append(.carte(principal))
                } else if let id = v(s, "title", "runs", 0, "navigationEndpoint", "watchEndpoint", "videoId") as? String {
                    let sous = texte(s["subtitle"]) ?? ""
                    items.append(.titre(Titre(idVideo: id, nom: texte(s["title"]) ?? "", artiste: artisteDepuis(sous),
                                              duree: nil, miniature: image(v(s, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails")) )))
                }
                let nomPrincipal = texte(s["title"]) ?? ""
                let idPrincipal = v(s, "title", "runs", 0, "navigationEndpoint", "browseEndpoint", "browseId") as? String
                items += elements(s["contents"]).map {
                    guard case .titre(var t) = $0, t.artiste.isEmpty || lireDuree(t.artiste) != nil else { return $0 }
                    t.artiste = nomPrincipal
                    if idPrincipal?.hasPrefix("UC") == true { t.idArtiste = idPrincipal }
                    return .titre(t)
                }
                if !items.isEmpty { resultat.append(Rangee(titre: "Meilleur résultat", style: .liste, elements: items)) }
            } else if let s = bloc["itemSectionRenderer"] as? Objet {
                enVrac += elements(s["contents"])
            }
        }
        viderVrac()
        // Ni podcasts, ni épisodes, ni clips vidéo (« Nouveaux clips musicaux », « Top music videos ») : l'app ne lit que le son.
        let exclus = ["podcast", "épisode", "clip", "music video"]
        return resultat.filter { r in !exclus.contains { r.titre.localizedCaseInsensitiveContains($0) } }
    }

    static func elements(_ contenus: Any?) -> [Element] {
        var vus = Set<String>()
        return (contenus as? [Objet] ?? []).compactMap { item -> Element? in
            if let r = item["musicResponsiveListItemRenderer"] as? Objet { return elementListe(r) }
            if let r = item["musicTwoRowItemRenderer"] as? Objet { return elementCarte(r) }
            if let r = item["musicNavigationButtonRenderer"] as? Objet { return boutonNavigation(r) }
            if let r = item["playlistPanelVideoRenderer"] as? Objet { return titreFile(r).map(Element.titre) }
            return nil
        }.filter { vus.insert($0.id).inserted }
    }

    // MARK: Éléments

    /// Ligne : titre (lecture) ou carte (artiste, album, playlist).
    private static func elementListe(_ r: Objet) -> Element? {
        if let c = carte(depuisLien: r["navigationEndpoint"], nom: texte(v(r, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text")) ?? "",
                         sousTitre: texte(v(r, "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text")) ?? "",
                         image: image(v(r, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"))) {
            return .carte(c)
        }
        return InnerTube.titre(depuis: r).map(Element.titre)
    }

    /// Carte carrée (ou ronde) : album, playlist, artiste, ou vidéo à lire.
    private static func elementCarte(_ r: Objet) -> Element? {
        let nom = texte(r["title"]) ?? ""
        let sous = texte(r["subtitle"]) ?? ""
        let vignettes = v(r, "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails")
        if let c = carte(depuisLien: r["navigationEndpoint"], nom: nom, sousTitre: sous, image: image(vignettes)) { return .carte(c) }
        let id = (v(r, "navigationEndpoint", "watchEndpoint", "videoId") as? String)
            ?? (v(r, "thumbnailOverlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId") as? String)
        guard let id else { return nil }
        return .titre(Titre(idVideo: id, nom: nom, artiste: artisteDepuis(sous), duree: nil, miniature: image(vignettes) ?? InnerTube.grandeImage(nil, idVideo: id)))
    }

    private static func boutonNavigation(_ r: Objet) -> Element? {
        guard let id = v(r, "clickCommand", "browseEndpoint", "browseId") as? String else { return nil }
        let couleur = (v(r, "solid", "leftStripeColor") as? NSNumber)?.uint32Value
        return .carte(Carte(idPage: id, params: v(r, "clickCommand", "browseEndpoint", "params") as? String, type: .page,
                            nom: texte(r["buttonText"]) ?? "", couleur: couleur.map { $0 & 0xFFFFFF }))
    }

    /// Élément de la file « À suivre » (endpoint next).
    static func titreFile(_ r: Objet) -> Titre? {
        guard let id = r["videoId"] as? String, let nom = texte(r["title"]) else { return nil }
        let runs = v(r, "longBylineText", "runs") as? [Objet] ?? []
        let artistes = runs.filter { pageType($0["navigationEndpoint"]) == "MUSIC_PAGE_TYPE_ARTIST" }.compactMap { $0["text"] as? String }
        let artiste = artistes.isEmpty ? (texte(r["shortBylineText"]) ?? "") : artistes.joined(separator: ", ")
        let (idArtiste, idAlbum, album) = InnerTube.liens(runs)
        return Titre(idVideo: id, nom: nom, artiste: artiste, duree: texte(r["lengthText"]).flatMap(lireDuree),
                     miniature: image(v(r, "thumbnail", "thumbnails")) ?? InnerTube.grandeImage(nil, idVideo: id),
                     idArtiste: idArtiste, idAlbum: idAlbum, album: album)
    }

    private static func enteteAlbum(_ h: Objet) -> EntetePage {
        let artiste = texte(h["straplineTextOne"]) ?? ""
        let sous = [texte(h["subtitle"]), artiste.isEmpty ? nil : artiste].compactMap { $0 }.joined(separator: " • ")
        return EntetePage(type: .album, nom: texte(h["title"]) ?? "", sousTitre: sous, detail: texte(h["secondSubtitle"]) ?? "",
                          artiste: artiste, idArtiste: v(h, "straplineTextOne", "runs", 0, "navigationEndpoint", "browseEndpoint", "browseId") as? String,
                          image: image(v(h, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails")),
                          description: texte(v(h, "description", "musicDescriptionShelfRenderer", "description")))
    }

    private static func puces(_ brutes: Any?) -> [Puce] {
        (brutes as? [Objet] ?? []).compactMap {
            guard let c = $0["chipCloudChipRenderer"] as? Objet, let nom = texte(c["text"]) else { return nil }
            // App 100 % musique : pas de podcasts, d'épisodes ni de profils.
            guard !["Podcasts", "Épisodes", "Profils"].contains(nom) else { return nil }
            let params = (v(c, "navigationEndpoint", "browseEndpoint", "params") ?? v(c, "navigationEndpoint", "searchEndpoint", "params")) as? String
            return Puce(nom: nom, params: params)
        }
    }

    // MARK: Outils

    private static func pageType(_ lien: Any?) -> String? {
        v(lien, "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType") as? String
    }

    static func carte(depuisLien lien: Any?, nom: String, sousTitre: String = "", image: URL? = nil) -> Carte? {
        guard let id = v(lien, "browseEndpoint", "browseId") as? String else { return nil }
        let type: TypeCarte
        switch pageType(lien) {
        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL": type = .artiste
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK": type = .album
        case "MUSIC_PAGE_TYPE_PLAYLIST": type = .playlist
        case nil where id.hasPrefix("UC"): type = .artiste
        case nil where id.hasPrefix("MPREb"): type = .album
        case nil where id.hasPrefix("VL"): type = .playlist
        default: type = .page
        }
        return Carte(idPage: id, params: v(lien, "browseEndpoint", "params") as? String, type: type, nom: nom, sousTitre: sousTitre, image: image)
    }

    /// « Titre • Ninho • 2023 » → « Ninho » ; « Ninho et Niska » reste tel quel.
    private static func artisteDepuis(_ sousTitre: String) -> String {
        let ignores: Set<String> = ["Titre", "Vidéo", "Single", "EP", "Album", "Playlist", "Song", "Video"]
        return sousTitre.components(separatedBy: " • ").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !ignores.contains($0) && !$0.isEmpty && Int($0) == nil } ?? sousTitre
    }

    /// Plus grande vignette, agrandie (les vignettes InnerTube font souvent 60 à 226 px).
    static func image(_ vignettes: Any?, largeur: Int = 544) -> URL? {
        guard var url = (vignettes as? [Objet])?.last?["url"] as? String else { return nil }
        if url.hasPrefix("//") { url = "https:" + url }
        if let r = url.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
            let hauteur = largeur <= 544 ? largeur : largeur * 5 / 12   // bannières d'artiste : 12/5
            url.replaceSubrange(r, with: "=w\(largeur)-h\(hauteur)")
        }
        return URL(string: url)
    }
}

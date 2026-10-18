import Foundation

// Teste, avec les vraies réponses de YouTube, tout ce dont l'app iPhone a besoin.
// Sortie en erreur (code 1) au premier problème : GitHub prévient alors par e-mail.
// Les contenus testés sont disponibles partout (les Mac de GitHub sont aux États-Unis, l'app en France).
var echecs: [String] = []
/// Sur GitHub (serveurs de data center, traités comme des robots par YouTube), certains contrôles ne peuvent pas
/// réussir : ils deviennent de simples avertissements (⚠), sans échec ni e-mail.
let dansLeCloud = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
func verifier(_ nom: String, avertissementDansLeCloud: Bool = false, essais: Int = 1, _ test: () async throws -> String?) async {
    var probleme: String?
    for essai in 1...essais {
        do { probleme = try await test() } catch { probleme = "\(error)" }
        if probleme == nil { break }
        if essai < essais { try? await Task.sleep(for: .seconds(5)) }   // sources externes capricieuses : on réessaie
    }
    guard let probleme else { print("✓ \(nom)"); return }
    if avertissementDansLeCloud && dansLeCloud { print("⚠ \(nom) — \(probleme) (normal depuis les serveurs de GitHub)"); return }
    echecs.append("\(nom) : \(probleme)"); print("✗ \(nom) — \(probleme)")
}

let it = InnerTube.partage
await InnerTube.actualiserVersion(forcer: true)
await verifier("Version du client YouTube Music") {
    UserDefaults.standard.string(forKey: "versionClientYTM") == nil ? "illisible sur music.youtube.com" : nil
}
await verifier("Accueil") {
    let p = try await it.page("FEmusic_home")
    return p.sections.isEmpty ? "aucune rangée" : p.sections.contains { $0.style == .grilleTitres } ? nil : "pas de « Sélection rapide »"
}
await verifier("Explorer") { try await it.page("FEmusic_explore").sections.count >= 3 ? nil : "moins de 3 rangées" }
await verifier("Recherche") {
    let r = try await it.recherchePage("ninho")
    return r.sections.flatMap(\.titres).count >= 5 ? (r.puces.isEmpty ? "pas de catégories" : nil) : "moins de 5 titres"
}
await verifier("Suggestions") { try await it.suggestions("nin").isEmpty ? "aucune" : nil }
await verifier("Page d'artiste") { try await it.page("UCBNTNHPngOpC-yeC8VpAPJQ").entete?.type == .artiste ? nil : "en-tête manquant" }
await verifier("Page d'album") { try await it.page("MPREb_TLwxTUtg1L9").titresPrincipaux.count >= 5 ? nil : "pistes manquantes" }
await verifier("Radio (recommandations)") { try await it.radio("1tClJjSEEpE").count >= 20 ? nil : "moins de 20 titres" }
await verifier("Similaires") { try await it.similaires("1tClJjSEEpE").isEmpty ? "vide" : nil }
await verifier("Classements France") { try await it.classements("FR").sections.isEmpty ? "vides" : nil }
await verifier("Nouveautés France", essais: 3) { try await it.nouveautes(["fr"]).count >= 5 ? nil : "moins de 5 sorties" }
await verifier("Lecture (son + clip)") {
    let flux = try await ExtracteurYouTubeKit().flux(pour: "dQw4w9WgXcQ")
    guard let audio = flux.audio else { return "pas de son" }
    var requete = URLRequest(url: audio)
    requete.setValue("bytes=0-1000", forHTTPHeaderField: "Range")
    let (_, reponse) = try await URLSession.shared.data(for: requete)
    let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
    if code != 206 && code != 200 { return "son refusé (HTTP \(code))" }
    return flux.video == nil ? "pas de clip (HLS)" : nil
}

await verifier("Recherche par catégorie (Titres, Vidéos, Albums, Artistes, Playlists)") {
    let base = try await it.recherchePage("angèle")
    var vides: [String] = []
    for puce in base.puces where ["Titres", "Vidéos", "Albums", "Artistes", "Playlists de la communauté"].contains(puce.nom) {
        if try await it.recherchePage("angèle", params: puce.params).sections.flatMap(\.elements).isEmpty { vides.append(puce.nom) }
    }
    return base.puces.count < 4 ? "catégories manquantes" : vides.isEmpty ? nil : "vide : \(vides.joined(separator: ", "))"
}
await verifier("Puces d'humeur de l'accueil") {
    let accueil = try await it.page("FEmusic_home")
    guard let puce = accueil.puces.first(where: { $0.nom == "Énergie" }) ?? accueil.puces.first else { return "aucune puce" }
    return try await it.page("FEmusic_home", params: puce.params).sections.isEmpty ? "« \(puce.nom) » vide" : nil
}
await verifier("Humeurs et genres") { try await it.page("FEmusic_moods_and_genres").sections.isEmpty ? "vide" : nil }
await verifier("Playlist de l'accueil (en-tête et titres)") {
    // Playlist prise sur l'accueil du jour : toujours disponible là où le test tourne.
    let accueil = try await it.page("FEmusic_home")
    guard let carte = accueil.sections.flatMap(\.elements).lazy.compactMap({ e -> Carte? in
        if case .carte(let c) = e, c.type == .playlist { c } else { nil }
    }).first else { return "aucune playlist sur l'accueil" }
    let p = try await it.page(carte.idPage, params: carte.params)
    guard p.titresPrincipaux.count >= 10 else { return "titres manquants (« \(carte.nom) »)" }
    return p.entete == nil ? "en-tête manquant" : nil
}
await verifier("Classements États-Unis et Monde") {
    let us = try await it.classements("US"), monde = try await it.classements("ZZ")
    return us.sections.isEmpty || monde.sections.isEmpty ? "vides" : nil
}
await verifier("Nouveautés États-Unis et Royaume-Uni", essais: 3) {
    let us = try await it.nouveautes(["us"]), gb = try await it.nouveautes(["gb"])
    return us.count < 5 ? "États-Unis : moins de 5" : gb.count < 3 ? "Royaume-Uni : moins de 3" : nil
}
await verifier("Nouveautés par univers (rap, pop, électro…) et albums / singles séparés", essais: 3) {
    let fr = try await it.nouveautes(["fr"]), us = try await it.nouveautes(["us"])
    let rapFR = fr.filter { $0.univers == .rap }, rapUS = us.filter { $0.univers == .rap }
    let univers = Set(us.map(\.univers))
    print("   France : \(Dictionary(grouping: fr, by: \.univers).mapValues(\.count).sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", "))")
    print("   États-Unis : \(Dictionary(grouping: us, by: \.univers).mapValues(\.count).sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", "))")
    print("   rap FR albums : \(rapFR.filter(\.album).prefix(4).map { if case .carte(let c) = $0.element { c.sousTitre } else { "" } })")
    if rapFR.filter(\.album).isEmpty || rapFR.filter({ !$0.album }).isEmpty { return "rap français : albums ou singles manquants" }
    if rapUS.isEmpty { return "rap US vide" }
    return univers.contains(.electro) && univers.contains(.pop) ? nil : "électro ou pop manquant aux États-Unis"
}
await verifier("Nouveautés par style précis (trap, drill, rap français, house…)", essais: 2) {
    let table = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../MusiqueLocale/Resources/genres-artistes.json").standardizedFileURL
    guard let donnees = try? Data(contentsOf: table),
          let fiches = try? JSONDecoder().decode([String: GenresArtistes.Fiche].self, from: donnees) else { return "table des styles absente" }
    var noms: [String: Set<String>] = [:]
    for (code, nom) in [("fr", "France"), ("us", "États-Unis")] {
        let sorties = try await it.nouveautes([code])
        let connus = sorties.filter { fiches[GenresArtistes.cle($0.artiste)]?.styles.isEmpty == false }.count
        let styles = Dictionary(uniqueKeysWithValues: StyleMusical.ranger(sorties.filter(\.album)) {
            StyleMusical.pour(fiches[GenresArtistes.cle($0.artiste)], univers: $0.univers, paysPage: code.uppercased())
        }.map { ($0.style.nom, $0.sorties) })
        noms[code] = Set(styles.keys)
        print("   \(nom), albums (\(connus)/\(sorties.count) artistes classés) : " + styles.sorted { $0.value.count > $1.value.count }
            .map { "\($0.key) \($0.value.count)" }.joined(separator: ", "))
        if let trap = styles[code == "fr" ? "Trap française" : "Trap américaine"] {
            print("     ex. : " + trap.prefix(5).map(\.artiste).joined(separator: ", "))
        }
    }
    if noms["fr"]?.contains("Rap français") != true && noms["fr"]?.contains("Trap française") != true { return "pas de rap français" }
    return noms["us"]?.contains("Trap américaine") == true || noms["us"]?.contains("Rap américain") == true ? nil : "pas de rap américain"
}
await verifier("Nouveautés retrouvées sur YouTube Music (album et single)") {
    guard let album = try await it.trouverAlbum("Ninho M.I.L.S 4") else { return "album introuvable" }
    guard let titre = try await it.trouverTitre("Ninho Jefe") else { return "titre introuvable" }
    return album.type == .album && !titre.idVideo.isEmpty ? nil : "résultat incorrect"
}
await verifier("Paroles YouTube Music") { try await it.parolesYouTubeMusic("1tClJjSEEpE") == nil ? "aucune" : nil }
await verifier("Paroles synchronisées (LRCLIB)", essais: 2) {
    var r = URLRequest(url: URL(string: "https://lrclib.net/api/search?track_name=Balance%20ton%20quoi&artist_name=Ang%C3%A8le")!)
    r.setValue("MusiqueLocale-iOS/1.0", forHTTPHeaderField: "User-Agent")
    let (d, rep) = try await URLSession.shared.data(for: r)
    let code = (rep as? HTTPURLResponse)?.statusCode ?? 0
    // Limite passagère ou site en panne : l'app retombe alors sur les paroles de YouTube Music.
    if code == 429 || code >= 500 { print("⚠ LRCLIB indisponible (\(code)), paroles YouTube Music utilisées"); return nil }
    return code == 200 && String(decoding: d, as: UTF8.self).contains("syncedLyrics") ? nil : "réponse \(code)"
}
await verifier("Clip : flux vidéo (HLS) et téléchargement (image + son)") {
    let flux = try await ExtracteurYouTubeKit().flux(pour: "dQw4w9WgXcQ")
    guard let hls = flux.video else { return "pas de HLS" }
    let (_, rep) = try await URLSession.shared.data(from: hls)
    if (rep as? HTTPURLResponse)?.statusCode != 200 { return "HLS refusé" }
    return flux.videoSeule == nil ? "pas de vidéo à télécharger" : nil
}
await verifier("Outil de lecture YouTube à jour (YouTubeKit)") {
    var r = URLRequest(url: URL(string: "https://api.github.com/repos/alexeichhorn/YouTubeKit/tags?per_page=20")!)
    r.setValue("MusiqueLocale", forHTTPHeaderField: "User-Agent")
    let (d, _) = try await URLSession.shared.data(for: r)
    let tags = (try JSONSerialization.jsonObject(with: d) as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    let num = { (v: String) in v.split(separator: ".").compactMap { Int($0) } }
    guard let derniere = tags.max(by: { num($0).lexicographicallyPrecedes(num($1)) }) else { return nil }
    return num(derniere).lexicographicallyPrecedes(num("0.4.9")) || derniere == "0.4.9" ? nil : "nouvelle version \(derniere) disponible (app : 0.4.9)"
}

await verifier("Lecture rapide (client visionOS, < 2 s)", avertissementDansLeCloud: true) {
    let debut = Date()
    let flux = try await ExtracteurDirect().flux(pour: "kJQP7kiw5Fk")
    let duree = Date().timeIntervalSince(debut)
    guard let audio = flux.audio, let hls = flux.video else { return "son ou clip manquant" }
    var r = URLRequest(url: audio); r.setValue("bytes=0-500000", forHTTPHeaderField: "Range")
    let code = (try await URLSession.shared.data(for: r).1 as? HTTPURLResponse)?.statusCode ?? 0
    let codeHLS = (try await URLSession.shared.data(from: hls).1 as? HTTPURLResponse)?.statusCode ?? 0
    if code != 206 { return "son refusé (HTTP \(code))" }
    if codeHLS != 200 { return "clip refusé (HTTP \(codeHLS))" }
    return duree < 2 ? nil : String(format: "trop lent (%.1f s)", duree)
}

await verifier("Vraie durée du titre (le lecteur d'Apple la double)", avertissementDansLeCloud: true) {
    // REMONTADA (1PLIKÉ140) dure 2:01 ; AVPlayer annonce 4:01 pour ce type de fichier.
    let flux = try await ExtracteurDirect().flux(pour: "fznfGLNZvGc")
    guard let d = flux.duree else { return "durée absente" }
    return abs(d - 121) <= 2 ? nil : String(format: "durée incorrecte (%.0f s au lieu de 121)", d)
}
await verifier("Téléchargement par morceaux (titre complet en < 15 s)", avertissementDansLeCloud: true) {
    let flux = try await PrechargeurFlux.partage.flux(pour: "kJQP7kiw5Fk")
    guard let audio = flux.audio else { return "pas de son" }
    let fichier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    defer { try? FileManager.default.removeItem(at: fichier) }
    let debut = Date()
    try await TelechargeurMorceaux.telecharger(audio, vers: fichier) { _ in }
    let duree = Date().timeIntervalSince(debut)
    let taille = (try FileManager.default.attributesOfItem(atPath: fichier.path)[.size] as? Int) ?? 0
    print(String(format: "   (%.1f Mo en %.1f s)", Double(taille) / 1e6, duree))
    if taille < 1_000_000 { return "fichier incomplet (\(taille) octets)" }
    return duree < 15 ? nil : String(format: "trop lent (%.0f s)", duree)
}
await verifier("Veille des sorties (dates exactes, récentes et à venir)", essais: 2) {
    let (recentes, _) = await VeilleSorties.partage.sorties(de: ["Jul", "Ninho", "Gims", "Tiakola", "Angèle", "Drake", "Taylor Swift"])
    print("   récentes : " + recentes.prefix(3).map { "\($0.artiste) « \($0.nom) »" }.joined(separator: ", "))
    return recentes.isEmpty ? "aucune sortie récente trouvée" : nil
}

print(echecs.isEmpty ? "\nTout fonctionne." : "\n\(echecs.count) problème(s).")
exit(echecs.isEmpty ? 0 : 1)

import Foundation

// Teste, avec les vraies réponses de YouTube, tout ce dont l'app iPhone a besoin.
// Sortie en erreur (code 1) au premier problème : GitHub prévient alors par e-mail.
var echecs: [String] = []
func verifier(_ nom: String, _ test: () async throws -> String?) async {
    do {
        if let probleme = try await test() { echecs.append("\(nom) : \(probleme)"); print("✗ \(nom) — \(probleme)") }
        else { print("✓ \(nom)") }
    } catch {
        echecs.append("\(nom) : \(error)"); print("✗ \(nom) — \(error)")
    }
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
await verifier("Nouveautés France") { try await it.nouveautes(["fr"]).count >= 5 ? nil : "moins de 5 sorties" }
await verifier("Lecture (son + clip)") {
    let flux = try await ExtracteurYouTubeKit().flux(pour: "1tClJjSEEpE")
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
await verifier("Playlist + suite (plus de 100 titres)") {
    let p = try await it.page("VLRDCLAK5uy_mXandMujpa1klEdyxHzQU-kyDqmVhk098")
    guard p.titresPrincipaux.count >= 20 else { return "titres manquants" }
    return p.entete == nil ? "en-tête manquant" : nil
}
await verifier("Classements États-Unis et Monde") {
    let us = try await it.classements("US"), monde = try await it.classements("ZZ")
    return us.sections.isEmpty || monde.sections.isEmpty ? "vides" : nil
}
await verifier("Nouveautés États-Unis et Royaume-Uni") {
    let us = try await it.nouveautes(["us"]), gb = try await it.nouveautes(["gb"])
    return us.count < 5 ? "États-Unis : moins de 5" : gb.count < 3 ? "Royaume-Uni : moins de 3" : nil
}
await verifier("Nouveautés retrouvées sur YouTube Music (album et single)") {
    guard let album = try await it.trouverAlbum("Ninho M.I.L.S 4") else { return "album introuvable" }
    guard let titre = try await it.trouverTitre("Ninho Jefe") else { return "titre introuvable" }
    return album.type == .album && !titre.idVideo.isEmpty ? nil : "résultat incorrect"
}
await verifier("Paroles YouTube Music") { try await it.parolesYouTubeMusic("1tClJjSEEpE") == nil ? "aucune" : nil }
await verifier("Paroles synchronisées (LRCLIB)") {
    var r = URLRequest(url: URL(string: "https://lrclib.net/api/search?track_name=Balance%20ton%20quoi&artist_name=Ang%C3%A8le")!)
    r.setValue("MusiqueLocale-iOS/1.0", forHTTPHeaderField: "User-Agent")
    let (d, rep) = try await URLSession.shared.data(for: r)
    let code = (rep as? HTTPURLResponse)?.statusCode ?? 0
    if code == 429 { return nil }   // limite passagère : l'app retombe sur YouTube Music
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

print(echecs.isEmpty ? "\nTout fonctionne." : "\n\(echecs.count) problème(s).")
exit(echecs.isEmpty ? 0 : 1)

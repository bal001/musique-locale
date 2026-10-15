import Foundation
import YouTubeKit

// Seul fichier qui dépend de YouTubeKit : pour changer d'extracteur, écrire un autre
// type conforme à `ExtracteurFlux` et le passer dans MusiqueLocaleApp.

struct FluxDisponibles: Sendable {
    var audio: URL?        // audio seul, m4a (AAC)
    var video: URL?        // flux HLS image + son, pour regarder le clip
    var videoSeule: URL?   // mp4 H.264 sans son (≤ 1080p), pour télécharger le clip (assemblé avec l'audio)
}

protocol ExtracteurFlux: Sendable {
    func flux(pour idVideo: String) async throws -> FluxDisponibles
}

enum ErreurFlux: LocalizedError {
    case introuvable
    var errorDescription: String? { "Aucun flux lisible pour ce titre." }
}

/// Méthode rapide (~0,5 s) : le lecteur de YouTube demandé comme l'app YouTube de l'Apple Vision Pro (client VISIONOS),
/// qui reçoit des liens prêts à lire (son, clip HLS, vidéo seule) sans page à télécharger ni signature à déchiffrer.
/// Si YouTube la refuse un jour, `PrechargeurFlux` retombe sur YouTubeKit (~4 s).
struct ExtracteurDirect: ExtracteurFlux {
    private static let client: [String: Any] = ["clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple",
                                                "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471",
                                                "hl": "fr", "gl": "FR"]
    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    func flux(pour idVideo: String) async throws -> FluxDisponibles {
        let visiteur = try await InnerTube.visiteur()
        var contexte = Self.client
        contexte["visitorData"] = visiteur
        var requete = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!, timeoutInterval: 8)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        requete.setValue(visiteur, forHTTPHeaderField: "X-Goog-Visitor-Id")
        requete.httpBody = try JSONSerialization.data(withJSONObject: ["videoId": idVideo, "context": ["client": contexte],
                                                                       "contentCheckOk": true, "racyCheckOk": true])
        let (donnees, _) = try await URLSession.shared.data(for: requete)
        guard let json = try JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              (json["playabilityStatus"] as? [String: Any])?["status"] as? String == "OK",
              let lecture = json["streamingData"] as? [String: Any] else { throw ErreurFlux.introuvable }
        let formats = (lecture["adaptiveFormats"] as? [[String: Any]] ?? []).filter { $0["url"] is String }
        func debit(_ f: [String: Any]) -> Int { f["bitrate"] as? Int ?? 0 }
        let audio = formats.filter { ($0["mimeType"] as? String)?.hasPrefix("audio/mp4") == true }.max { debit($0) < debit($1) }
        let videoSeule = formats.filter {
            ($0["mimeType"] as? String)?.hasPrefix("video/mp4; codecs=\"avc1") == true && ($0["height"] as? Int ?? 0) <= 1080
        }.max { ($0["height"] as? Int ?? 0, debit($0)) < ($1["height"] as? Int ?? 0, debit($1)) }
        let hls = (lecture["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
        let urlAudio = (audio?["url"] as? String).flatMap(URL.init(string:))
        guard urlAudio != nil || hls != nil else { throw ErreurFlux.introuvable }
        return FluxDisponibles(audio: urlAudio, video: hls, videoSeule: (videoSeule?["url"] as? String).flatMap(URL.init(string:)))
    }
}

/// Extraction par YouTubeKit (https://github.com/alexeichhorn/YouTubeKit), directement sur le téléphone.
/// Le service distant de l'auteur de la bibliothèque ne sert qu'en secours, si YouTube refuse l'extraction locale.
struct ExtracteurYouTubeKit: ExtracteurFlux {
    func flux(pour idVideo: String) async throws -> FluxDisponibles {
        do {
            return try await extraire(YouTube(videoID: idVideo, methods: [.local]))
        } catch {
            return try await extraire(YouTube(videoID: idVideo, methods: [.remote]))
        }
    }

    private func extraire(_ video: YouTube) async throws -> FluxDisponibles {
        let tous = try await video.streams
        let audio = tous.filterAudioOnly().filter { $0.fileExtension == .m4a }.highestAudioBitrateStream()
        let videoSeule = tous.filterVideoOnly()
            .filter { $0.fileExtension == .mp4 && ($0.videoResolution ?? 0) <= 1080 && ($0.videoCodec.map { "\($0)" }?.contains("avc") ?? true) }
            .max { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) }
        let hls = try? await video.livestreams.first?.url
        guard audio != nil || hls != nil else { throw ErreurFlux.introuvable }
        return FluxDisponibles(audio: audio?.url, video: hls, videoSeule: videoSeule?.url)
    }
}

/// Prépare les flux à l'avance et les garde 5 heures (les liens YouTube valent ~6 h) : le titre suivant de la file,
/// les premiers résultats d'une recherche, les premiers titres de l'accueil démarrent alors tout de suite.
/// Un titre touché pendant sa préparation attend celle-ci au lieu de recommencer.
actor PrechargeurFlux {
    static let partage = PrechargeurFlux()
    private let rapide: any ExtracteurFlux = ExtracteurDirect()
    private let secours: any ExtracteurFlux = ExtracteurYouTubeKit()
    private var connus: [String: (date: Date, flux: FluxDisponibles)] = [:]
    private var enCours: [String: Task<FluxDisponibles, Error>] = [:]

    func flux(pour idVideo: String) async throws -> FluxDisponibles {
        if let c = connus[idVideo], Date.now.timeIntervalSince(c.date) < 5 * 3600 { return c.flux }
        if let tache = enCours[idVideo] { return try await tache.value }
        let (rapide, secours) = (self.rapide, self.secours)
        let tache = Task {
            do { return try await rapide.flux(pour: idVideo) }
            catch { return try await secours.flux(pour: idVideo) }
        }
        enCours[idVideo] = tache
        defer { enCours[idVideo] = nil }
        let flux = try await tache.value
        connus[idVideo] = (.now, flux)
        if connus.count > 200, let ancien = connus.min(by: { $0.value.date < $1.value.date })?.key { connus[ancien] = nil }
        return flux
    }

    /// Lance la préparation sans attendre (3 titres au plus à la fois, pour ne pas encombrer la connexion).
    nonisolated func precharger(_ titres: [Titre]) {
        Task {
            for lot in stride(from: 0, to: min(titres.count, 6), by: 3).map({ Array(titres[$0..<min($0 + 3, titres.count, 6)]) }) {
                await withTaskGroup(of: Void.self) { groupe in
                    for t in lot { groupe.addTask { _ = try? await self.flux(pour: t.idVideo) } }
                }
            }
        }
    }

    /// Lien expiré ou refusé : on oublie ce flux pour le réextraire.
    func oublier(_ idVideo: String) { connus[idVideo] = nil }
}

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

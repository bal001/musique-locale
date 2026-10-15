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

/// Prépare les flux à l'avance et les garde 5 heures (les liens YouTube valent ~6 h) : le titre suivant de la file,
/// les premiers résultats d'une recherche, les premiers titres de l'accueil démarrent alors tout de suite.
/// Un titre touché pendant sa préparation attend celle-ci au lieu de recommencer (l'extraction prend ~4 s).
actor PrechargeurFlux {
    static let partage = PrechargeurFlux()
    private let extracteur: any ExtracteurFlux = ExtracteurYouTubeKit()
    private var connus: [String: (date: Date, flux: FluxDisponibles)] = [:]
    private var enCours: [String: Task<FluxDisponibles, Error>] = [:]

    func flux(pour idVideo: String) async throws -> FluxDisponibles {
        if let c = connus[idVideo], Date.now.timeIntervalSince(c.date) < 5 * 3600 { return c.flux }
        if let tache = enCours[idVideo] { return try await tache.value }
        let extracteur = self.extracteur
        let tache = Task { try await extracteur.flux(pour: idVideo) }
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

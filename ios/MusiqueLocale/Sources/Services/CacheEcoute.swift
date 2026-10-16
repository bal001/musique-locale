import Foundation

// Écoute sans attente : lu « en continu » d'un seul tenant, un son YouTube est bridé par YouTube et le lecteur
// d'Apple attend 10 à 16 s avant de démarrer (mesuré sur l'iPhone, « WaitingToMinimizeStalls »). On récupère donc le
// titre entier par morceaux (~1 s, TelechargeurMorceaux) et on le lit depuis le téléphone ; le titre suivant
// de la file sont récupérés à l'avance. Fichiers temporaires (Caches), 80 au plus, les plus anciens effacés.
actor CacheEcoute {
    static let partage = CacheEcoute()
    private let dossier: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Ecoute", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var enCours: [String: Task<URL, Error>] = [:]

    func fichier(pour idVideo: String, depuis url: URL) async throws -> URL {
        let cible = dossier.appendingPathComponent("\(idVideo).m4a")
        if FileManager.default.fileExists(atPath: cible.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: cible.path)
            return cible
        }
        if let tache = enCours[idVideo] { return try await tache.value }
        let tache = Task<URL, Error> {
            let temporaire = cible.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: temporaire)
            try await TelechargeurMorceaux.telecharger(url, vers: temporaire) { _ in }
            try? FileManager.default.removeItem(at: cible)
            try FileManager.default.moveItem(at: temporaire, to: cible)
            return cible
        }
        enCours[idVideo] = tache
        defer { enCours[idVideo] = nil }
        let resultat = try await tache.value
        nettoyer()
        return resultat
    }

    /// Récupère à l'avance les titres suivants (lien puis fichier), sans attendre.
    nonisolated func precharger(_ titres: [Titre]) {
        Task {
            for t in titres.prefix(1) {
                guard let flux = try? await PrechargeurFlux.partage.flux(pour: t.idVideo), let audio = flux.audio else { continue }
                do { _ = try await self.fichier(pour: t.idVideo, depuis: audio) }
                catch ErreurReseau.statut(403) { await PrechargeurFlux.partage.lienRefuse(t.idVideo) }
                catch {}
            }
        }
    }

    private func nettoyer() {
        guard let fichiers = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey]),
              fichiers.count > 80 else { return }
        let tries = fichiers.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for f in tries.prefix(fichiers.count - 80) { try? FileManager.default.removeItem(at: f) }
    }
}

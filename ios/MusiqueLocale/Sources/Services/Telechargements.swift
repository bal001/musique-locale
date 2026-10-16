import AVFoundation
import Foundation
import Observation
import UIKit

// Téléchargements sur le téléphone : audio m4a ou clip mp4, avec pochette et paroles.
// Un titre téléchargé est toujours lu depuis le fichier local (mode avion compris).
@Observable
@MainActor
final class Telechargements {
    private(set) var elements: [Telechargement] = []
    private(set) var enCours: [TelechargementEnCours] = []
    var erreur: String?

    @ObservationIgnored private let images = NSCache<NSString, UIImage>()

    init(extracteur: any ExtracteurFlux) {
        // `extracteur` gardé pour la compatibilité ; les flux viennent de PrechargeurFlux (rapide + secours).
        if let donnees = try? Data(contentsOf: Stockage.index),
           let liste = try? JSONDecoder().decode([Telechargement].self, from: donnees) {
            elements = liste.filter { Stockage.existe(Stockage.url($0.fichier)) }
        }
    }

    // MARK: Consultation

    func estTelecharge(_ idVideo: String, _ type: TypeTelechargement) -> Bool {
        elements.contains { $0.titre.idVideo == idVideo && $0.type == type }
    }

    func aUnTelechargement(_ idVideo: String) -> Bool {
        elements.contains { $0.titre.idVideo == idVideo }
    }

    func progression(_ idVideo: String) -> TelechargementEnCours? {
        enCours.first { $0.titre.idVideo == idVideo }
    }

    /// Fichier local à lire à la place de YouTube (le clip d'abord, il contient aussi le son).
    func fichierLocal(pour idVideo: String) -> (url: URL, video: Bool)? {
        for type in [TypeTelechargement.clip, .audio] {
            if let e = elements.first(where: { $0.titre.idVideo == idVideo && $0.type == type }) {
                let url = Stockage.url(e.fichier)
                if Stockage.existe(url) { return (url, type == .clip) }
            }
        }
        return nil
    }

    /// Pochette enregistrée (lue une fois puis gardée en mémoire).
    func imageLocale(_ idVideo: String) -> UIImage? {
        guard aUnTelechargement(idVideo) else { return nil }
        if let image = images.object(forKey: idVideo as NSString) { return image }
        guard let image = UIImage(contentsOfFile: Stockage.pochette(idVideo).path) else { return nil }
        images.setObject(image, forKey: idVideo as NSString)
        return image
    }

    // MARK: Actions

    func telecharger(_ titre: Titre, type: TypeTelechargement) {
        let cle = Telechargement.cle(titre.idVideo, type)
        guard !estTelecharge(titre.idVideo, type), !enCours.contains(where: { $0.id == cle }) else { return }
        enCours.append(TelechargementEnCours(titre: titre, type: type, fraction: nil))
        Task {
            await FileTelechargements.partage.entrer()
            defer { Task { await FileTelechargements.partage.sortir() } }
            do {
                // Lien refusé par YouTube (403) : un 2e essai avec un lien de la méthode de secours.
                for essai in 1...2 {
                    do {
                        let flux = try await PrechargeurFlux.partage.flux(pour: titre.idVideo)   // déjà prêt s'il a été écouté
                        var titre = titre
                        if titre.duree == nil, let d = flux.duree { titre.duree = Int(d.rounded()) }   // vraie durée gardée pour le hors-ligne
                        guard let url = type == .audio ? flux.audio : flux.videoSeule, type == .audio || flux.audio != nil else {
                            throw ErreurFlux.introuvable
                        }
                        let temporaire = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        try await TelechargeurMorceaux.telecharger(url, vers: temporaire) { [weak self] fraction in
                            Task { @MainActor in self?.avancer(cle, type == .clip ? fraction * 0.85 : fraction) }
                        }
                        try await terminer(titre, type, temporaire, son: type == .clip ? flux.audio : nil)
                        break
                    } catch ErreurReseau.statut(403) where essai == 1 {
                        await PrechargeurFlux.partage.lienRefuse(titre.idVideo)
                    }
                }
            } catch {
                echouer(cle, titre, error)
            }
        }
    }

    func supprimer(_ idVideo: String, _ type: TypeTelechargement) {
        guard let e = elements.first(where: { $0.titre.idVideo == idVideo && $0.type == type }) else { return }
        try? FileManager.default.removeItem(at: Stockage.url(e.fichier))
        elements.removeAll { $0.id == e.id }
        if !aUnTelechargement(idVideo) {
            try? FileManager.default.removeItem(at: Stockage.pochette(idVideo))
            try? FileManager.default.removeItem(at: Stockage.paroles(idVideo))
            images.removeObject(forKey: idVideo as NSString)
        }
        sauver()
    }

    // MARK: Suivi

    private func avancer(_ cle: String, _ fraction: Double) {
        guard let i = enCours.firstIndex(where: { $0.id == cle }) else { return }
        enCours[i].fraction = fraction
    }

    private func terminer(_ titre: Titre, _ type: TypeTelechargement, _ temporaire: URL, son: URL?) async throws {
        let cle = Telechargement.cle(titre.idVideo, type)
        let nom = "\(titre.idVideo).\(type.extensionFichier)"
        let destination = Stockage.url(nom)
        try? FileManager.default.removeItem(at: destination)
        if let son {
            try await Self.assembler(image: temporaire, son: son, vers: destination)
        } else {
            try FileManager.default.moveItem(at: temporaire, to: destination)
        }
        await enregistrerAnnexes(titre)
        elements.removeAll { $0.id == cle }
        elements.insert(Telechargement(titre: titre, type: type, fichier: nom, date: .now), at: 0)
        enCours.removeAll { $0.id == cle }
        sauver()
    }

    /// Clip : image (mp4 sans son) + son (m4a) réunis dans un seul mp4, sans réencodage.
    private static func assembler(image: URL, son distant: URL, vers destination: URL) async throws {
        let dossier = FileManager.default.temporaryDirectory
        let imageLocale = dossier.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.moveItem(at: image, to: imageLocale)
        let sonLocal = dossier.appendingPathComponent(UUID().uuidString + ".m4a")
        try await TelechargeurMorceaux.telecharger(distant, vers: sonLocal) { _ in }
        defer {
            try? FileManager.default.removeItem(at: imageLocale)
            try? FileManager.default.removeItem(at: sonLocal)
        }
        let composition = AVMutableComposition()
        let actifImage = AVURLAsset(url: imageLocale), actifSon = AVURLAsset(url: sonLocal)
        guard let pisteImage = try await actifImage.loadTracks(withMediaType: .video).first,
              let pisteSon = try await actifSon.loadTracks(withMediaType: .audio).first else { throw ErreurFlux.introuvable }
        let duree = try await actifImage.load(.duration)
        let plage = CMTimeRange(start: .zero, duration: duree)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(plage, of: pisteImage, at: .zero)
        let dureeSon = try await actifSon.load(.duration)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duree, dureeSon)), of: pisteSon, at: .zero)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ErreurFlux.introuvable
        }
        try await export.export(to: destination, as: .mp4)
    }

    /// Pochette et paroles à côté du fichier, pour l'écoute hors ligne.
    private func enregistrerAnnexes(_ titre: Titre) async {
        let id = titre.idVideo
        if !Stockage.existe(Stockage.pochette(id)), let url = titre.miniature,
           let reponse = try? await URLSession.shared.data(from: url) {
            try? reponse.0.write(to: Stockage.pochette(id), options: .atomic)
        }
        if !Stockage.existe(Stockage.paroles(id)), let paroles = await ServiceParoles.partage.paroles(pour: titre),
           let donnees = try? JSONEncoder().encode(paroles) {
            try? donnees.write(to: Stockage.paroles(id), options: .atomic)
        }
    }

    private func echouer(_ cle: String, _ titre: Titre, _ erreur: Error) {
        enCours.removeAll { $0.id == cle }
        self.erreur = "Échec du téléchargement de « \(titre.nom) » : \(erreur.localizedDescription)"
    }

    private func sauver() {
        guard let donnees = try? JSONEncoder().encode(elements) else { return }
        try? donnees.write(to: Stockage.index, options: .atomic)
    }
}

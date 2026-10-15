import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum Repetition { case aucune, tout, un }

enum ModeLecture: String, CaseIterable, Identifiable {
    case titre = "Titre"
    case video = "Vidéo"
    case paroles = "Paroles"
    var id: Self { self }
}

// Moteur de lecture : AVPlayer, file d'attente, lecture en arrière-plan,
// commandes de l'écran verrouillé. Lit le fichier local quand le titre est téléchargé.
@Observable
@MainActor
final class Lecteur {
    private(set) var file: [Titre] = []
    private(set) var index = 0
    private(set) var enLecture = false
    private(set) var position: Double = 0
    private(set) var duree: Double = 0
    private(set) var chargement = false
    private(set) var aDeLaVideo = false
    private(set) var depuisFichier = false
    private(set) var mode: ModeLecture = .titre
    var pleinEcran = false
    /// « Lecture automatique » : prolonge la file avec des titres similaires (interrupteur de la file d'attente).
    var lectureAuto = UserDefaults.standard.object(forKey: "lectureAuto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lectureAuto, forKey: "lectureAuto"); prolongerSiBesoin() }
    }
    /// « Lecture à partir de … » (playlist, album, mix…).
    private(set) var source: String?
    /// Mise en veille : arrêt à une heure donnée, ou à la fin du titre.
    private(set) var arretPrevu: Date?
    private(set) var arretFinDuTitre = false
    var erreur: String?

    /// Nombre de titres ajoutés en fin de file par les recommandations (« radio »).
    private(set) var ajoutsAuto = 0
    var repetition: Repetition = .aucune
    private(set) var aleatoire = false
    var enCours: Titre? { file.indices.contains(index) ? file[index] : nil }
    var aUnSuivant: Bool { index + 1 < file.count }

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let extracteur: any ExtracteurFlux
    @ObservationIgnored private let telechargements: Telechargements
    @ObservationIgnored private let historique: Historique
    @ObservationIgnored private var observateurTemps: Any?
    @ObservationIgnored private var observateurs: [NSObjectProtocol] = []
    @ObservationIgnored private var observateurStatut: NSKeyValueObservation?
    @ObservationIgnored private var tacheChargement: Task<Void, Never>?
    @ObservationIgnored private var pochette: MPMediaItemArtwork?
    @ObservationIgnored private var tacheRadio: Task<Void, Never>?
    @ObservationIgnored private var graineRadio: String?
    @ObservationIgnored private var derniereBonneEcoute: Titre?   // dernier titre écouté jusqu'au bout ou aimé
    @ObservationIgnored private var tacheVeille: Task<Void, Never>?
    @ObservationIgnored private var repriseApresInterruption = false
    /// Vraie durée du titre en cours (YouTube), prioritaire sur celle d'AVPlayer qui est doublée pour les sons YouTube.
    @ObservationIgnored private var dureeReelle: Double?
    @ObservationIgnored private var finTraitee = false
    @ObservationIgnored private var sautEnCours = false
    @ObservationIgnored private var debutInterruption = Date.distantPast

    init(extracteur: any ExtracteurFlux, telechargements: Telechargements, historique: Historique) {
        self.extracteur = extracteur
        self.telechargements = telechargements
        self.historique = historique
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        configurerCommandes()
        observer()
        restaurerSession()
    }

    // MARK: File d'attente

    /// Lance une liste. Comme YouTube Music, un titre seul est suivi de recommandations dans le même esprit,
    /// et une liste se prolonge par des recommandations quand elle arrive à sa fin.
    func jouer(_ titres: [Titre], depuis i: Int = 0, source: String? = nil) {
        guard titres.indices.contains(i) else { return }
        file = titres
        index = i
        ajoutsAuto = 0
        graineRadio = nil
        derniereBonneEcoute = titres[i]
        self.source = source
        charger()
        prolongerSiBesoin()
    }

    /// « Lancer la radio » / « Démarrer le mix » : ce titre puis des titres similaires.
    func lancerRadio(_ titre: Titre) {
        jouer([titre], source: "Mix de \(titre.nom)")
    }

    /// Prolonge la file avec des titres similaires quand il en reste moins de 3.
    /// Recommandations de YouTube Music (même algorithme que l'app officielle), affinées par vos goûts :
    /// jamais un titre 👎 ou zappé, ni un titre écouté récemment, ni une autre version d'un même morceau ;
    /// et la graine est le dernier titre vraiment écouté ou aimé, pour ne pas dériver après un zap.
    private func prolongerSiBesoin() {
        guard lectureAuto, file.count - index <= 3, let graine = derniereBonneEcoute ?? enCours, graine.idVideo != graineRadio else { return }
        graineRadio = graine.idVideo
        tacheRadio?.cancel()
        tacheRadio = Task {
            guard let proposes = try? await InnerTube.partage.radio(graine.idVideo), !Task.isCancelled else { return }
            let recents = Set(historique.ecoutes.prefix(25).map(\.idVideo))
            var deja = Set(file.map(\.idVideo))
            var morceaux = Set(file.map { Self.morceau($0) })
            let nouveaux = proposes.filter { t in
                guard !deja.contains(t.idVideo), !historique.jaimePas.contains(t.idVideo), !historique.zappes.contains(t.idVideo),
                      !historique.artisteEvite(t),
                      !recents.contains(t.idVideo), morceaux.insert(Self.morceau(t)).inserted else { return false }
                deja.insert(t.idVideo)
                return true
            }
            file += nouveaux
            ajoutsAuto += nouveaux.count
            PrechargeurFlux.partage.precharger(Array(file.dropFirst(index + 1).prefix(2)))
        }
    }

    /// « Lucid (Slowed) » et « Lucid – Sped Up » sont le même morceau.
    private static func morceau(_ t: Titre) -> String {
        let nom = t.nom.lowercased()
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+[-–|].*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return nom + "|" + (t.artiste.lowercased().components(separatedBy: ",").first ?? "")
    }

    // MARK: File d'attente (réorganiser, vider, mise en veille)

    func deplacer(depuis source: IndexSet, vers destination: Int) {
        let courant = enCours
        file.move(fromOffsets: source, toOffset: destination)
        if let courant, let i = file.firstIndex(of: courant) { index = i }
    }

    /// « Supprimer la file d'attente » : ne garde que le titre en cours.
    func viderFile() {
        guard let courant = enCours else { return }
        file = [courant]
        index = 0
        ajoutsAuto = 0
        graineRadio = nil
        prolongerSiBesoin()
    }

    /// Mise en veille dans `minutes`, ou à la fin du titre (`nil`).
    func programmerArret(minutes: Int?) {
        tacheVeille?.cancel()
        arretFinDuTitre = minutes == nil
        arretPrevu = minutes.map { Date.now.addingTimeInterval(Double($0) * 60) }
        guard let minutes else { return }
        tacheVeille = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            player.pause()
            arretPrevu = nil
        }
    }

    func annulerArret() {
        tacheVeille?.cancel()
        arretPrevu = nil
        arretFinDuTitre = false
    }

    func allerA(_ i: Int) {
        guard file.indices.contains(i) else { return }
        index = i
        charger()
        prolongerSiBesoin()
    }

    func retirer(_ i: Int) {
        guard file.indices.contains(i), i != index else { return }
        file.remove(at: i)
        if i < index { index -= 1 }
    }

    /// Ajoute en fin de file, avant les recommandations automatiques.
    func ajouterALaFile(_ titre: Titre) {
        if file.isEmpty { jouer([titre]); return }
        file.insert(titre, at: file.count - ajoutsAuto)
    }

    func ajouterEnSuivant(_ titre: Titre) {
        if file.isEmpty { jouer([titre]) } else { file.insert(titre, at: index + 1) }
    }

    /// Mélange les titres restants (le titre en cours ne bouge pas), comme le bouton aléatoire de YouTube Music.
    func basculerAleatoire() {
        aleatoire.toggle()
        guard aleatoire, index + 1 < file.count else { return }
        file = Array(file[...index]) + file[(index + 1)...].shuffled()
    }

    func basculerRepetition() {
        repetition = switch repetition { case .aucune: .tout; case .tout: .un; case .un: .aucune }
    }

    func suivant(automatique: Bool = false) {
        if automatique, arretFinDuTitre { arretFinDuTitre = false; player.pause(); return }
        if automatique, repetition == .un { chercher(a: 0); reprendre(); return }
        if let t = enCours {
            if automatique {
                derniereBonneEcoute = t
                historique.noterEcouteReelle(t, complete: true)
            } else if position < 30 {
                historique.noterZap(t)
            } else if position >= 60 {
                historique.noterEcouteReelle(t, complete: false)
            }
        }
        guard aUnSuivant else {
            if repetition == .tout, !file.isEmpty { index = 0; charger(); return }
            if automatique { player.pause(); chercher(a: 0) }
            return
        }
        index += 1
        charger()
        prolongerSiBesoin()
    }

    func precedent() {
        if position > 3 || index == 0 { chercher(a: 0); return }
        index -= 1
        charger()
    }

    // MARK: Commandes

    func basculer() {
        if enLecture {
            player.pause()
            repriseApresInterruption = false
        } else {
            reprendre()
        }
    }

    func reprendre() {
        guard player.currentItem != nil else { if enCours != nil { charger(depart: position) }; return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    /// Saut dans le titre : borné à la vraie fin ; la position affichée ne bouge plus pendant le saut
    /// (sinon la barre revenait un instant en arrière : « petits coups de bug »).
    func chercher(a secondes: Double) {
        let fin = (dureeReelle ?? duree) > 0 ? (dureeReelle ?? duree) - 0.5 : secondes
        let cible = max(0, min(secondes, fin))
        sautEnCours = true
        position = cible
        finTraitee = false
        player.seek(to: CMTime(seconds: cible, preferredTimescale: 600),
                    toleranceBefore: CMTime(seconds: 0.2, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.2, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.sautEnCours = false }
        }
        majNowPlaying()
    }

    /// Passer en mode Vidéo recharge le titre avec le flux mp4 (même position) si on n'a que l'audio.
    func changerMode(_ nouveau: ModeLecture) {
        mode = nouveau
        if nouveau == .video, !aDeLaVideo, enCours != nil {
            charger(depart: position, video: true, nouvelleEcoute: false)
        }
    }

    // MARK: Chargement

    private func charger(depart: Double = 0, video: Bool = false, nouvelleEcoute: Bool = true) {
        guard let titre = enCours else { return }
        tacheChargement?.cancel()
        player.replaceCurrentItem(with: nil)
        erreur = nil
        // Remise à zéro complète : rien de l'ancien titre (durée, fin, saut) ne doit influencer la barre.
        dureeReelle = titre.duree.map(Double.init)
        finTraitee = false
        sautEnCours = false
        position = depart
        duree = Double(titre.duree ?? 0)
        chargement = true
        aDeLaVideo = false
        if nouvelleEcoute {
            historique.ajouterEcoute(titre)
            pochette = nil
            chargerPochette(titre)
        }
        majNowPlaying()
        sauverSession()
        // Les 2 titres suivants se préparent pendant l'écoute : « suivant » démarre tout de suite.
        PrechargeurFlux.partage.precharger(Array(file.dropFirst(index + 1).prefix(2)))

        let veutVideo = video || mode == .video
        tacheChargement = Task {
            do {
                let choisi = try await source(pour: titre, video: veutVideo)
                guard !Task.isCancelled, enCours?.idVideo == titre.idVideo else { return }
                dureeReelle = choisi.duree ?? titre.duree.map(Double.init)
                if let d = dureeReelle, d > 0 { duree = d }
                finTraitee = false
                player.replaceCurrentItem(with: AVPlayerItem(url: choisi.url))
                if depart > 0 {
                    _ = await player.seek(to: CMTime(seconds: depart, preferredTimescale: 600))
                }
                aDeLaVideo = choisi.video
                depuisFichier = choisi.local
                chargement = false
                reprendre()
            } catch {
                guard !Task.isCancelled else { return }
                chargement = false
                erreur = "Lecture impossible : \(error.localizedDescription)"
            }
        }
    }

    /// Fichier téléchargé d'abord ; sinon flux YouTube (mp4 si la vidéo est demandée, m4a sinon).
    private func source(pour titre: Titre, video: Bool) async throws -> (url: URL, video: Bool, local: Bool, duree: Double?) {
        let connue = titre.duree.map(Double.init)
        let local = telechargements.fichierLocal(pour: titre.idVideo)
        if let local, local.video || !video { return (local.url, local.video, true, connue) }
        do {
            let flux = try await PrechargeurFlux.partage.flux(pour: titre.idVideo)
            // Vraie durée : YouTube, sinon le paramètre « dur= » du lien audio, sinon YouTube Music.
            let dansLien = flux.audio.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "dur" }?.value }.flatMap(Double.init)
            let duree = flux.duree ?? dansLien ?? connue
            if video, let hls = flux.video { return (hls, true, false, duree) }
            if let audio = flux.audio { return (audio, false, false, duree) }
            if let hls = flux.video { return (hls, true, false, duree) }
            throw ErreurFlux.introuvable
        } catch {
            // Hors ligne avec seulement l'audio téléchargé : on le lit quand même.
            if let local { return (local.url, local.video, true, connue) }
            throw error
        }
    }

    // MARK: Observation du player

    private func observer() {
        observateurTemps = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                          queue: .main) { [weak self] temps in
            MainActor.assumeIsolated { self?.tic(temps) }
        }
        observateurStatut = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] joueur, _ in
            let lit = joueur.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, self.enLecture != lit else { return }
                self.enLecture = lit
                self.majNowPlaying()
            }
        }
        let centre = NotificationCenter.default
        observateurs.append(centre.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem, !self.finTraitee else { return }
                self.finTraitee = true
                self.suivant(automatique: true)
            }
        })
        // Vocal (Snapchat, WhatsApp…), appel, Siri, vidéo dans une autre app : la musique s'arrête net
        // et libère le son et le micro ; quand plus aucune app n'utilise le son, elle reprend toute seule.
        observateurs.append(centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let suspendue = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt == AVAudioSession.InterruptionReason.appWasSuspended.rawValue
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    guard !suspendue else { return }   // ancienne interruption, sans effet
                    self.repriseApresInterruption = self.enLecture || self.repriseApresInterruption
                    self.debutInterruption = .now
                    self.player.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    // Reprise automatique si la musique jouait avant (et pas après une très longue coupure).
                    guard self.repriseApresInterruption, Date.now.timeIntervalSince(self.debutInterruption) < 20 * 60 else {
                        self.repriseApresInterruption = false
                        return
                    }
                    self.repriseApresInterruption = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))   // laisse l'autre app rendre le son
                        self.reprendre()
                    }
                }
            }
        })
        // Écouteurs ou casque débranchés : pause (comme toutes les apps de musique), pas de son dans le haut-parleur.
        observateurs.append(centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raison = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                if raison == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.player.pause() }
            }
        })
    }

    private func tic(_ temps: CMTime) {
        // Signaux d'un élément pas encore prêt (ou de l'ancien titre pendant un changement) : ignorés.
        guard player.currentItem?.status == .readyToPlay else { return }
        let s = temps.seconds
        if s.isFinite, !chargement, !sautEnCours { position = duree > 0 ? min(s, duree) : s }
        if Int(s) % 5 == 0 { sauverSession() }
        if let reelle = dureeReelle, reelle > 0 {
            // Vraie fin atteinte (AVPlayer, lui, croit que le titre dure deux fois plus) : titre suivant.
            if s.isFinite, s >= reelle - 0.3, !finTraitee, !sautEnCours, enLecture {
                finTraitee = true
                suivant(automatique: true)
            }
        } else if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, abs(d - duree) > 0.5 {
            duree = d
            majNowPlaying()
        }
    }

    // MARK: Reprise au lancement (file, titre et position, comme YouTube Music)

    private struct Session: Codable { var file: [Titre]; var index: Int; var position: Double; var ajoutsAuto: Int }
    private static let cleSession = "sessionLecture"

    private func sauverSession() {
        guard !file.isEmpty, let donnees = try? JSONEncoder().encode(Session(file: Array(file.prefix(200)), index: index, position: position, ajoutsAuto: ajoutsAuto)) else { return }
        UserDefaults.standard.set(donnees, forKey: Self.cleSession)
    }

    /// Prépare le dernier titre sans le lancer : le mini-lecteur réapparaît, « lecture » reprend au même endroit.
    private func restaurerSession() {
        guard let donnees = UserDefaults.standard.data(forKey: Self.cleSession),
              let s = try? JSONDecoder().decode(Session.self, from: donnees), s.file.indices.contains(s.index) else { return }
        file = s.file
        index = s.index
        position = s.position
        ajoutsAuto = min(s.ajoutsAuto, s.file.count)
        duree = Double(s.file[s.index].duree ?? 0)
    }

    // MARK: Écran verrouillé / Centre de contrôle

    private func configurerCommandes() {
        let centre = MPRemoteCommandCenter.shared()
        cibler(centre.playCommand) { $0.reprendre() }
        cibler(centre.pauseCommand) { $0.player.pause() }
        cibler(centre.togglePlayPauseCommand) { $0.basculer() }
        cibler(centre.nextTrackCommand) { $0.suivant() }
        cibler(centre.previousTrackCommand) { $0.precedent() }
        centre.changePlaybackPositionCommand.addTarget { [weak self] evenement in
            guard let e = evenement as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            MainActor.assumeIsolated { self?.chercher(a: t) }
            return .success
        }
    }

    private func cibler(_ commande: MPRemoteCommand, _ action: @escaping @MainActor (Lecteur) -> Void) {
        commande.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
            return .success
        }
    }

    private func majNowPlaying() {
        guard let titre = enCours else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: titre.nom,
            MPMediaItemPropertyArtist: titre.artiste,
            MPMediaItemPropertyPlaybackDuration: duree,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: enLecture ? 1.0 : 0.0,
        ]
        if let pochette { info[MPMediaItemPropertyArtwork] = pochette }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func chargerPochette(_ titre: Titre) {
        let locale = telechargements.imageLocale(titre.idVideo)
        Task {
            var image = locale
            if image == nil, let url = titre.miniature, let reponse = try? await URLSession.shared.data(from: url) {
                image = UIImage(data: reponse.0)
            }
            guard let image, enCours?.idVideo == titre.idVideo else { return }
            pochette = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            majNowPlaying()
        }
    }
}

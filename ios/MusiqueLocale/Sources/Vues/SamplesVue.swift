import AVFoundation
import AVKit
import SwiftUI

// Onglet « Samples » comme YouTube Music : clips plein écran qui défilent à la verticale, chacun joué
// en boucle sur 30 secondes à partir d'un passage du morceau. 👍, Enregistrer, Partager, « Lire » le titre entier.
// Les clips viennent de vos goûts (titres similaires à vos écoutes) et des tendances.
struct SamplesVue: View {
    let actif: Bool
    @Environment(Historique.self) private var historique
    @Environment(Lecteur.self) private var lecteur
    @Environment(Navigateur.self) private var navigateur
    @State private var titres: [Titre] = []
    @State private var visible: String?
    @State private var moteur = MoteurSamples()

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(titres) { t in
                        PageSample(titre: t, moteur: moteur, visible: visible == t.idVideo)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(t.idVideo)
                            .onAppear { if t.idVideo == titres.dropLast(3).last?.idVideo { Task { await completer() } } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visible)
            .overlay {
                if titres.isEmpty { ProgressView().tint(Palette.citron) }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .top)
        .task { if titres.isEmpty { await completer() } }
        .onChange(of: visible) { _, id in jouerVisible(id) }
        .onChange(of: actif) { _, oui in
            if oui { jouerVisible(visible) } else { moteur.arreter() }
        }
        .onChange(of: lecteur.enLecture) { _, lit in if lit { moteur.arreter() } }
    }

    private func jouerVisible(_ id: String?) {
        guard let id, let i = titres.firstIndex(where: { $0.idVideo == id }) else { return }
        // Les 3 clips suivants (et le précédent) se préparent pendant qu'on regarde celui-ci.
        moteur.precharger(Array(titres[i...min(titres.count - 1, i + 1)]))
        guard actif else { return }
        if lecteur.enLecture { lecteur.basculer() }   // comme YouTube Music : un sample met la lecture en pause
        moteur.jouer(titres[i])
    }

    /// Ajoute des clips : titres proches de vos dernières écoutes, puis tendances.
    private func completer() async {
        var nouveaux: [Titre] = []
        // Clips dans vos goûts : artistes préférés si l'app les connaît, sinon vos dernières écoutes.
        let graines = (historique.profilSuffisant ? historique.artistesPreferes(5) : Array(historique.ecoutes.prefix(5))).shuffled().prefix(2)
        for g in graines { nouveaux += (try? await InnerTube.partage.radio(g.idVideo))?.dropFirst().shuffled().prefix(12) ?? [] }
        if nouveaux.count < 10, let explorer = try? await InnerTube.partage.page("FEmusic_explore") {
            nouveaux += explorer.sections.flatMap(\.titres).shuffled()
        }
        let deja = Set(titres.map(\.idVideo))
        var vus = Set<String>()
        let ajout = nouveaux.filter { !deja.contains($0.idVideo) && !historique.jaimePas.contains($0.idVideo) && vus.insert($0.idVideo).inserted }
        titres += ajout.shuffled()
        if visible == nil {
            visible = titres.first?.idVideo
            moteur.precharger(Array(titres.prefix(1)))   // le premier préparé dès l'ouverture de l'app
        }
    }
}

/// Un clip : vidéo plein écran, infos en bas, boutons à droite.
private struct PageSample: View {
    let titre: Titre
    let moteur: MoteurSamples
    let visible: Bool
    @Environment(Historique.self) private var historique
    @Environment(Lecteur.self) private var lecteur
    @Environment(Navigateur.self) private var navigateur

    var body: some View {
        ZStack(alignment: .bottom) {
            ImageDistante(url: titre.miniature, rayon: 0).blur(radius: 30).opacity(0.5)
            if moteur.avecVideo.contains(titre.idVideo), let joueur = moteur.joueur(titre.idVideo) {
                CoucheVideo(player: joueur)
            } else {
                Pochette(titre: titre, rayon: 12).padding(40)
                    .frame(maxHeight: .infinity)
                    .overlay { if visible && !moteur.prets.contains(titre.idVideo) { ProgressView().tint(.white) } }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titre.nom).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    Text(titre.artiste).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 16)
                VStack(spacing: 22) {
                    bouton(historique.aime(titre) ? "hand.thumbsup.fill" : "hand.thumbsup", "J'aime") { historique.basculerJaime(titre) }
                    bouton("hand.thumbsdown", "Je n'aime pas") { historique.basculerJaimePas(titre) }
                    bouton("text.badge.plus", "Enregistrer") { navigateur.aEnregistrer = [titre] }
                    ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(titre.idVideo)")!) {
                        etiquette("arrowshape.turn.up.right", "Partager")
                    }
                    bouton("play.fill", "Lire") {
                        moteur.arreter()
                        lecteur.lancerRadio(titre)
                        lecteur.pleinEcran = true
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { moteur.basculer() }
    }

    private func bouton(_ icone: String, _ nom: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { etiquette(icone, nom) }.buttonStyle(.plain)
    }

    private func etiquette(_ icone: String, _ nom: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icone).font(.system(size: 24))
            Text(nom).font(.system(size: 11, weight: .semibold))
        }
    }
}

/// Lecteur des samples : chaque clip a son propre AVPlayer, préparé à l'avance (flux trouvé, chargé,
/// placé sur le passage choisi, mis en mémoire tampon) ; quand on arrive dessus, il démarre tout de suite.
@Observable
@MainActor
final class MoteurSamples {
    private(set) var prets: Set<String> = []          // clips prêts à démarrer
    private(set) var avecVideo: Set<String> = []
    private(set) var courant: String?
    @ObservationIgnored private var joueurs: [String: AVPlayer] = [:]
    @ObservationIgnored private var preparations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var boucles: [String: Any] = [:]
    @ObservationIgnored private var ordre: [String] = []
    private let maxEnMemoire = 5

    func joueur(_ id: String) -> AVPlayer? { joueurs[id] }

    /// Prépare les clips à venir (en parallèle) et libère ceux qui sont loin.
    func precharger(_ titres: [Titre]) {
        for t in titres where joueurs[t.idVideo] == nil && preparations[t.idVideo] == nil {
            preparations[t.idVideo] = Task { await preparer(t) }
        }
        let gardes = Set(titres.map(\.idVideo) + [courant].compactMap { $0 })
        for id in ordre where !gardes.contains(id) && ordre.count > maxEnMemoire { liberer(id) }
    }

    func jouer(_ titre: Titre) {
        let id = titre.idVideo
        if let ancien = courant, ancien != id { joueurs[ancien]?.pause() }
        courant = id
        try? AVAudioSession.sharedInstance().setActive(true)
        if let j = joueurs[id] {
            j.isMuted = false
            j.play()
        } else {
            if preparations[id] == nil { preparations[id] = Task { await preparer(titre) } }
        }
    }

    func basculer() {
        guard let id = courant, let j = joueurs[id] else { return }
        j.timeControlStatus == .paused ? j.play() : j.pause()
    }

    func arreter() {
        for j in joueurs.values { j.pause() }
    }

    private func preparer(_ titre: Titre) async {
        let id = titre.idVideo
        defer { preparations[id] = nil }
        guard let flux = try? await PrechargeurFlux.partage.flux(pour: id), let url = flux.video ?? flux.audio, !Task.isCancelled else { return }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 12
        let joueur = AVPlayer(playerItem: item)
        joueur.isMuted = true
        joueur.automaticallyWaitsToMinimizeStalling = false
        let duree = try? await item.asset.load(.duration).seconds
        let total = (duree?.isFinite == true && (duree ?? 0) > 0) ? duree! : Double(titre.duree ?? 120)
        let debut = total > 60 ? total * 0.35 : 0
        _ = await joueur.seek(to: CMTime(seconds: debut, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        guard !Task.isCancelled else { return }
        let fin = NSValue(time: CMTime(seconds: min(debut + 30, total), preferredTimescale: 600))
        boucles[id] = joueur.addBoundaryTimeObserver(forTimes: [fin], queue: .main) { [weak joueur] in
            _ = joueur?.seek(to: CMTime(seconds: debut, preferredTimescale: 600))
        }
        joueurs[id] = joueur
        ordre.append(id)
        if flux.video != nil { avecVideo.insert(id) }
        prets.insert(id)
        // Arrivé dessus pendant la préparation : on lance tout de suite.
        if courant == id {
            joueur.isMuted = false
            joueur.play()
        }
    }

    private func liberer(_ id: String) {
        if let b = boucles.removeValue(forKey: id) { joueurs[id]?.removeTimeObserver(b) }
        joueurs[id]?.pause()
        joueurs[id] = nil
        prets.remove(id)
        avecVideo.remove(id)
        ordre.removeAll { $0 == id }
    }
}

/// Couche vidéo plein écran (remplissage, comme les Samples).
private struct CoucheVideo: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> VueCouche {
        let v = VueCouche()
        v.couche.player = player
        v.couche.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: VueCouche, context: Context) { v.couche.player = player }

    final class VueCouche: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var couche: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

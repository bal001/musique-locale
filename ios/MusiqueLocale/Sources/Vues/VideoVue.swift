import AVFoundation
import SwiftUI
import UIKit

// Affiche la vidéo de l'AVPlayer partagé. Le calque est détaché en arrière-plan,
// sinon iOS met la lecture en pause (le son doit continuer, écran verrouillé compris).
struct VideoVue: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VueCalque {
        let vue = VueCalque()
        vue.brancher(player)
        return vue
    }

    func updateUIView(_ vue: VueCalque, context: Context) {
        vue.brancher(player)
    }

    final class VueCalque: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var calque: AVPlayerLayer { layer as! AVPlayerLayer }
        private weak var joueur: AVPlayer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            calque.videoGravity = .resizeAspect
            let centre = NotificationCenter.default
            centre.addObserver(self, selector: #selector(arriere), name: UIApplication.didEnterBackgroundNotification, object: nil)
            centre.addObserver(self, selector: #selector(avant), name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

        func brancher(_ player: AVPlayer) {
            joueur = player
            if UIApplication.shared.applicationState != .background, calque.player !== player {
                calque.player = player
            }
        }

        @objc private func arriere() { calque.player = nil }
        @objc private func avant() { calque.player = joueur }
    }
}

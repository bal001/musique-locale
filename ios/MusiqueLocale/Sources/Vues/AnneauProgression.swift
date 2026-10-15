import SwiftUI

// Anneau citron pour un téléchargement (roue indéterminée tant que la taille est inconnue).
struct AnneauProgression: View {
    let fraction: Double?
    var taille: CGFloat = 22

    var body: some View {
        Group {
            if let fraction {
                ZStack {
                    Circle().stroke(Palette.bord, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, fraction)))
                        .stroke(Palette.citron, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: fraction)
                }
            } else {
                ProgressView().tint(Palette.citron)
            }
        }
        .frame(width: taille, height: taille)
    }
}

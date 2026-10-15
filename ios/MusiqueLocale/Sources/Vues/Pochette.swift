import SwiftUI

// Pochette carrée : fichier local si le titre est téléchargé (hors ligne), sinon l'image YouTube.
struct Pochette: View {
    let titre: Titre
    var taille: CGFloat? = nil
    var rayon: CGFloat = 8

    @Environment(Telechargements.self) private var telechargements

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = telechargements.imageLocale(titre.idVideo) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ImageDistante(url: titre.miniature, rayon: 0)
                }
            }
            .frame(width: taille, height: taille)
            .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
    }
}

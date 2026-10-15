import SwiftUI

// Barre de lecture compacte au-dessus des onglets ; un toucher ouvre le lecteur plein écran.
struct MiniLecteur: View {
    @Environment(Lecteur.self) private var lecteur

    var body: some View {
        if let titre = lecteur.enCours {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Pochette(titre: titre, taille: 42, rayon: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titre.nom)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(lecteur.erreur ?? titre.artiste)
                            .font(.system(size: 12))
                            .foregroundStyle(lecteur.erreur == nil ? Palette.texte2 : Palette.danger)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { lecteur.precedent() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 18))
                            .frame(width: 36, height: 40)
                    }
                    .accessibilityLabel("Précédent")
                    if lecteur.chargement {
                        ProgressView().tint(Palette.citron).frame(width: 40, height: 40)
                    } else {
                        Button { lecteur.basculer() } label: {
                            Image(systemName: lecteur.enLecture ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .frame(width: 40, height: 40)
                        }
                    }
                    Button { lecteur.suivant() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 18))
                            .frame(width: 36, height: 40)
                    }
                    .disabled(!lecteur.aUnSuivant)
                    .accessibilityLabel("Suivant")
                }
                .foregroundStyle(Palette.texte)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                GeometryReader { geo in
                    Rectangle()
                        .fill(Palette.citron)
                        .frame(width: lecteur.duree > 0 ? geo.size.width * min(1, max(0, lecteur.position / lecteur.duree)) : 0)
                }
                .frame(height: 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { lecteur.pleinEcran = true }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }
}

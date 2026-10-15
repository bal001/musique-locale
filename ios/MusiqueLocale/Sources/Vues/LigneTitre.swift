import SwiftUI

// Ligne de liste : pochette, titre, artiste • durée, état du téléchargement, menu « … ».
struct LigneTitre: View {
    let titre: Titre
    var badge: String? = nil
    var numero: Int? = nil   // piste d'album
    let action: () -> Void

    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements

    private var estCourant: Bool { lecteur.enCours?.idVideo == titre.idVideo }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if let numero {
                        Text("\(numero)").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.texte2).frame(width: 28)
                    } else {
                        Pochette(titre: titre, taille: 52, rayon: 6)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(titre.nom)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(estCourant ? Palette.citron : Palette.texte)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if telechargements.aUnTelechargement(titre.idVideo) {
                                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.citron)
                            }
                            if titre.explicite == true { BadgeExplicite() }
                            if let badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Palette.citronVoile))
                                    .foregroundStyle(Palette.citron)
                            }
                            Text(titre.sousTitre)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.texte2)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let suivi = telechargements.progression(titre.idVideo) {
                AnneauProgression(fraction: suivi.fraction)
            }

            BoutonMenu(titre: titre)
        }
        .contextMenu { ActionsTitre(titre: titre) }
        .ligneSombre()
    }
}

/// Petit « E » des titres explicites, comme YouTube Music.
struct BadgeExplicite: View {
    var body: some View {
        Text("E").font(.system(size: 9, weight: .heavy))
            .frame(width: 14, height: 14)
            .background(RoundedRectangle(cornerRadius: 2).fill(Palette.texte2))
            .foregroundStyle(Palette.fond)
            .accessibilityLabel("Explicite")
    }
}

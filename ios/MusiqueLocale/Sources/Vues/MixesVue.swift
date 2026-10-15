import SwiftUI

/// « Mixés pour vous » : grandes cartes de mix (Mon supermix, Mix de …) avec 3 titres, ▶ et ⊕.
struct MixesPourVous: View {
    let mixes: [(nom: String, titres: [Titre])]
    @Environment(Lecteur.self) private var lecteur
    @Environment(Historique.self) private var historique

    var body: some View {
        if !mixes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mixés pour vous").font(.system(size: 22, weight: .bold)).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(mixes.indices, id: \.self) { carte(mixes[$0]) }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func carte(_ mix: (nom: String, titres: [Titre])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Mosaique(images: mix.titres.prefix(4).map(\.miniature)).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mix.nom).font(.system(size: 19, weight: .bold)).lineLimit(2)
                    Text("Musique Locale").font(.system(size: 13)).foregroundStyle(Palette.texte2)
                }
            }
            ForEach(Array(mix.titres.prefix(3).enumerated()), id: \.element.id) { i, t in
                Button { lecteur.jouer(mix.titres, depuis: i, source: mix.nom) } label: {
                    HStack(spacing: 10) {
                        Pochette(titre: t, taille: 40, rayon: 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.nom).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(t.artiste).font(.system(size: 12)).foregroundStyle(Palette.texte2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        BoutonMenu(titre: t, taille: 14)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { lecteur.jouer(mix.titres, source: mix.nom) } label: {
                    Image(systemName: "play.fill").font(.system(size: 18)).frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Lire le mix")
                Button { historique.creerPlaylist(mix.nom, titres: mix.titres) } label: {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 18)).frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Enregistrer le mix en playlist")
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: UIScreen.main.bounds.width - 56, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface2))
    }
}

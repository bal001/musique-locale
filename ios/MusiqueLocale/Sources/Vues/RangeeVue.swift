import SwiftUI

// Une rangée de page YouTube Music : carrousel de cartes, « Sélection rapide » en colonnes de 4,
// liste de titres, ou boutons (Nouveautés, Classements, genres).
struct RangeeVue: View {
    let rangee: Rangee
    var numeroter = false   // pistes d'album : numéro à la place de la pochette
    /// Recherche, similaires : toucher un titre lance sa radio (titres du même style), comme YouTube Music.
    /// Album, playlist : la liste se lit dans l'ordre.
    var radio = false
    @Environment(Lecteur.self) private var lecteur
    @Environment(\.noterConsultation) private var noter
    @Environment(Navigateur.self) private var navigateur

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !rangee.titre.isEmpty { entete }
            switch rangee.style {
            case .carrousel: carrousel
            case .grilleTitres: GrilleTitres(titres: rangee.titres)
            case .liste: liste
            case .boutons: boutons
            }
        }
    }

    private var entete: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let vignette = rangee.vignette {
                ImageDistante(url: vignette, ronde: true).frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let sur = rangee.surtitre {
                    Text(sur.uppercased()).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.texte2).lineLimit(1)
                }
                Text(rangee.titre).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.texte).lineLimit(2)
            }
            Spacer(minLength: 8)
            if rangee.style != .carrousel, rangee.titres.count > 1 {
                // « Tout lire » : lance tous les titres de la rangée.
                Button { lecteur.jouer(rangee.titres, source: rangee.titre) } label: {
                    Text("Tout lire").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else if let lien = rangee.lien {
                Button { navigateur.ouvrir(Route.pour(lien)) } label: {
                    Text("Plus").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var carrousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(rangee.elements) { e in
                    ToucheElement(element: e, liste: [], source: rangee.titre) { CarteVue(element: e, largeur: rangee.large ? 260 : 150, large: rangee.large) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var liste: some View {
        let titres = rangee.titres
        return LazyVStack(spacing: 0) {
            ForEach(Array(rangee.elements.enumerated()), id: \.element.id) { i, e in
                switch e {
                case .titre(let t):
                    LigneTitre(titre: t, numero: numeroter ? i + 1 : nil) {
                        noter?(e)
                        if radio { lecteur.lancerRadio(t) }
                        else { lecteur.jouer(titres, depuis: titres.firstIndex(of: t) ?? 0, source: rangee.titre.isEmpty ? nil : rangee.titre) }
                    }
                    .padding(.leading, 16)
                case .carte(let c):
                    Button {
                        noter?(e)
                        navigateur.ouvrir(Route.pour(c))
                    } label: { LigneCarte(carte: c) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var boutons: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(rangee.elements) { e in
                if case .carte(let c) = e {
                    Button { navigateur.ouvrir(Route.pour(c)) } label: {
                        HStack(spacing: 0) {
                            Rectangle().fill(c.couleur.map { Color(hex: $0) } ?? Palette.citron).frame(width: 6)
                            Text(c.nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 12)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 48)
                        .background(Palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Carte carrée (ronde pour un artiste) : image, nom, sous-titre.
struct CarteVue: View {
    let element: Element
    var largeur: CGFloat = 150
    var large = false   // clip : vignette 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch element {
            case .titre(let t):
                if large {
                    ImageDistante(url: t.miniature, rayon: 6).frame(width: largeur, height: largeur * 9 / 16)
                } else {
                    Pochette(titre: t, taille: largeur, rayon: 6)
                }
                textes(t.nom, t.artiste)
            case .carte(let c):
                ImageDistante(url: c.image, ronde: c.ronde)
                    .frame(width: largeur, height: large ? largeur * 9 / 16 : largeur)
                textes(c.nom, c.sousTitre, centre: c.ronde)
            }
        }
        .frame(width: largeur)
    }

    private func textes(_ nom: String, _ sous: String, centre: Bool = false) -> some View {
        VStack(alignment: centre ? .center : .leading, spacing: 2) {
            Text(nom).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.texte).lineLimit(2)
            Text(sous).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(2)
        }
        .multilineTextAlignment(centre ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centre ? .center : .leading)
    }
}

/// « Sélection rapide » : colonnes de 4 titres, qui défilent colonne par colonne.
struct GrilleTitres: View {
    let titres: [Titre]
    @Environment(Lecteur.self) private var lecteur

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(56), spacing: 4), count: min(4, max(1, titres.count))), spacing: 8) {
                ForEach(titres) { t in
                    Button { lecteur.lancerRadio(t) } label: {
                        HStack(spacing: 12) {
                            Pochette(titre: t, taille: 48, rayon: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    .foregroundStyle(lecteur.enCours?.idVideo == t.idVideo ? Palette.citron : Palette.texte)
                                HStack(spacing: 4) {
                                    if t.explicite == true { BadgeExplicite() }
                                    Text(t.artiste).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            BoutonMenu(titre: t)
                        }
                        .frame(width: UIScreen.main.bounds.width - 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { ActionsTitre(titre: t) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Ligne d'artiste, d'album ou de playlist (recherche, pages).
struct LigneCarte: View {
    let carte: Carte

    var body: some View {
        HStack(spacing: 12) {
            ImageDistante(url: carte.image, ronde: carte.ronde).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(carte.nom).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.texte).lineLimit(1)
                Text(carte.sousTitre).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.texte3)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Image distante carrée ou ronde, avec un fond neutre en attendant.
struct ImageDistante: View {
    let url: URL?
    var ronde = false
    var rayon: CGFloat = 6

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = image ?? url.flatMap({ ChargeurImages.partage.enMemoire($0) }) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Palette.surface2
                }
            }
            .clipShape(ronde ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: rayon, style: .continuous)))
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await ChargeurImages.partage.image(url)
            }
    }
}

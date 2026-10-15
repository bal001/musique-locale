import SwiftUI

// Page d'artiste, d'album, de playlist ou d'exploration (genre, humeur, nouveautés, classements),
// telle que YouTube Music l'affiche.
struct PageVue: View {
    let carte: Carte
    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @Environment(Historique.self) private var historique
    @State private var page: PageYTM?
    @State private var erreur: String?
    @State private var chargementSuite = false
    @State private var trouvee: Carte?   // vraie page YouTube Music d'un album des nouveautés

    private var titres: [Titre] { page?.titresPrincipaux ?? [] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let page {
                    entete(page.entete)
                    ForEach(Array(page.sections.enumerated()), id: \.element.id) { i, rangee in
                        RangeeVue(rangee: rangee, numeroter: carte.type == .album && i == 0)
                    }
                    if page.suite != nil {
                        ProgressView().tint(Palette.citron).frame(maxWidth: .infinity)
                            .onAppear { Task { await chargerSuite() } }
                    }
                } else if let erreur {
                    ContentUnavailableView("Page indisponible", systemImage: "wifi.slash", description: Text(erreur))
                        .padding(.top, 80)
                } else {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Palette.fond)
        .ignoresSafeArea(edges: carte.type == .artiste ? .top : [])
        .navigationTitle(carte.type == .artiste ? "" : (page?.entete == nil ? carte.nom : ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(carte.type == .artiste ? .hidden : .automatic, for: .navigationBar)
        .task { await charger() }
    }

    // MARK: En-têtes

    @ViewBuilder
    private func entete(_ e: EntetePage?) -> some View {
        if let e {
            switch e.type {
            case .artiste: enteteArtiste(e)
            case .album, .playlist: enteteAlbum(e)
            case .page: Text(e.nom).font(.system(size: 30, weight: .heavy)).padding(.horizontal, 16)
            }
        } else if carte.type == .page {
            Text(carte.nom).font(.system(size: 30, weight: .heavy)).padding(.horizontal, 16).padding(.top, 8)
        }
    }

    private func enteteArtiste(_ e: EntetePage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                ImageDistante(url: e.image, rayon: 0)
                    .frame(maxWidth: .infinity).frame(height: 360)
                    .clipped()
                LinearGradient(colors: [.clear, Palette.fond], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.nom).font(.system(size: 40, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                    if !e.sousTitre.isEmpty {
                        Text(e.sousTitre).font(.system(size: 14)).foregroundStyle(Palette.texte2)
                    }
                }
                .padding(.horizontal, 16)
            }
            boutonsLecture(radio: true)
        }
    }

    private func enteteAlbum(_ e: EntetePage) -> some View {
        VStack(spacing: 10) {
            ImageDistante(url: e.image, rayon: 8)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            Text(e.nom).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center).padding(.top, 6)
            if !e.sousTitre.isEmpty { Text(e.sousTitre).font(.system(size: 14)).foregroundStyle(Palette.texte2).multilineTextAlignment(.center) }
            if !e.detail.isEmpty { Text(e.detail).font(.system(size: 13)).foregroundStyle(Palette.texte3) }
            boutonsLecture(radio: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func boutonsLecture(radio: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                lecteur.jouer(titres.shuffled())
            } label: {
                Label("Aléatoire", systemImage: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .foregroundStyle(Palette.fond)
                    .background(Capsule().fill(Color.white))
            }
            Button {
                if radio, let premier = titres.first { lecteur.lancerRadio(premier) } else { lecteur.jouer(titres) }
            } label: {
                Label(radio ? "Radio" : "Lecture", systemImage: radio ? "dot.radiowaves.left.and.right" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
            }
            boutonEnregistrer(artiste: radio)
            if !radio {
                Button {
                    for t in titres { telechargements.telecharger(t, type: .audio) }
                } label: {
                    Image(systemName: titres.allSatisfy { telechargements.aUnTelechargement($0.idVideo) } ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tout télécharger")
            }
        }
        .buttonStyle(.plain)
        .disabled(titres.isEmpty)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: radio ? .leading : .center)
    }

    /// « S'abonner » (artiste) ou « Enregistrer dans la bibliothèque » (album, playlist), gardé sur le téléphone.
    private func boutonEnregistrer(artiste: Bool) -> some View {
        var aGarder = trouvee ?? carte
        if let e = page?.entete {
            aGarder.nom = e.nom
            aGarder.image = e.image ?? carte.image
            if aGarder.sousTitre.isEmpty { aGarder.sousTitre = e.sousTitre }
        }
        let garde = historique.estEnregistre(aGarder)
        return Button { historique.basculerEnregistrement(aGarder) } label: {
            if artiste {
                Text(garde ? "Abonné" : "S'abonner")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(garde ? Palette.texte2 : Palette.texte)
                    .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
            } else {
                Image(systemName: garde ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24)).frame(width: 44, height: 44)
            }
        }
        .accessibilityLabel(artiste ? (garde ? "Se désabonner" : "S'abonner") : (garde ? "Retirer de la bibliothèque" : "Enregistrer dans la bibliothèque"))
    }

    // MARK: Chargement

    private func charger() async {
        guard page == nil else { return }
        do {
            var cible = carte
            if let recherche = carte.aChercher {
                // Album des nouveautés : retrouvé sur YouTube Music par son nom.
                guard let trouve = try await InnerTube.partage.trouverAlbum(recherche.requete) else {
                    erreur = "Cet album n'est pas (encore) sur YouTube Music."
                    return
                }
                cible = trouve
                trouvee = trouve
            }
            page = try await InnerTube.partage.page(cible.idPage, params: cible.params)
        } catch {
            erreur = "Vérifie ta connexion."
        }
    }

    private func chargerSuite() async {
        guard let jeton = page?.suite, !chargementSuite else { return }
        chargementSuite = true
        defer { chargementSuite = false }
        guard let suite = try? await InnerTube.partage.suitePage(jeton) else { page?.suite = nil; return }
        // Playlist longue : la suite prolonge la liste des titres.
        if let i = page?.sections.firstIndex(where: { $0.style == .liste }), let ajout = suite.sections.first, ajout.style == .liste, ajout.titre.isEmpty {
            page?.sections[i].elements += ajout.elements
            page?.sections += suite.sections.dropFirst()
        } else {
            page?.sections += suite.sections
        }
        page?.suite = suite.suite
    }
}

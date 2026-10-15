import SwiftUI

// Menu d'un titre comme YouTube Music : feuille avec le titre en tête (👍, fermer), trois gros boutons
// (Lire ensuite · Enregistrer dans une playlist · Partager), puis la liste des actions.

/// Ouvre une page, la feuille d'un titre ou « Enregistrer dans une playlist », depuis n'importe où.
@Observable
@MainActor
final class Navigateur {
    var demande: Route?
    var menu: Titre?               // feuille « ⋮ » d'un titre
    var aEnregistrer: [Titre]?     // feuille « Enregistrer dans une playlist »
    func ouvrir(_ route: Route) { demande = route }
}

/// Bouton « ⋮ » qui ouvre la feuille du titre.
struct BoutonMenu: View {
    let titre: Titre
    var taille: CGFloat = 16
    @Environment(Navigateur.self) private var navigateur
    var body: some View {
        Button { navigateur.menu = titre } label: {
            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                .font(.system(size: taille, weight: .semibold))
                .foregroundStyle(Palette.texte2)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plus d'actions")
    }
}

struct FeuilleTitre: View {
    let titre: Titre
    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @Environment(Historique.self) private var historique
    @Environment(Navigateur.self) private var navigateur
    @Environment(\.dismiss) private var fermer
    @State private var veille = false

    private var lien: URL { URL(string: "https://music.youtube.com/watch?v=\(titre.idVideo)")! }
    private var estEnCours: Bool { lecteur.enCours?.idVideo == titre.idVideo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                entete
                HStack(spacing: 10) {
                    gros("Lire ensuite", "text.line.first.and.arrowtriangle.forward") { lecteur.ajouterEnSuivant(titre) }
                    gros("Enregistrer dans une playlist", "text.badge.plus") { navigateur.aEnregistrer = [titre] }
                    ShareLink(item: lien, subject: Text(titre.nom), message: Text("\(titre.nom) – \(titre.artiste)")) {
                        grosContenu("Partager", "arrowshape.turn.up.right")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                ligne("Démarrer le mix", "dot.radiowaves.left.and.right") { lecteur.lancerRadio(titre) }
                ligne("Ajouter à la file d'attente", "text.append") { lecteur.ajouterALaFile(titre) }
                if telechargements.estTelecharge(titre.idVideo, .audio) {
                    ligne("Supprimer le téléchargement", "trash", danger: true) { telechargements.supprimer(titre.idVideo, .audio) }
                } else {
                    ligne("Télécharger", "arrow.down.to.line") { telechargements.telecharger(titre, type: .audio) }
                }
                if let id = titre.idAlbum {
                    ligne("Accéder à l'album", "square.stack") {
                        navigateur.ouvrir(.page(Carte(idPage: id, type: .album, nom: titre.album ?? "Album")))
                    }
                }
                if let id = titre.idArtiste {
                    ligne("Accéder à l'artiste", "person") {
                        navigateur.ouvrir(.page(Carte(idPage: id, type: .artiste, nom: titre.artiste)))
                    }
                }
                if estEnCours {
                    ligne("Supprimer la file d'attente", "list.bullet.rectangle") { lecteur.viderFile() }
                    ligne(lecteur.arretPrevu != nil || lecteur.arretFinDuTitre ? "Mise en veille · activée" : "Mise en veille", "moon.zzz", fermerApres: false) {
                        veille = true
                    }
                }
                ligne(historique.aimePas(titre) ? "Retirer « Je n'aime pas »" : "Je n'aime pas", "hand.thumbsdown") {
                    historique.basculerJaimePas(titre)
                    if estEnCours, historique.aimePas(titre) { lecteur.suivant() }
                }
            }
            .padding(.bottom, 20)
        }
        .foregroundStyle(Palette.texte)
        .confirmationDialog("Mise en veille", isPresented: $veille, titleVisibility: .visible) {
            ForEach([5, 10, 15, 30, 45, 60], id: \.self) { m in
                Button("\(m) minutes") { lecteur.programmerArret(minutes: m); fermer() }
            }
            Button("Fin du titre") { lecteur.programmerArret(minutes: nil); fermer() }
            if lecteur.arretPrevu != nil || lecteur.arretFinDuTitre {
                Button("Désactiver", role: .destructive) { lecteur.annulerArret(); fermer() }
            }
        }
    }

    private var entete: some View {
        HStack(spacing: 12) {
            Pochette(titre: titre, taille: 52, rayon: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre.nom).font(.system(size: 16, weight: .bold)).lineLimit(2)
                Text(titre.artiste).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { historique.basculerJaime(titre) } label: {
                Image(systemName: historique.aime(titre) ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 20))
                    .foregroundStyle(historique.aime(titre) ? Palette.citron : Palette.texte)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("J'aime")
            Button { fermer() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 36, height: 40)
            }
            .accessibilityLabel("Fermer")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 4)
    }

    private func gros(_ nom: String, _ icone: String, action: @escaping () -> Void) -> some View {
        Button { action(); fermer() } label: { grosContenu(nom, icone) }.buttonStyle(.plain)
    }

    private func grosContenu(_ nom: String, _ icone: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icone).font(.system(size: 20))
            Text(nom).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func ligne(_ nom: String, _ icone: String, danger: Bool = false, fermerApres: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            action()
            if fermerApres { fermer() }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: icone).font(.system(size: 18)).frame(width: 24)
                Text(nom).font(.system(size: 16))
                Spacer()
            }
            .foregroundStyle(danger ? Palette.danger : Palette.texte)
            .padding(.horizontal, 20).frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Menu d'appui long (version courte, menu système).
struct ActionsTitre: View {
    let titre: Titre
    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @Environment(Historique.self) private var historique
    @Environment(Navigateur.self) private var navigateur

    var body: some View {
        Button { lecteur.ajouterEnSuivant(titre) } label: { Label("Lire ensuite", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { navigateur.aEnregistrer = [titre] } label: { Label("Enregistrer dans une playlist", systemImage: "text.badge.plus") }
        Button { lecteur.lancerRadio(titre) } label: { Label("Démarrer le mix", systemImage: "dot.radiowaves.left.and.right") }
        Button { lecteur.ajouterALaFile(titre) } label: { Label("Ajouter à la file d'attente", systemImage: "text.append") }
        Button { historique.basculerJaime(titre) } label: {
            historique.aime(titre) ? Label("Retirer des titres J'aime", systemImage: "hand.thumbsup.fill") : Label("J'aime", systemImage: "hand.thumbsup")
        }
        if !telechargements.aUnTelechargement(titre.idVideo) {
            Button { telechargements.telecharger(titre, type: .audio) } label: { Label("Télécharger", systemImage: "arrow.down.to.line") }
        }
    }
}

/// « Enregistrer dans une playlist » : vos playlists, ou une nouvelle.
struct FeuilleEnregistrer: View {
    let titres: [Titre]
    @Environment(Historique.self) private var historique
    @Environment(\.dismiss) private var fermer
    @State private var nouvelle = false
    @State private var nom = ""

    var body: some View {
        NavigationStack {
            List {
                Button { nouvelle = true } label: {
                    Label("Nouvelle playlist", systemImage: "plus").font(.system(size: 16, weight: .semibold))
                }
                .ligneSombre()
                Button {
                    for t in titres where !historique.aime(t) { historique.basculerJaime(t) }
                    fermer()
                } label: {
                    LignePlaylist(nom: "Musique « J'aime »", sous: "Playlist automatique", mosaique: historique.jaime.map(\.miniature), jaime: true)
                }
                .ligneSombre()
                ForEach(historique.playlists) { p in
                    Button {
                        historique.ajouter(titres, a: p.id)
                        fermer()
                    } label: {
                        LignePlaylist(nom: p.nom, sous: "\(p.titres.count) titres", mosaique: p.titres.map(\.miniature))
                    }
                    .ligneSombre()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Enregistrer dans…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { fermer() } } }
            .alert("Nouvelle playlist", isPresented: $nouvelle) {
                TextField("Nom", text: $nom)
                Button("Créer") {
                    historique.creerPlaylist(nom, titres: titres)
                    fermer()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.texte)
    }
}

/// Ligne de playlist avec mosaïque de 4 pochettes.
struct LignePlaylist: View {
    let nom: String
    let sous: String
    var mosaique: [URL?] = []
    var jaime = false

    var body: some View {
        HStack(spacing: 12) {
            Mosaique(images: mosaique, jaime: jaime).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(nom).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(sous).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Pochette de playlist : 4 pochettes en carré, ou la tuile « J'aime » (dégradé et pouce).
struct Mosaique: View {
    let images: [URL?]
    var jaime = false
    var body: some View {
        GeometryReader { geo in
            let c = geo.size.width / 2
            ZStack {
                if jaime {
                    LinearGradient(colors: [Color(hex: 0xA855F7), Color(hex: 0xF472B6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "hand.thumbsup.fill").font(.system(size: geo.size.width * 0.42)).foregroundStyle(.white)
                } else if images.count >= 4 {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { ImageDistante(url: images[0], rayon: 0).frame(width: c, height: c); ImageDistante(url: images[1], rayon: 0).frame(width: c, height: c) }
                        HStack(spacing: 0) { ImageDistante(url: images[2], rayon: 0).frame(width: c, height: c); ImageDistante(url: images[3], rayon: 0).frame(width: c, height: c) }
                    }
                } else if let premiere = images.first {
                    ImageDistante(url: premiere, rayon: 0)
                } else {
                    Palette.surface3
                    Image(systemName: "music.note.list").font(.system(size: geo.size.width * 0.35)).foregroundStyle(Palette.texte2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

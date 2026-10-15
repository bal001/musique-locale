import SwiftUI

// Onglet Bibliothèque comme YouTube Music : puces (Téléchargés, Playlists, Titres, Albums, Artistes),
// tri « Activité récente », grille ou liste, tuile « Musique J'aime », vos playlists, « + Nouveau ».
struct BibliothequeVue: View {
    private enum Filtre: String, CaseIterable, Identifiable {
        case telecharges = "Téléchargés", playlists = "Playlists", titres = "Titres", albums = "Albums", artistes = "Artistes"
        var id: Self { self }
    }
    private enum Tri: String, CaseIterable, Identifiable {
        case activite = "Activité récente", ajouts = "Ajouts récents", az = "A à Z"
        var id: Self { self }
    }
    /// Tout ce que la bibliothèque peut afficher, dans un même ordre.
    private enum Objet: Identifiable {
        case jaime, playlist(PlaylistPerso), carte(Carte)
        var id: String {
            switch self {
            case .jaime: "jaime"
            case .playlist(let p): p.id.uuidString
            case .carte(let c): c.id
            }
        }
    }

    @Environment(Historique.self) private var historique
    @Environment(Telechargements.self) private var telechargements
    @Environment(Lecteur.self) private var lecteur
    @Environment(Navigateur.self) private var navigateur
    @State private var filtre: Filtre?
    @AppStorage("triBibliotheque") private var tri: Tri = .activite
    @AppStorage("grilleBibliotheque") private var grille = true
    @State private var nouvelle = false
    @State private var nom = ""

    private var objets: [Objet] {
        var liste: [Objet] = []
        if filtre == nil || filtre == .playlists { liste.append(.jaime) }
        var autres: [(date: Date, nom: String, objet: Objet)] = []
        if filtre == nil || filtre == .playlists {
            autres += historique.playlists.map { ($0.modifieLe, $0.nom, .playlist($0)) }
        }
        let cartes = historique.enregistres.filter {
            switch filtre {
            case nil: true
            case .playlists?: $0.type == .playlist
            case .albums?: $0.type == .album
            case .artistes?: $0.type == .artiste
            default: false
            }
        }
        autres += cartes.enumerated().map { (Date.now.addingTimeInterval(-Double($0.offset)), $0.element.nom, .carte($0.element)) }
        switch tri {
        case .az: autres.sort { $0.nom.localizedCaseInsensitiveCompare($1.nom) == .orderedAscending }
        case .activite, .ajouts: autres.sort { $0.date > $1.date }
        }
        return liste + autres.map(\.objet)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    puces
                    switch filtre {
                    case .telecharges?: TelechargementsContenu()
                    case .titres?: titres
                    default:
                        barreTri
                        if grille { grilleObjets } else { listeObjets }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 80)
            }
            Button { nom = ""; nouvelle = true } label: {
                Label("Nouveau", systemImage: "plus").font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .foregroundStyle(Palette.fond)
                    .background(Capsule().fill(Color.white))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .background(Palette.fond)
        .navigationTitle("Bibliothèque")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.historique) { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Historique")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.parametres) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Paramètres")
            }
        }
        .alert("Nouvelle playlist", isPresented: $nouvelle) {
            TextField("Nom", text: $nom)
            Button("Créer") {
                let p = historique.creerPlaylist(nom)
                navigateur.ouvrir(.playlistPerso(p.id))
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var puces: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filtre.allCases) { f in
                    Button { filtre = filtre == f ? nil : f } label: {
                        Text(f.rawValue).font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(filtre == f ? Palette.surCitron : Palette.texte)
                            .background(Capsule().fill(filtre == f ? Palette.citron : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var barreTri: some View {
        HStack {
            Menu {
                Picker("Trier", selection: $tri) { ForEach(Tri.allCases) { Text($0.rawValue).tag($0) } }
            } label: {
                HStack(spacing: 4) {
                    Text(tri.rawValue).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Palette.texte)
            }
            Spacer()
            Button { grille.toggle() } label: {
                Image(systemName: grille ? "list.bullet" : "square.grid.2x2").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(grille ? "Afficher en liste" : "Afficher en grille")
        }
        .padding(.horizontal, 16)
    }

    private var grilleObjets: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 20) {
            ForEach(objets) { o in
                Button { ouvrir(o) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        visuel(o).aspectRatio(1, contentMode: .fit)
                        Text(nom(o)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            if case .jaime = o { Image(systemName: "pin.fill").font(.system(size: 10)) }
                            Text(sous(o)).lineLimit(1)
                        }
                        .font(.system(size: 12)).foregroundStyle(Palette.texte2)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { menu(o) }
            }
        }
        .padding(.horizontal, 16)
    }

    private var listeObjets: some View {
        LazyVStack(spacing: 4) {
            ForEach(objets) { o in
                Button { ouvrir(o) } label: {
                    HStack(spacing: 12) {
                        visuel(o).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nom(o)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text(sous(o)).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { menu(o) }
            }
        }
    }

    private var titres: some View {
        let tous = historique.jaime + telechargements.elements.map(\.titre).filter { !historique.aime($0) }
        return LazyVStack(spacing: 0) {
            if tous.isEmpty {
                Text("Vos titres J'aime et vos téléchargements apparaîtront ici.").font(.system(size: 14)).foregroundStyle(Palette.texte2).padding(16)
            }
            ForEach(Array(tous.enumerated()), id: \.element.id) { i, t in
                LigneTitre(titre: t) { lecteur.jouer(tous, depuis: i, source: "Titres") }.padding(.leading, 16)
            }
        }
    }

    @ViewBuilder private func visuel(_ o: Objet) -> some View {
        switch o {
        case .jaime: Mosaique(images: [], jaime: true)
        case .playlist(let p): Mosaique(images: p.titres.map(\.miniature))
        case .carte(let c): ImageDistante(url: c.image, ronde: c.ronde)
        }
    }

    private func nom(_ o: Objet) -> String {
        switch o {
        case .jaime: "Musique « J'aime »"
        case .playlist(let p): p.nom
        case .carte(let c): c.nom
        }
    }

    private func sous(_ o: Objet) -> String {
        switch o {
        case .jaime: "Playlist automatique · \(historique.jaime.count) titres"
        case .playlist(let p): "Playlist · \(p.titres.count) titres"
        case .carte(let c):
            switch c.type {
            case .artiste: "Artiste"
            case .album: c.sousTitre.isEmpty ? "Album" : c.sousTitre
            default: c.sousTitre.isEmpty ? "Playlist" : c.sousTitre
            }
        }
    }

    private func ouvrir(_ o: Objet) {
        switch o {
        case .jaime: navigateur.ouvrir(.titresJaime)
        case .playlist(let p): navigateur.ouvrir(.playlistPerso(p.id))
        case .carte(let c): navigateur.ouvrir(Route.pour(c))
        }
    }

    @ViewBuilder private func menu(_ o: Objet) -> some View {
        switch o {
        case .jaime: EmptyView()
        case .playlist(let p):
            Button(role: .destructive) { historique.supprimerPlaylist(p.id) } label: { Label("Supprimer la playlist", systemImage: "trash") }
        case .carte(let c):
            Button(role: .destructive) { historique.basculerEnregistrement(c) } label: { Label("Retirer de la bibliothèque", systemImage: "minus.circle") }
        }
    }
}

/// Téléchargements dans la bibliothèque (puce « Téléchargés »).
struct TelechargementsContenu: View {
    @Environment(Telechargements.self) private var telechargements
    @Environment(Lecteur.self) private var lecteur
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(telechargements.enCours) { suivi in
                HStack(spacing: 12) {
                    Pochette(titre: suivi.titre, taille: 48, rayon: 4)
                    Text(suivi.titre.nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    AnneauProgression(fraction: suivi.fraction)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            if telechargements.elements.isEmpty && telechargements.enCours.isEmpty {
                Text("Touchez « Télécharger » dans le menu ⋮ d'un titre pour l'écouter sans connexion.")
                    .font(.system(size: 14)).foregroundStyle(Palette.texte2).padding(16)
            } else if !telechargements.elements.isEmpty {
                Button { lecteur.jouer(telechargements.elements.map(\.titre).shuffled(), source: "Téléchargés") } label: {
                    Label("Lecture aléatoire", systemImage: "shuffle").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .foregroundStyle(Palette.fond).background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 8)
            }
            let titres = telechargements.elements.map(\.titre)
            ForEach(Array(telechargements.elements.enumerated()), id: \.element.id) { i, e in
                LigneTitre(titre: e.titre, badge: e.type == .clip ? "CLIP" : nil) { lecteur.jouer(titres, depuis: i, source: "Téléchargés") }
                    .padding(.leading, 16)
            }
        }
    }
}

/// Liste simple de titres avec lecture et lecture aléatoire (Titres J'aime…).
struct TitresVue: View {
    let nom: String
    let titres: [Titre]
    @Environment(Lecteur.self) private var lecteur

    var body: some View {
        List {
            if titres.isEmpty {
                ContentUnavailableView("Aucun titre", systemImage: "hand.thumbsup",
                                       description: Text("Touchez 👍 dans le lecteur pour ajouter un titre ici."))
                    .ligneSombre()
            }
            ForEach(Array(titres.enumerated()), id: \.element.id) { i, t in
                LigneTitre(titre: t) { lecteur.jouer(titres, depuis: i) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.fond)
        .navigationTitle(nom)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    BoutonToutTelecharger(titres: titres)
                    Button { lecteur.jouer(titres.shuffled()) } label: { Label("Aléatoire", systemImage: "shuffle") }
                        .disabled(titres.isEmpty)
                }
            }
        }
    }
}

/// Historique d'écoute, effaçable (titre par titre ou en entier).
struct HistoriqueVue: View {
    @Environment(Historique.self) private var historique
    @Environment(Lecteur.self) private var lecteur
    @State private var confirmer = false

    var body: some View {
        List {
            if historique.ecoutes.isEmpty {
                ContentUnavailableView("Aucun historique", systemImage: "clock")
                    .ligneSombre()
            }
            ForEach(Array(historique.ecoutes.enumerated()), id: \.element.id) { i, t in
                LigneTitre(titre: t) { lecteur.jouer(historique.ecoutes, depuis: i) }
                    .swipeActions {
                        Button("Retirer", role: .destructive) { historique.retirerEcoute(t) }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.fond)
        .navigationTitle("Historique")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    BoutonToutTelecharger(titres: historique.ecoutes)
                    Button("Effacer") { confirmer = true }.disabled(historique.ecoutes.isEmpty)
                }
            }
        }
        .confirmationDialog("Effacer tout l'historique d'écoute ?", isPresented: $confirmer, titleVisibility: .visible) {
            Button("Effacer l'historique", role: .destructive) { historique.effacerEcoutes() }
        }
    }
}

/// Musique « J'aime » (playlist automatique).
struct TitresJaimeVue: View {
    @Environment(Historique.self) private var historique
    var body: some View { TitresVue(nom: "Musique « J'aime »", titres: historique.jaime) }
}

/// Playlist créée sur le téléphone : lire, mélanger, renommer, réordonner, retirer, supprimer.
struct PlaylistPersoVue: View {
    let id: UUID
    @Environment(Historique.self) private var historique
    @Environment(Lecteur.self) private var lecteur
    @Environment(\.dismiss) private var fermer
    @State private var renommer = false
    @State private var nom = ""
    @State private var supprimer = false

    var body: some View {
        if let p = historique.playlists.first(where: { $0.id == id }) {
            List {
                VStack(spacing: 10) {
                    Mosaique(images: p.titres.map(\.miniature)).frame(width: 220, height: 220)
                    Text(p.nom).font(.system(size: 24, weight: .bold))
                    Text("Playlist • \(p.titres.count) titres").font(.system(size: 14)).foregroundStyle(Palette.texte2)
                    HStack(spacing: 12) {
                        Button { lecteur.jouer(p.titres.shuffled(), source: p.nom) } label: {
                            Label("Aléatoire", systemImage: "shuffle").font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .foregroundStyle(Palette.fond).background(Capsule().fill(Color.white))
                        }
                        Button { lecteur.jouer(p.titres, source: p.nom) } label: {
                            Label("Lecture", systemImage: "play.fill").font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
                        }
                        BoutonToutTelecharger(titres: p.titres)
                    }
                    .buttonStyle(.plain)
                    .disabled(p.titres.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .ligneSombre()
                if p.titres.isEmpty {
                    Text("Ajoutez des titres avec « Enregistrer dans une playlist » (menu ⋮ d'un titre).")
                        .font(.system(size: 14)).foregroundStyle(Palette.texte2).ligneSombre()
                }
                ForEach(Array(p.titres.enumerated()), id: \.element.id) { i, t in
                    LigneTitre(titre: t) { lecteur.jouer(p.titres, depuis: i, source: p.nom) }
                }
                .onDelete { positions in historique.modifierPlaylist(id) { $0.titres.remove(atOffsets: positions) } }
                .onMove { depart, arrivee in historique.modifierPlaylist(id) { $0.titres.move(fromOffsets: depart, toOffset: arrivee) } }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.fond)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { nom = p.nom; renommer = true } label: { Label("Renommer", systemImage: "pencil") }
                        EditButton()
                        Button(role: .destructive) { supprimer = true } label: { Label("Supprimer la playlist", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .alert("Renommer", isPresented: $renommer) {
                TextField("Nom", text: $nom)
                Button("OK") { historique.modifierPlaylist(id) { $0.nom = nom } }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog("Supprimer « \(p.nom) » ?", isPresented: $supprimer, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { historique.supprimerPlaylist(id); fermer() }
            }
        } else {
            ContentUnavailableView("Playlist supprimée", systemImage: "music.note.list")
        }
    }
}

/// « Tout télécharger » : tous les titres d'une liste pour l'écoute hors ligne (cercle plein quand tout y est).
struct BoutonToutTelecharger: View {
    let titres: [Titre]
    @Environment(Telechargements.self) private var telechargements

    private var restants: [Titre] { titres.filter { !telechargements.aUnTelechargement($0.idVideo) } }
    private var enCours: Int { titres.filter { telechargements.progression($0.idVideo) != nil }.count }

    var body: some View {
        Button {
            for t in restants where telechargements.progression(t.idVideo) == nil { telechargements.telecharger(t, type: .audio) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: restants.isEmpty ? "arrow.down.circle.fill" : "arrow.down.circle").font(.system(size: 22))
                if enCours > 0 { Text("\(titres.count - restants.count)/\(titres.count)").font(.system(size: 13, weight: .semibold).monospacedDigit()) }
            }
            .foregroundStyle(restants.isEmpty ? Palette.citron : Palette.texte)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(titres.isEmpty || restants.isEmpty)
        .accessibilityLabel(restants.isEmpty ? "Tout est téléchargé" : "Tout télécharger (\(restants.count) titres)")
    }
}

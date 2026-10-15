import SwiftUI

enum Onglet: Hashable {
    case accueil, samples, recherche, bibliotheque
}

// Comme YouTube Music : onglets Accueil / Samples / Rechercher / Bibliothèque, mini-lecteur au-dessus des onglets,
// lecteur plein écran en feuille. Chaque onglet garde sa propre pile de pages.
struct RacineVue: View {
    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @Environment(Navigateur.self) private var navigateur
    @State private var onglet: Onglet = .accueil
    @State private var chemins: [Onglet: NavigationPath] = [:]

    var body: some View {
        @Bindable var lecteur = lecteur
        TabView(selection: Binding(get: { onglet }, set: { nouveau in
            // Toucher l'onglet déjà affiché revient à sa première page, comme dans YouTube Music.
            if nouveau == onglet { chemins[nouveau] = NavigationPath() }
            onglet = nouveau
        })) {
            pile(.accueil) { AccueilVue() }
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(Onglet.accueil)
            SamplesVue(actif: onglet == .samples)
                .tabItem { Label("Samples", systemImage: "play.square.stack.fill") }
                .tag(Onglet.samples)
            pile(.recherche) { RechercheVue(racine: true) }
                .tabItem { Label("Rechercher", systemImage: "magnifyingglass") }
                .tag(Onglet.recherche)
            pile(.bibliotheque) { BibliothequeVue() }
                .tabItem { Label("Bibliothèque", systemImage: "bookmark.fill") }
                .tag(Onglet.bibliotheque)
        }
        .sheet(isPresented: $lecteur.pleinEcran) {
            LecteurPlein()
                .presentationBackground(Palette.fond)
        }
        .sheet(item: Binding(get: { navigateur.menu }, set: { navigateur.menu = $0 })) { titre in
            FeuilleTitre(titre: titre)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.surface1)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(get: { navigateur.aEnregistrer != nil }, set: { if !$0 { navigateur.aEnregistrer = nil } })) {
            FeuilleEnregistrer(titres: navigateur.aEnregistrer ?? [])
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.surface1)
        }
        .onChange(of: navigateur.demande) { _, route in
            guard let route else { return }
            lecteur.pleinEcran = false
            navigateur.menu = nil
            // Une page demandée depuis Samples s'ouvre dans l'onglet Accueil.
            if onglet == .samples { onglet = .accueil }
            chemins[onglet, default: NavigationPath()].append(route)
            navigateur.demande = nil
        }
        .alert("Téléchargement", isPresented: Binding(
            get: { telechargements.erreur != nil },
            set: { if !$0 { telechargements.erreur = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(telechargements.erreur ?? "")
        }
    }

    private func pile<Contenu: View>(_ o: Onglet, @ViewBuilder _ racine: () -> Contenu) -> some View {
        NavigationStack(path: Binding(get: { chemins[o] ?? NavigationPath() }, set: { chemins[o] = $0 })) {
            racine().destinationsYTM()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MiniLecteur() }
    }
}

extension View {
    /// Ligne de liste sans fond ni séparateur, sur fond noir.
    func ligneSombre() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8))
    }

    /// Titre de section façon YouTube Music.
    func enteteSection() -> some View {
        font(.system(size: 20, weight: .bold))
            .foregroundStyle(Palette.texte)
            .textCase(nil)
    }
}

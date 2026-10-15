import AVKit
import SwiftUI

// Lecteur plein écran comme YouTube Music (version 🎧 seulement, sans vidéo) : AirPlay, menu ⋮,
// pochette, titre « › » (ouvre l'artiste), bulles d'actions (👍|👎, Enregistrer, Télécharger, Partager),
// progression, commandes, puis À SUIVRE · PAROLES · SIMILAIRES.
struct LecteurPlein: View {
    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @Environment(Historique.self) private var historique
    @Environment(Navigateur.self) private var navigateur
    @Environment(\.dismiss) private var dismiss
    @State private var glissement: Double?
    @State private var ongletBas: OngletBas?

    var body: some View {
        if let titre = lecteur.enCours {
            VStack(spacing: 16) {
                entete(titre)
                contenu(titre)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                infos(titre)
                bulles(titre)
                progression
                commandes
                barreOnglets
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .foregroundStyle(Palette.texte)
            .background { fond(titre) }
            .sheet(item: $ongletBas) { o in
                PanneauBas(selection: o)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Palette.surface1)
                    .presentationDragIndicator(.visible)
            }
            // Le menu ⋮ et « Enregistrer » s'ouvrent aussi par-dessus le lecteur.
            .sheet(item: Binding(get: { navigateur.menu }, set: { navigateur.menu = $0 })) { t in
                FeuilleTitre(titre: t)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Palette.surface1)
                    .presentationDragIndicator(.visible)
            }
        } else {
            Palette.fond.onAppear { dismiss() }
        }
    }

    // MARK: En-tête

    private func entete(_ titre: Titre) -> some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Réduire le lecteur")
            Spacer()
            Spacer()
            BoutonAirPlay().frame(width: 44, height: 44)
            BoutonMenu(titre: titre, taille: 18)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    /// Pochette seulement : le propriétaire ne veut pas de vidéo dans l'app (version 🎧 uniquement).
    private func contenu(_ titre: Titre) -> some View {
        Pochette(titre: titre, rayon: 10)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.horizontal, 24)
    }

    // MARK: Titre et actions

    private func infos(_ titre: Titre) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if let id = titre.idArtiste { navigateur.ouvrir(.page(Carte(idPage: id, type: .artiste, nom: titre.artiste))) }
            } label: {
                HStack(spacing: 6) {
                    if titre.explicite == true { BadgeExplicite() }
                    Text(titre.nom).font(.system(size: 22, weight: .bold)).lineLimit(1)
                    if titre.idArtiste != nil { Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)) }
                }
            }
            .buttonStyle(.plain)
            Text(lecteur.erreur ?? titre.artiste)
                .font(.system(size: 15))
                .foregroundStyle(lecteur.erreur == nil ? Palette.texte2 : Palette.danger)
                .lineLimit(2)
            if let fin = lecteur.arretPrevu {
                Label("Arrêt à \(fin.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.citron)
            } else if lecteur.arretFinDuTitre {
                Label("Arrêt à la fin du titre", systemImage: "moon.zzz.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.citron)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func bulles(_ titre: Titre) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button { historique.basculerJaime(titre) } label: {
                        Image(systemName: historique.aime(titre) ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundStyle(historique.aime(titre) ? Palette.citron : Palette.texte)
                            .padding(.horizontal, 14)
                    }
                    .accessibilityLabel("J'aime")
                    Rectangle().fill(Palette.bord).frame(width: 1, height: 18)
                    Button {
                        historique.basculerJaimePas(titre)
                        if historique.aimePas(titre) { lecteur.suivant() }
                    } label: {
                        Image(systemName: historique.aimePas(titre) ? "hand.thumbsdown.fill" : "hand.thumbsdown").padding(.horizontal, 14)
                    }
                    .accessibilityLabel("Je n'aime pas")
                }
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                bulle("Enregistrer", "text.badge.plus") { navigateur.aEnregistrer = [titre] }
                if let suivi = telechargements.progression(titre.idVideo) {
                    HStack(spacing: 6) { AnneauProgression(fraction: suivi.fraction, taille: 18); Text("Téléchargement") }
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                } else if telechargements.aUnTelechargement(titre.idVideo) {
                    bulle("Téléchargé", "checkmark.circle.fill") {}
                } else {
                    bulle("Télécharger", "arrow.down.to.line") { telechargements.telecharger(titre, type: .audio) }
                }
                ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(titre.idVideo)")!) {
                    Label("Partager", systemImage: "arrowshape.turn.up.right")
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }

    private func bulle(_ nom: String, _ icone: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(nom, systemImage: icone)
                .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
    }

    // MARK: Progression et commandes

    private var progression: some View {
        let total = max(lecteur.duree, 1)
        return VStack(spacing: 2) {
            Slider(
                value: Binding(get: { glissement ?? min(lecteur.position, total) }, set: { glissement = $0 }),
                in: 0...total,
                onEditingChanged: { enCours in
                    if !enCours, let g = glissement {
                        lecteur.chercher(a: g)
                        glissement = nil
                    }
                }
            )
            .tint(.white)
            HStack {
                Text(formaterDuree(glissement ?? lecteur.position))
                Spacer()
                Text(formaterDuree(lecteur.duree))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Palette.texte2)
        }
        .padding(.horizontal, 24)
    }

    private var commandes: some View {
        HStack(spacing: 0) {
            Button { lecteur.basculerAleatoire() } label: {
                Image(systemName: "shuffle").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(lecteur.aleatoire ? Palette.citron : Palette.texte)
            }
            .accessibilityLabel("Aléatoire")
            Spacer()
            Button { lecteur.precedent() } label: { Image(systemName: "backward.end.fill").font(.system(size: 30)) }
                .accessibilityLabel("Précédent")
            Spacer()
            Button { lecteur.basculer() } label: {
                ZStack {
                    Circle().fill(Color.white)
                    if lecteur.chargement {
                        ProgressView().tint(Palette.fond)
                    } else {
                        Image(systemName: lecteur.enLecture ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold)).foregroundStyle(Palette.fond)
                    }
                }
                .frame(width: 72, height: 72)
            }
            .accessibilityLabel(lecteur.enLecture ? "Pause" : "Lecture")
            Spacer()
            Button { lecteur.suivant() } label: { Image(systemName: "forward.end.fill").font(.system(size: 30)) }
                .disabled(!lecteur.aUnSuivant)
                .opacity(lecteur.aUnSuivant ? 1 : 0.4)
                .accessibilityLabel("Suivant")
            Spacer()
            Button { lecteur.basculerRepetition() } label: {
                Image(systemName: lecteur.repetition == .un ? "repeat.1" : "repeat").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(lecteur.repetition == .aucune ? Palette.texte : Palette.citron)
            }
            .accessibilityLabel("Répéter")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
    }

    /// Poignée et « À SUIVRE · PAROLES · SIMILAIRES » ; glisser vers le haut ouvre la file d'attente.
    private var barreOnglets: some View {
        VStack(spacing: 6) {
            Capsule().fill(Palette.texte3).frame(width: 36, height: 4)
            HStack {
                ForEach(OngletBas.allCases) { o in
                    Button { ongletBas = o } label: {
                        Text(o.rawValue.uppercased()).font(.system(size: 13, weight: .bold)).tracking(0.6)
                            .foregroundStyle(Palette.texte2)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { if $0.translation.height < -20 { ongletBas = .suivre } })
        .padding(.horizontal, 16)
    }

    private func fond(_ titre: Titre) -> some View {
        ZStack {
            Palette.fond
            Pochette(titre: titre, rayon: 0)
                .scaleEffect(1.6)
                .blur(radius: 70)
                .opacity(0.45)
            LinearGradient(colors: [.clear, Palette.fond.opacity(0.9), Palette.fond],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Bouton de diffusion (AirPlay : enceinte, TV, voiture…).
struct BoutonAirPlay: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Palette.citron)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

enum OngletBas: String, CaseIterable, Identifiable {
    case suivre = "À suivre", paroles = "Paroles", similaires = "Similaires"
    var id: Self { self }
}

/// Panneau du bas du lecteur : file d'attente (avec les recommandations), paroles, titres similaires.
struct PanneauBas: View {
    @State var selection: OngletBas
    @Environment(Lecteur.self) private var lecteur

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(OngletBas.allCases) { o in
                    Button { selection = o } label: {
                        VStack(spacing: 8) {
                            Text(o.rawValue.uppercased()).font(.system(size: 13, weight: .bold)).tracking(0.6)
                                .foregroundStyle(selection == o ? Palette.texte : Palette.texte2)
                            Rectangle().fill(selection == o ? Palette.texte : .clear).frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
            Divider().overlay(Palette.bord)
            switch selection {
            case .suivre: FileAttenteVue()
            case .paroles:
                if let t = lecteur.enCours { ParolesVue(titre: t).padding(.horizontal, 20) }
            case .similaires:
                if let t = lecteur.enCours { SimilairesVue(titre: t) }
            }
        }
        .foregroundStyle(Palette.texte)
    }
}

/// « À suivre » comme YouTube Music : « Lecture à partir de … », Enregistrer, titres réordonnables,
/// séparation des recommandations, interrupteur « Lecture automatique ».
struct FileAttenteVue: View {
    @Environment(Lecteur.self) private var lecteur
    @Environment(Historique.self) private var historique

    var body: some View {
        @Bindable var lecteur = lecteur
        ScrollViewReader { defilement in
            List {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lecture à partir de").font(.system(size: 12)).foregroundStyle(Palette.texte2)
                        Text(lecteur.source ?? "Votre file d'attente").font(.system(size: 15, weight: .bold)).lineLimit(1)
                    }
                    Spacer()
                    Button { historique.creerPlaylist(lecteur.source ?? "Ma file d'attente", titres: lecteur.file) } label: {
                        Label("Enregistrer", systemImage: "text.badge.plus").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Capsule().stroke(Palette.bord, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .ligneSombre()
                let debutAuto = lecteur.file.count - lecteur.ajoutsAuto
                ForEach(Array(lecteur.file.enumerated()), id: \.offset) { i, t in
                    if i == debutAuto, lecteur.ajoutsAuto > 0 {
                        Text("Recommandations · même style").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.texte2).ligneSombre()
                    }
                    HStack(spacing: 12) {
                        Pochette(titre: t, taille: 48, rayon: 4)
                            .overlay {
                                if i == lecteur.index {
                                    Image(systemName: lecteur.enLecture ? "waveform" : "pause.fill")
                                        .symbolEffect(.variableColor.iterative, isActive: lecteur.enLecture)
                                        .foregroundStyle(Palette.citron)
                                        .frame(width: 48, height: 48).background(.black.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(i == lecteur.index ? Palette.citron : Palette.texte)
                            Text(t.sousTitre).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "line.3.horizontal").foregroundStyle(Palette.texte3)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { lecteur.allerA(i) }
                    .swipeActions {
                        if i != lecteur.index {
                            Button("Retirer", role: .destructive) { lecteur.retirer(i) }
                        }
                    }
                    .id(i)
                    .ligneSombre()
                }
                .onMove { lecteur.deplacer(depuis: $0, vers: $1) }
                Toggle(isOn: $lecteur.lectureAuto) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lecture automatique").font(.system(size: 15, weight: .semibold))
                        Text("Ajoute des titres similaires pour une écoute en continu").font(.system(size: 12)).foregroundStyle(Palette.texte2)
                    }
                }
                .tint(Palette.citron)
                .ligneSombre()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .onAppear { defilement.scrollTo(lecteur.index, anchor: .top) }
        }
    }
}

/// « Similaires » : titres, artistes et playlists proches du titre en cours.
struct SimilairesVue: View {
    let titre: Titre
    @State private var rangees: [Rangee]?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let rangees {
                    if rangees.isEmpty {
                        ContentUnavailableView("Rien de similaire", systemImage: "music.note.list").padding(.top, 40)
                    }
                    ForEach(rangees) { RangeeVue(rangee: $0, radio: true) }
                } else {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.vertical, 16)
        }
        .task(id: titre.idVideo) {
            rangees = nil
            rangees = await avecEssais(vide: { $0.isEmpty }) { try await InnerTube.partage.similaires(titre.idVideo) } ?? []
        }
    }
}

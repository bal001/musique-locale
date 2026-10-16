import SwiftUI

// Recherche comme YouTube Music : historique (supprimable), suggestions pendant la frappe,
// puis résultats avec puces (Titres, Vidéos, Albums, Artistes, Playlists…) et meilleur résultat.
struct RechercheVue: View {
    var racine = false   // onglet « Rechercher » (pas de bouton retour)
    @Environment(Historique.self) private var historique
    @Environment(Lecteur.self) private var lecteur
    @Environment(Navigateur.self) private var navigateur
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var suggestions: [String] = []
    @State private var lancee: String?
    @State private var resultats: PageYTM?
    @State private var puces: [Puce] = []
    @State private var puce: Puce?
    @State private var chargement = false
    @State private var erreur: String?
    @FocusState private var focus: Bool

    var body: some View {
        VStack(spacing: 0) {
            champ
            if lancee == nil || focus {
                propositions
            } else {
                resultatsVue
            }
        }
        .background(Palette.fond)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if lancee == nil, !racine { focus = true } }
        .task(id: texte) { await suggerer() }
    }

    // MARK: Champ

    private var champ: some View {
        HStack(spacing: 8) {
            if !racine || lancee != nil || focus {
                Button {
                    if lancee != nil || focus { lancee = nil; resultats = nil; texte = ""; focus = false } else { fermer() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 44)
                }
                .accessibilityLabel("Retour")
            }
            HStack(spacing: 8) {
                if racine && lancee == nil && !focus {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.texte2)
                }
                TextField("Saisir une recherche", text: $texte)
                    .focused($focus)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { lancer(texte) }
                if !texte.isEmpty {
                    Button { texte = ""; focus = true } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.texte2)
                    }
                    .accessibilityLabel("Effacer")
                }
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .foregroundStyle(Palette.texte)
    }

    // MARK: Historique et suggestions

    private var propositions: some View {
        List {
            if texte.trimmingCharacters(in: .whitespaces).isEmpty {
                if !historique.consultes.isEmpty || !historique.recherches.isEmpty {
                    Text("Recherches récentes").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.texte2).ligneSombre()
                }
                if !historique.consultes.isEmpty {
                    // Derniers résultats ouverts, en images, comme YouTube Music.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(historique.consultes) { e in
                                ToucheElement(element: e) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        switch e {
                                        case .titre(let t): ImageDistante(url: t.miniature, rayon: 4).frame(width: 104, height: 104)
                                        case .carte(let c): ImageDistante(url: c.image, ronde: c.ronde, rayon: 4).frame(width: 104, height: 104)
                                        }
                                        Text(nomElement(e)).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(width: 104, alignment: .leading)
                                    }
                                }
                                .contextMenu { Button("Retirer", role: .destructive) { historique.retirerConsulte(e) } }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if !historique.recherches.isEmpty {
                    ForEach(historique.recherches, id: \.self) { q in
                        ligneProposition(q, icone: "clock.arrow.circlepath")
                            .swipeActions { Button("Supprimer", role: .destructive) { historique.supprimerRecherche(q) } }
                    }
                    Button("Tout effacer", role: .destructive) { historique.toutEffacer() }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .ligneSombre()
                }
                tuiles.ligneSombre()
            } else {
                ForEach(suggestions, id: \.self) { ligneProposition($0, icone: "magnifyingglass") }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// Nouveautés · Charts · Humeurs et genres (accès à l'exploration, comme dans YouTube Music).
    private var tuiles: some View {
        HStack(spacing: 10) {
            tuile("Nouveautés", "sparkles", .nouveautes)
            tuile("Charts", "chart.line.uptrend.xyaxis", .classements)
            tuile("Humeurs et genres", "face.smiling", .page(Carte(idPage: "FEmusic_moods_and_genres", type: .page, nom: "Humeurs et genres")))
        }
        .padding(.top, 8)
    }

    private func nomElement(_ e: Element) -> String {
        switch e {
        case .titre(let t): t.nom
        case .carte(let c): c.nom
        }
    }

    private func tuile(_ nom: String, _ icone: String, _ route: Route) -> some View {
        Button { navigateur.ouvrir(route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icone).font(.system(size: 16))
                Spacer(minLength: 0)
                Text(nom).font(.system(size: 14, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface2))
        }
        .buttonStyle(.plain)
    }

    private func ligneProposition(_ q: String, icone: String) -> some View {
        HStack(spacing: 14) {
            Button { lancer(q) } label: {
                HStack(spacing: 14) {
                    Image(systemName: icone).foregroundStyle(Palette.texte2).frame(width: 22)
                    Text(q).font(.system(size: 16)).foregroundStyle(Palette.texte).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if icone == "clock.arrow.circlepath" {
                Button { historique.supprimerRecherche(q) } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Palette.texte2).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Supprimer de l'historique")
            } else {
                Button { texte = q + " " } label: {
                    Image(systemName: "arrow.up.left").font(.system(size: 14)).foregroundStyle(Palette.texte2).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compléter")
            }
        }
        .ligneSombre()
    }

    // MARK: Résultats

    private var resultatsVue: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(puces) { p in
                            Button {
                                puce = puce == p ? nil : p
                                Task { await chercher() }
                            } label: {
                                Text(p.nom).font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(puce == p ? Palette.surCitron : Palette.texte)
                                    .background(Capsule().fill(puce == p ? Palette.citron : Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if chargement {
                    ProgressView().tint(Palette.citron).frame(maxWidth: .infinity).padding(.top, 60)
                } else if let erreur {
                    ContentUnavailableView("Recherche impossible", systemImage: "wifi.slash", description: Text(erreur))
                } else if let resultats, resultats.sections.isEmpty {
                    ContentUnavailableView.search(text: lancee ?? "")
                } else if let resultats {
                    ForEach(resultats.sections) { RangeeVue(rangee: $0, radio: true) }
                        .environment(\.noterConsultation, { historique.noterConsulte($0) })
                }
            }
            .padding(.vertical, 6)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Actions

    private func lancer(_ q: String) {
        let requete = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requete.isEmpty else { return }
        texte = requete
        lancee = requete
        puce = nil
        focus = false
        historique.ajouterRecherche(requete)
        Task { await chercher() }
    }

    private func chercher() async {
        guard let q = lancee else { return }
        chargement = true
        erreur = nil
        defer { chargement = false }
        do {
            let page = try await InnerTube.partage.recherchePage(q, params: puce?.params)
            if puce == nil, !page.puces.isEmpty { puces = page.puces }
            resultats = page
            PrechargeurFlux.partage.precharger(Array(page.sections.flatMap(\.titres).prefix(1)))
        } catch {
            erreur = "Vérifie ta connexion."
        }
    }

    private func suggerer() async {
        let q = texte.trimmingCharacters(in: .whitespaces)
        guard q.count >= 1, focus else { suggestions = []; return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        suggestions = (try? await InnerTube.partage.suggestions(q)) ?? []
    }
}

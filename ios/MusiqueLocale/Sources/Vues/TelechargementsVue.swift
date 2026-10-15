import SwiftUI

// Bibliothèque des titres enregistrés sur le téléphone (lisibles en mode avion).
struct TelechargementsVue: View {
    private enum Filtre: String, CaseIterable, Identifiable {
        case tous = "Tous", audio = "Audio", clips = "Clips"
        var id: Self { self }
    }

    @Environment(Lecteur.self) private var lecteur
    @Environment(Telechargements.self) private var telechargements
    @State private var filtre: Filtre = .tous

    private var visibles: [Telechargement] {
        switch filtre {
        case .tous: telechargements.elements
        case .audio: telechargements.elements.filter { $0.type == .audio }
        case .clips: telechargements.elements.filter { $0.type == .clip }
        }
    }

    var body: some View {
        List {
                if !telechargements.enCours.isEmpty {
                    Section {
                        ForEach(telechargements.enCours) { suivi in
                            HStack(spacing: 12) {
                                Pochette(titre: suivi.titre, taille: 44, rayon: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suivi.titre.nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    Text(suivi.type == .clip ? "Clip" : "Audio")
                                        .font(.system(size: 12)).foregroundStyle(Palette.texte2)
                                }
                                Spacer()
                                AnneauProgression(fraction: suivi.fraction)
                            }
                            .ligneSombre()
                        }
                    } header: {
                        Text("En cours").enteteSection()
                    }
                }

                if telechargements.elements.isEmpty {
                    ContentUnavailableView("Aucun téléchargement", systemImage: "arrow.down.circle",
                                           description: Text("Touchez « Télécharger » sur un titre pour l'écouter hors ligne."))
                        .ligneSombre()
                } else {
                    Section {
                        ForEach(visibles) { e in
                            LigneTitre(titre: e.titre, badge: e.type == .clip ? "CLIP" : nil) {
                                lecteur.jouer(visibles.map(\.titre), depuis: visibles.firstIndex(of: e) ?? 0)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    telechargements.supprimer(e.titre.idVideo, e.type)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Picker("Filtre", selection: $filtre) {
                            ForEach(Filtre.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .textCase(nil)
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.fond)
            .navigationTitle("Téléchargements")
            .toolbar {
                if !visibles.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            lecteur.jouer(visibles.map(\.titre).shuffled())
                        } label: {
                            Label("Lecture aléatoire", systemImage: "shuffle")
                        }
                    }
                }
            }
    }
}

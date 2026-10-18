import SwiftUI

// Paramètres : égaliseur (basses…), lecture, nouveautés, stockage, historique, à propos.
struct ParametresVue: View {
    @Environment(Lecteur.self) private var lecteur
    @Environment(Historique.self) private var historique
    @State private var egaliseur = Egaliseur.partage
    @AppStorage("pays") private var pays: Pays = .france
    @State private var tailleCache: Int64 = 0
    @State private var tailleTelechargements: Int64 = 0
    @State private var confirmer = false

    var body: some View {
        @Bindable var lecteur = lecteur
        @Bindable var egaliseur = egaliseur
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Égaliseur
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Égaliseur").font(.system(size: 22, weight: .bold))
                        Spacer()
                        Toggle("", isOn: $egaliseur.actif).labelsHidden().tint(Palette.citron)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Egaliseur.presets) { p in
                                let choisi = egaliseur.actif && egaliseur.presetCourant == p
                                Button { egaliseur.choisir(p) } label: {
                                    Text(p.nom).font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .foregroundStyle(choisi ? Palette.surCitron : Palette.texte)
                                        .background(Capsule().fill(choisi ? Palette.citron : Color.white.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            VStack(spacing: 8) {
                                Text(String(format: "%+.0f", egaliseur.gains[i])).font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Palette.texte2)
                                CurseurVertical(valeur: Binding(get: { egaliseur.gains[i] }, set: { v in
                                    egaliseur.gains[i] = v
                                    if !egaliseur.actif { egaliseur.actif = true }
                                }))
                                .frame(height: 170)
                                Text(Egaliseur.libelles[i]).font(.system(size: 11)).foregroundStyle(Palette.texte2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .opacity(egaliseur.actif ? 1 : 0.4)
                    Text("Basses à gauche, aigus à droite. Le volume est un peu réduit quand tu pousses fort, pour éviter que ça sature.")
                        .font(.system(size: 12)).foregroundStyle(Palette.texte3)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface2))

                section("Lecture") {
                    Toggle(isOn: $lecteur.lectureAuto) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lecture automatique").font(.system(size: 16, weight: .semibold))
                            Text("Ajoute des titres du même style à la fin de la file").font(.system(size: 13)).foregroundStyle(Palette.texte2)
                        }
                    }
                    .tint(Palette.citron)
                }

                section("Nouveautés et classements") {
                    Text("Pays").font(.system(size: 13)).foregroundStyle(Palette.texte2)
                    PucesPays(pays: $pays).padding(.horizontal, -16)
                }

                section("Stockage") {
                    ligneInfo("Téléchargements", ByteCountFormatter.string(fromByteCount: tailleTelechargements, countStyle: .file))
                    HStack {
                        ligneInfo("Titres gardés pour une écoute rapide", ByteCountFormatter.string(fromByteCount: tailleCache, countStyle: .file))
                        Button("Vider") { viderCache() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.citron)
                    }
                }

                section("Historique") {
                    Button("Effacer l'historique des recherches", role: .destructive) { historique.toutEffacer() }
                    Button("Effacer l'historique d'écoute", role: .destructive) { confirmer = true }
                }

                section("À propos") {
                    ligneInfo("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                }
            }
            .padding(16)
        }
        .background(Palette.fond)
        .navigationTitle("Paramètres")
        .task { mesurer() }
        .confirmationDialog("Effacer tout l'historique d'écoute ?", isPresented: $confirmer, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { historique.effacerEcoutes() }
        }
    }

    private func section<C: View>(_ titre: String, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre).font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 12) { contenu() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface2))
        }
    }

    private func ligneInfo(_ nom: String, _ valeur: String) -> some View {
        HStack {
            Text(nom).font(.system(size: 15))
            Spacer()
            Text(valeur).font(.system(size: 15)).foregroundStyle(Palette.texte2)
        }
    }

    private func taille(_ dossier: URL) -> Int64 {
        let fichiers = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        return fichiers.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func mesurer() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Ecoute")
        tailleCache = taille(caches)
        tailleTelechargements = taille(Stockage.url("x").deletingLastPathComponent())   // dossier des téléchargements
    }

    private func viderCache() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Ecoute")
        for f in (try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
        mesurer()
    }
}

/// Curseur vertical de l'égaliseur (−12 à +12 dB), 0 au milieu ; double toucher = remise à 0.
struct CurseurVertical: View {
    @Binding var valeur: Float
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let y = h / 2 - CGFloat(valeur / 12) * (h / 2)
            ZStack(alignment: .top) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 4).frame(maxHeight: .infinity)
                Rectangle().fill(Palette.citron).frame(width: 4, height: abs(y - h / 2))
                    .offset(y: min(y, h / 2))
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 14, height: 1).offset(y: h / 2)
                Circle().fill(Color.white).frame(width: 20, height: 20).offset(y: y - 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let v = Float((h / 2 - g.location.y) / (h / 2) * 12)
                valeur = (max(-12, min(12, v)) * 2).rounded() / 2
            })
            .onTapGesture(count: 2) { valeur = 0 }
        }
        .accessibilityElement()
        .accessibilityValue(String(format: "%+.0f décibels", valeur))
        .accessibilityAdjustableAction { valeur = max(-12, min(12, valeur + ($0 == .increment ? 1 : -1))) }
    }
}

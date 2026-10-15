import SwiftUI

// Paroles du titre en cours : synchronisées (ligne active en citron, défilement automatique,
// toucher une ligne pour y aller) ou texte simple.
struct ParolesVue: View {
    let titre: Titre

    @Environment(Lecteur.self) private var lecteur
    @State private var paroles: Paroles?
    @State private var charge = false

    var body: some View {
        Group {
            if !charge {
                ProgressView().tint(Palette.citron)
            } else if let paroles, let lignes = paroles.lignes {
                synchronisees(lignes, source: paroles.source)
            } else if let paroles {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(paroles.texte)
                            .font(.system(size: 20, weight: .semibold))
                            .lineSpacing(6)
                        mention(paroles.source)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView("Pas de paroles", systemImage: "quote.bubble",
                                       description: Text("Aucune parole trouvée pour ce titre."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: titre.idVideo) {
            charge = false
            paroles = await ServiceParoles.partage.paroles(pour: titre)
            charge = true
        }
    }

    private func synchronisees(_ lignes: [LigneParole], source: String) -> some View {
        let actif = lignes.lastIndex { $0.temps <= lecteur.position + 0.25 }
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(lignes.indices, id: \.self) { i in
                        Text(lignes[i].texte.isEmpty ? "♪" : lignes[i].texte)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(couleur(i, actif: actif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { lecteur.chercher(a: lignes[i].temps) }
                            .id(i)
                    }
                    mention(source)
                }
                .padding(.vertical, 140)
            }
            .onChange(of: actif) { _, nouvel in
                guard let nouvel else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(nouvel, anchor: .center) }
            }
            .onAppear {
                if let actif { proxy.scrollTo(actif, anchor: .center) }
            }
        }
    }

    private func couleur(_ i: Int, actif: Int?) -> Color {
        guard let actif else { return Palette.texte.opacity(0.55) }
        if i == actif { return Palette.citron }
        return Palette.texte.opacity(i < actif ? 0.35 : 0.55)
    }

    private func mention(_ source: String) -> some View {
        Text("Source : \(source)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.texte3)
    }
}

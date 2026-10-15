import SwiftUI

// Point d'entrée : crée les services une seule fois et les injecte dans l'environnement.
// Aucun serveur du propriétaire : recherche, flux, paroles et téléchargements partent du téléphone.
@main
@MainActor
struct MusiqueLocaleApp: App {
    @State private var historique: Historique
    @State private var telechargements: Telechargements
    @State private var lecteur: Lecteur
    @State private var navigateur = Navigateur()

    init() {
        Palette.configurerApparence()
        let extracteur: any ExtracteurFlux = ExtracteurYouTubeKit()
        let historique = Historique()
        let telechargements = Telechargements(extracteur: extracteur)
        _historique = State(initialValue: historique)
        _telechargements = State(initialValue: telechargements)
        _lecteur = State(initialValue: Lecteur(extracteur: extracteur, telechargements: telechargements, historique: historique))
    }

    var body: some Scene {
        WindowGroup {
            RacineVue()
                .environment(lecteur)
                .environment(telechargements)
                .environment(historique)
                .environment(navigateur)
                .preferredColorScheme(.dark)
                .task { await InnerTube.actualiserVersion() }
                .tint(Palette.citron)
        }
    }
}

import SwiftUI
import UIKit

// Jetons de couleur repris de src/styles.css (app Mac) : fond #030304, accent citron #D1FE17.
enum Palette {
    static let fond = Color(hex: 0x030304)
    static let surface1 = Color(hex: 0x131416)
    static let surface2 = Color(hex: 0x1C1E21)
    static let surface3 = Color(hex: 0x23262A)
    static let bord = Color.white.opacity(0.1)
    static let texte = Color.white
    static let texte2 = Color(hex: 0xA8A8A8)
    static let texte3 = Color(hex: 0x6B6F76)
    static let citron = Color(hex: 0xD1FE17)
    static let citronVoile = Color(hex: 0xD1FE17).opacity(0.12)
    static let surCitron = Color(hex: 0x030304)
    static let danger = Color(hex: 0xFF5A4F)

    /// Barres d'onglets et de navigation noires opaques, titres blancs.
    static func configurerApparence() {
        let noir = UIColor(fond)
        let onglets = UITabBarAppearance()
        onglets.configureWithOpaqueBackground()
        onglets.backgroundColor = noir
        onglets.shadowColor = UIColor.white.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = onglets
        UITabBar.appearance().scrollEdgeAppearance = onglets

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = noir
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

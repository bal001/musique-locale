import Foundation
import Observation

// Recherches et écoutes récentes, titres J'aime, albums/playlists/artistes enregistrés :
// la « bibliothèque » de YouTube Music, gardée sur le téléphone (UserDefaults, JSON).
@Observable
@MainActor
final class Historique {
    private(set) var recherches: [String] = []
    private(set) var ecoutes: [Titre] = []
    private(set) var jaime: [Titre] = []
    private(set) var enregistres: [Carte] = []   // albums, playlists, artistes suivis
    private(set) var playlists: [PlaylistPerso] = []
    private(set) var jaimePas: Set<String> = []    // 👎 : jamais proposé par les recommandations
    private(set) var zappes: Set<String> = []      // passés dans les 30 premières secondes
    private(set) var consultes: [Element] = []     // résultats ouverts depuis la recherche (« Recherches récentes »)
    private(set) var gouts: [String: Gout] = [:]    // profil de goûts par artiste

    @ObservationIgnored private let defauts = UserDefaults.standard
    private static let cleRecherches = "recherchesRecentes"
    private static let cleEcoutes = "ecoutesRecentes"
    private static let cleJaime = "titresJaime"
    private static let cleEnregistres = "bibliotheque"
    private static let clePlaylists = "playlistsPerso"
    private static let cleJaimePas = "jaimePas"
    private static let cleZappes = "zappes"
    private static let cleConsultes = "consultes"
    private static let cleGouts = "gouts"

    init() {
        recherches = defauts.stringArray(forKey: Self.cleRecherches) ?? []
        if let donnees = defauts.data(forKey: Self.cleEcoutes),
           let liste = try? JSONDecoder().decode([Titre].self, from: donnees) {
            ecoutes = liste
        }
        jaime = Self.lire(Self.cleJaime) ?? []
        enregistres = Self.lire(Self.cleEnregistres) ?? []
        playlists = Self.lire(Self.clePlaylists) ?? []
        jaimePas = Self.lire(Self.cleJaimePas) ?? []
        zappes = Self.lire(Self.cleZappes) ?? []
        consultes = Self.lire(Self.cleConsultes) ?? []
        gouts = Self.lire(Self.cleGouts) ?? [:]
    }

    private static func lire<T: Decodable>(_ cle: String) -> T? {
        UserDefaults.standard.data(forKey: cle).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func ecrire<T: Encodable>(_ valeur: T, _ cle: String) {
        if let donnees = try? JSONEncoder().encode(valeur) { defauts.set(donnees, forKey: cle) }
    }

    // MARK: J'aime

    func aime(_ titre: Titre) -> Bool { jaime.contains { $0.idVideo == titre.idVideo } }

    func basculerJaime(_ titre: Titre) {
        if aime(titre) { jaime.removeAll { $0.idVideo == titre.idVideo } } else {
            jaime.insert(titre, at: 0)
            modifierGout(titre, graineSiMeilleur: true) { $0.jaime += 1 }
            jaimePas.remove(titre.idVideo)
            zappes.remove(titre.idVideo)
            ecrire(zappes, Self.cleZappes)
            ecrire(jaimePas, Self.cleJaimePas)
        }
        ecrire(jaime, Self.cleJaime)
    }

    func aimePas(_ titre: Titre) -> Bool { jaimePas.contains(titre.idVideo) }

    // MARK: Profil de goûts (ce que vous écoutez vraiment, artiste par artiste)

    struct Gout: Codable {
        var ecoutes = 0       // écoutes d'au moins une minute
        var completes = 0     // écoutes jusqu'au bout
        var zaps = 0          // passés dans les 30 premières secondes
        var jaime = 0
        var dernier = Date.now
        var graine: Titre     // titre préféré de l'artiste, point de départ des mix

        /// Poids récent : les goûts du moment comptent plus (moitié moins tous les 14 jours).
        var score: Double {
            let brut = Double(completes * 2 + ecoutes + jaime * 4) - Double(zaps * 2)
            let jours = Date.now.timeIntervalSince(dernier) / 86400
            return brut * pow(0.5, jours / 14)
        }
    }

    private func cleArtiste(_ t: Titre) -> String {
        (t.artiste.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? t.artiste)
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func modifierGout(_ t: Titre, graineSiMeilleur: Bool, _ change: (inout Gout) -> Void) {
        let cle = cleArtiste(t)
        guard !cle.isEmpty else { return }
        var g = gouts[cle] ?? Gout(graine: t)
        change(&g)
        g.dernier = .now
        if graineSiMeilleur { g.graine = t }
        gouts[cle] = g
        ecrire(gouts, Self.cleGouts)
    }

    /// Fin d'écoute : jusqu'au bout, ou au moins une minute.
    func noterEcouteReelle(_ titre: Titre, complete: Bool) {
        modifierGout(titre, graineSiMeilleur: complete) { complete ? ($0.completes += 1) : ($0.ecoutes += 1) }
    }

    /// Assez d'écoutes pour proposer des mix personnels (comme YouTube Music, après un peu d'utilisation).
    var profilSuffisant: Bool {
        let utiles = gouts.values.reduce(0) { $0 + $1.ecoutes + $1.completes }
        return utiles >= 8 && gouts.values.filter { $0.score > 0 }.count >= 2
    }

    /// Artistes préférés, du mieux noté au moins bien noté, avec le titre qui sert de graine.
    func artistesPreferes(_ n: Int) -> [Titre] {
        gouts.values.filter { $0.score > 0 }.sorted { $0.score > $1.score }.prefix(n).map(\.graine)
    }

    /// Artiste zappé bien plus souvent qu'écouté : écarté des recommandations.
    func artisteEvite(_ t: Titre) -> Bool {
        guard let g = gouts[cleArtiste(t)] else { return false }
        return g.zaps >= 3 && g.zaps > (g.ecoutes + g.completes) * 2
    }

    /// Titre passé très vite : signal négatif pour les recommandations (oublié si on l'aime ensuite).
    func noterZap(_ titre: Titre) {
        guard !aime(titre) else { return }
        modifierGout(titre, graineSiMeilleur: false) { $0.zaps += 1 }
        zappes.insert(titre.idVideo)
        if zappes.count > 500 { zappes.removeFirst() }
        ecrire(zappes, Self.cleZappes)
    }

    func basculerJaimePas(_ titre: Titre) {
        if jaimePas.remove(titre.idVideo) == nil {
            jaimePas.insert(titre.idVideo)
            if aime(titre) { basculerJaime(titre) }
        }
        ecrire(jaimePas, Self.cleJaimePas)
    }

    // MARK: Playlists personnelles

    @discardableResult
    func creerPlaylist(_ nom: String, titres: [Titre] = []) -> PlaylistPerso {
        let p = PlaylistPerso(nom: nom.trimmingCharacters(in: .whitespaces).isEmpty ? "Nouvelle playlist" : nom, titres: titres)
        playlists.insert(p, at: 0)
        ecrire(playlists, Self.clePlaylists)
        return p
    }

    func ajouter(_ titres: [Titre], a idPlaylist: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == idPlaylist }) else { return }
        let deja = Set(playlists[i].titres.map(\.idVideo))
        playlists[i].titres += titres.filter { !deja.contains($0.idVideo) }
        playlists[i].modifieLe = .now
        ecrire(playlists, Self.clePlaylists)
    }

    func modifierPlaylist(_ id: UUID, _ change: (inout PlaylistPerso) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
        playlists[i].modifieLe = .now
        ecrire(playlists, Self.clePlaylists)
    }

    func supprimerPlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        ecrire(playlists, Self.clePlaylists)
    }

    // MARK: Bibliothèque (albums, playlists, artistes)

    func estEnregistre(_ carte: Carte) -> Bool { enregistres.contains { $0.idPage == carte.idPage } }

    func basculerEnregistrement(_ carte: Carte) {
        if estEnregistre(carte) { enregistres.removeAll { $0.idPage == carte.idPage } } else { enregistres.insert(carte, at: 0) }
        ecrire(enregistres, Self.cleEnregistres)
    }

    func effacerEcoutes() {
        ecoutes = []
        defauts.removeObject(forKey: Self.cleEcoutes)
    }

    func retirerEcoute(_ titre: Titre) {
        ecoutes.removeAll { $0.idVideo == titre.idVideo }
        ecrire(ecoutes, Self.cleEcoutes)
    }

    func ajouterRecherche(_ requete: String) {
        let q = requete.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recherches.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recherches.insert(q, at: 0)
        recherches = Array(recherches.prefix(20))
        defauts.set(recherches, forKey: Self.cleRecherches)
    }

    func supprimerRecherche(_ requete: String) {
        recherches.removeAll { $0 == requete }
        defauts.set(recherches, forKey: Self.cleRecherches)
    }

    func toutEffacer() {
        recherches = []
        consultes = []
        defauts.removeObject(forKey: Self.cleRecherches)
        defauts.removeObject(forKey: Self.cleConsultes)
    }

    /// Résultat touché dans la recherche : en tête des « Recherches récentes ».
    func noterConsulte(_ e: Element) {
        consultes.removeAll { $0.id == e.id }
        consultes.insert(e, at: 0)
        consultes = Array(consultes.prefix(15))
        ecrire(consultes, Self.cleConsultes)
    }

    func retirerConsulte(_ e: Element) {
        consultes.removeAll { $0.id == e.id }
        ecrire(consultes, Self.cleConsultes)
    }

    func ajouterEcoute(_ titre: Titre) {
        ecoutes.removeAll { $0.idVideo == titre.idVideo }
        ecoutes.insert(titre, at: 0)
        ecoutes = Array(ecoutes.prefix(30))
        if let donnees = try? JSONEncoder().encode(ecoutes) { defauts.set(donnees, forKey: Self.cleEcoutes) }
    }
}

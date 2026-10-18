import Foundation
import Security

// Spotify, par la porte officielle : la clé gratuite du propriétaire (developer.spotify.com, app « Musique Locale »).
// Le Client ID n'est pas secret ; le Client Secret est gardé dans le coffre de GitHub et inséré dans l'app à sa
// fabrication (jamais dans le code : le dépôt est public). On peut aussi le taper dans Paramètres (trousseau de l'iPhone). Sert aux nouveautés : « New releases » de Spotify
// par pays, ajoutées aux sources Apple Music et Deezer.
enum Spotify {
    static let clientIDParDefaut = "35c94161ecbc43cba1be1f9de6c3fe95"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "spotifyClientID") ?? clientIDParDefaut }
        set { UserDefaults.standard.set(newValue, forKey: "spotifyClientID") }
    }
    /// Secret tapé dans Paramètres, sinon celui inséré par GitHub à la fabrication de l'app (coffre « SPOTIFY_CLIENT_SECRET »).
    static var secret: String? {
        get {
            if let s = Trousseau.lire("spotifySecret") { return s }
            let fabrique = (Bundle.main.object(forInfoDictionaryKey: "SpotifySecret") as? String ?? "").trimmingCharacters(in: .whitespaces)
            return fabrique.isEmpty || fabrique.hasPrefix("$(") ? nil : fabrique
        }
        set { if let newValue, !newValue.isEmpty { Trousseau.ecrire("spotifySecret", newValue) } else { Trousseau.effacer("spotifySecret") } }
    }
    static var estBranche: Bool { secret != nil }

    private actor Jeton {
        var valeur: String?
        var expire = Date.distantPast
        func lire() async -> String? {
            if let valeur, Date.now < expire { return valeur }
            guard let secret = Spotify.secret else { return nil }
            var requete = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 12)
            requete.httpMethod = "POST"
            requete.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            requete.setValue("Basic " + Data("\(Spotify.clientID):\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            requete.httpBody = Data("grant_type=client_credentials".utf8)
            guard let (donnees, _) = try? await URLSession.shared.data(for: requete),
                  let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
                  let jeton = json["access_token"] as? String else { return nil }
            valeur = jeton
            expire = Date.now.addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
            return jeton
        }
        func oublier() { valeur = nil }
    }
    private static let jeton = Jeton()

    /// Vérifie la clé (Paramètres) : vrai si Spotify accepte l'identifiant et le secret.
    static func tester() async -> Bool {
        await jeton.oublier()
        return await jeton.lire() != nil
    }

    static func demander(_ chemin: String) async -> [String: Any]? {
        guard let j = await jeton.lire(), let url = URL(string: "https://api.spotify.com/v1/" + chemin) else { return nil }
        var requete = URLRequest(url: url, timeoutInterval: 12)
        requete.setValue("Bearer \(j)", forHTTPHeaderField: "Authorization")
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: donnees) as? [String: Any]
    }

    struct Sortie: Sendable { var nom: String; var artiste: String; var date: String; var type: String; var image: String? }

    /// Nouveautés Spotify d'un pays (« fr », « us », « gb ») : 100 dernières sorties.
    static func nouveautes(_ pays: String) async -> [Sortie] {
        guard estBranche else { return [] }
        var resultat: [Sortie] = []
        for decalage in [0, 50] {
            guard let json = await demander("browse/new-releases?country=\(pays.uppercased())&limit=50&offset=\(decalage)"),
                  let items = (json["albums"] as? [String: Any])?["items"] as? [[String: Any]] else { break }
            resultat += items.compactMap { a in
                guard let nom = a["name"] as? String, let date = a["release_date"] as? String,
                      let artiste = (a["artists"] as? [[String: Any]])?.first?["name"] as? String else { return nil }
                let image = ((a["images"] as? [[String: Any]])?.first)?["url"] as? String
                return Sortie(nom: nom, artiste: artiste, date: date, type: a["album_type"] as? String ?? "album", image: image)
            }
        }
        return resultat
    }
}

/// Trousseau de l'iPhone (mots de passe chiffrés, propres à l'app).
enum Trousseau {
    private static func requete(_ cle: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MusiqueLocale", kSecAttrAccount as String: cle]
    }
    static func lire(_ cle: String) -> String? {
        var q = requete(cle)
        q[kSecReturnData as String] = true
        var resultat: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultat) == errSecSuccess, let d = resultat as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func ecrire(_ cle: String, _ valeur: String) {
        effacer(cle)
        var q = requete(cle)
        q[kSecValueData as String] = Data(valeur.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func effacer(_ cle: String) { SecItemDelete(requete(cle) as CFDictionary) }
}

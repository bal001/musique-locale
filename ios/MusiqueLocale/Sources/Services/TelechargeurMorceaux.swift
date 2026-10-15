import Foundation

// Téléchargement par morceaux : demandé d'un seul coup, un fichier YouTube est bridé (~25 Ko/s, 2 min 30 par titre) ;
// demandé par plages de 2 Mo, il arrive à pleine vitesse. 4 morceaux à la fois, écrits directement dans le fichier.
enum TelechargeurMorceaux {
    static let tailleMorceau = 2_000_000

    static func telecharger(_ url: URL, vers destination: URL, progression: @escaping @Sendable (Double) -> Void) async throws {
        // 1er morceau : donne aussi la taille totale (Content-Range « bytes 0-1999999/4557665 »).
        let (premier, reponse) = try await morceau(url, debut: 0, fin: tailleMorceau - 1)
        guard let http = reponse as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw ErreurReseau.statut((reponse as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let total = (http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last).flatMap { Int($0) } ?? premier.count
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fichier = try FileHandle(forWritingTo: destination)
        defer { try? fichier.close() }
        try fichier.write(contentsOf: premier)
        try fichier.truncate(atOffset: UInt64(total))
        let recus = Compteur(premier.count)
        progression(Double(premier.count) / Double(max(total, 1)))
        guard http.statusCode == 206, total > premier.count else { return }

        let plages = stride(from: premier.count, to: total, by: tailleMorceau).map { ($0, min($0 + tailleMorceau, total) - 1) }
        for lot in stride(from: 0, to: plages.count, by: 4).map({ Array(plages[$0..<min($0 + 4, plages.count)]) }) {
            try await withThrowingTaskGroup(of: (Int, Data).self) { groupe in
                for (debut, fin) in lot {
                    groupe.addTask {
                        // Un morceau qui échoue est redemandé (jusqu'à 3 fois).
                        for essai in 1...3 {
                            if let (d, r) = try? await morceau(url, debut: debut, fin: fin),
                               (r as? HTTPURLResponse)?.statusCode == 206, d.count == fin - debut + 1 { return (debut, d) }
                            try await Task.sleep(for: .milliseconds(500 * essai))
                        }
                        throw ErreurReseau.indisponible
                    }
                }
                for try await (debut, donnees) in groupe {
                    try fichier.seek(toOffset: UInt64(debut))
                    try fichier.write(contentsOf: donnees)
                    progression(Double(await recus.ajouter(donnees.count)) / Double(total))
                }
            }
        }
    }

    private static func morceau(_ url: URL, debut: Int, fin: Int) async throws -> (Data, URLResponse) {
        var requete = URLRequest(url: url, timeoutInterval: 30)
        requete.setValue("bytes=\(debut)-\(fin)", forHTTPHeaderField: "Range")
        return try await URLSession.shared.data(for: requete)
    }

    private actor Compteur {
        private var valeur: Int
        init(_ v: Int) { valeur = v }
        func ajouter(_ n: Int) -> Int { valeur += n; return valeur }
    }
}

/// Au plus 3 titres téléchargés en même temps (« Tout télécharger » sur une grande playlist reste fluide).
actor FileTelechargements {
    static let partage = FileTelechargements()
    private var actifs = 0
    private var enAttente: [CheckedContinuation<Void, Never>] = []

    func entrer() async {
        if actifs < 3 { actifs += 1; return }
        await withCheckedContinuation { enAttente.append($0) }
    }

    func sortir() {
        if enAttente.isEmpty { actifs -= 1 } else { enAttente.removeFirst().resume() }
    }
}

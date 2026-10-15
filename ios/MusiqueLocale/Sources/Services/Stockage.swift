import Foundation

// Emplacements sur le téléphone : Application Support/Telechargements/
//   <idVideo>.m4a | <idVideo>.mp4   fichiers audio ou clip
//   <idVideo>.jpg                  pochette
//   <idVideo>.paroles.json         paroles
//   index.json                     liste des téléchargements
enum Stockage {
    static let dossier: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Telechargements", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func url(_ nom: String) -> URL { dossier.appendingPathComponent(nom) }
    static func pochette(_ idVideo: String) -> URL { url("\(idVideo).jpg") }
    static func paroles(_ idVideo: String) -> URL { url("\(idVideo).paroles.json") }
    static var index: URL { url("index.json") }

    static func existe(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    static func parolesLocales(_ idVideo: String) -> Paroles? {
        guard let donnees = try? Data(contentsOf: paroles(idVideo)) else { return nil }
        return try? JSONDecoder().decode(Paroles.self, from: donnees)
    }
}

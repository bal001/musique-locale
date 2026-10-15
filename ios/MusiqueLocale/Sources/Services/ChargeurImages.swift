import UIKit

// Chargement des pochettes et vignettes : cache mémoire + disque (URLCache), une seule requête par image,
// et nouvel essai en cas d'échec. Remplace AsyncImage, qui abandonne au défilement des rangées et ne réessaie pas.
actor ChargeurImages {
    static let partage = ChargeurImages()
    private let memoire = NSCache<NSURL, UIImage>()
    private var enCours: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 40 << 20, diskCapacity: 300 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    init() { memoire.countLimit = 400 }

    nonisolated func enMemoire(_ url: URL) -> UIImage? { memoire.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let i = memoire.object(forKey: url as NSURL) { return i }
        if let tache = enCours[url] { return await tache.value }
        let tache = Task<UIImage?, Never> {
            for essai in 0..<3 {
                if let (donnees, _) = try? await session.data(from: url),
                   let image = await UIImage(data: donnees)?.byPreparingForDisplay() {
                    return image
                }
                try? await Task.sleep(for: .milliseconds(400 * (essai + 1)))
            }
            return nil
        }
        enCours[url] = tache
        let image = await tache.value
        enCours[url] = nil
        if let image { memoire.setObject(image, forKey: url as NSURL) }
        return image
    }
}

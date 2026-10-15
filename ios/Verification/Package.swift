// swift-tools-version:5.9
// Vérification de chaque nuit (GitHub Actions) : le code de l'app iPhone parle toujours bien à YouTube Music.
import PackageDescription

let package = Package(
    name: "Verification",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/alexeichhorn/YouTubeKit", exact: "0.4.9")],
    targets: [.executableTarget(name: "Verification", dependencies: ["YouTubeKit"],
                                swiftSettings: [.unsafeFlags(["-swift-version", "5"])])]
)

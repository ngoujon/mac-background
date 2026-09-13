// swift-tools-version: 6.0
import PackageDescription
import Foundation

// MultiPlash — fonds d'écran web, un par écran.
// Aucune dépendance externe : uniquement AppKit / WebKit / swift-testing du système.

/// Sans Xcode installé, swift-testing vit dans les Command Line Tools et n'est
/// ni dans le SDK ni dans les chemins de recherche par défaut : on les ajoute.
/// Avec Xcode, SwiftPM s'en charge seul et ces réglages restent vides.
private let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
private let commandLineToolsLibraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
private let needsCommandLineToolsTesting =
    FileManager.default.fileExists(atPath: commandLineToolsFrameworks + "/Testing.framework")
    && !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")

private let testSwiftSettings: [SwiftSetting] = needsCommandLineToolsTesting
    ? [.swiftLanguageMode(.v5), .unsafeFlags(["-F", commandLineToolsFrameworks])]
    : [.swiftLanguageMode(.v5)]

private let testLinkerSettings: [LinkerSetting] = needsCommandLineToolsTesting
    ? [.unsafeFlags(["-F", commandLineToolsFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworks,
                     "-Xlinker", "-rpath", "-Xlinker", commandLineToolsLibraries])]
    : []

let package = Package(
    name: "MultiPlash",
    platforms: [.macOS(.v14)],
    targets: [
        // Cœur testable : modèle de configuration, persistance, résolution des sources.
        .target(name: "MultiPlashCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // Application AppKit (barre des menus + fenêtres au niveau du bureau).
        .executableTarget(name: "MultiPlash",
                          dependencies: ["MultiPlashCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Tests (swift-testing).
        .testTarget(name: "MultiPlashCoreTests",
                    dependencies: ["MultiPlashCore"],
                    swiftSettings: testSwiftSettings,
                    linkerSettings: testLinkerSettings),
    ]
)

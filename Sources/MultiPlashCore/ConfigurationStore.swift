import Foundation

/// Lecture / écriture de `config.json`.
///
/// Emplacement par défaut : `~/Library/Application Support/MultiPlash/config.json`.
/// Le dossier est injectable pour les tests.
public final class ConfigurationStore {

    public let directory: URL

    public var fileURL: URL { directory.appendingPathComponent("config.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Emplacement standard de l'application.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MultiPlash", isDirectory: true)
    }

    public convenience init() {
        self.init(directory: ConfigurationStore.defaultDirectory())
    }

    /// Charge la configuration. Un fichier absent ou illisible donne une configuration
    /// vide plutôt qu'une erreur : l'application doit toujours pouvoir démarrer.
    public func load() -> AppConfiguration {
        guard let data = try? Data(contentsOf: fileURL) else { return AppConfiguration() }
        guard let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return AppConfiguration()
        }
        return configuration
    }

    /// Écrit la configuration de façon atomique (fichier lisible, clés triées).
    public func save(_ configuration: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}

import Testing
import Foundation
@testable import MultiPlashCore

/// Encodage / décodage / persistance de la configuration.
@Suite("Configuration : encodage et persistance")
struct ConfigurationCodingTests {

    private func roundTrip(_ configuration: AppConfiguration) throws -> AppConfiguration {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(configuration)
        return try JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    /// Dossier de travail temporaire, à l'intérieur du projet (rien n'est écrit ailleurs).
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/tests-tmp/\(UUID().uuidString)", isDirectory: true)
    }

    @Test("L'aller-retour JSON conserve les trois types de source")
    func allerRetourConserveLesSources() throws {
        var configuration = AppConfiguration(isPaused: true)
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran principal",
                                source: .folder("/Users/moi/Pictures/Fonds animés/Trou noir"),
                                parameters: "fps=30&q=0.7",
                                isEnabled: true),
            forUUID: "UUID-A")
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran secondaire",
                                source: .url("https://exemple.com/fond"),
                                parameters: "",
                                isEnabled: false),
            forUUID: "UUID-B")
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Sans source", source: .none),
            forUUID: "UUID-C")

        let decoded = try roundTrip(configuration)
        #expect(decoded == configuration)
        #expect(decoded.isPaused)
        #expect(decoded.screens["UUID-A"]?.source == .folder("/Users/moi/Pictures/Fonds animés/Trou noir"))
        #expect(decoded.screens["UUID-A"]?.parameters == "fps=30&q=0.7")
        #expect(decoded.screens["UUID-B"]?.source == .url("https://exemple.com/fond"))
        #expect(decoded.screens["UUID-B"]?.isEnabled == false)
        #expect(decoded.screens["UUID-C"]?.source == ScreenSource.none)
    }

    @Test("Le JSON produit a une forme lisible et stable")
    func formatJSONLisible() throws {
        var configuration = AppConfiguration()
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran principal", source: .folder("/tmp/fond"), parameters: "fps=30"),
            forUUID: "UUID-A")
        let data = try JSONEncoder().encode(configuration)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let screens = try #require(json["screens"] as? [String: Any])
        let screen = try #require(screens["UUID-A"] as? [String: Any])
        let source = try #require(screen["source"] as? [String: Any])
        #expect(source["type"] as? String == "folder")
        #expect(source["value"] as? String == "/tmp/fond")
        #expect(screen["displayName"] as? String == "Écran principal")
        #expect(screen["parameters"] as? String == "fps=30")
        #expect(json["schemaVersion"] as? Int == AppConfiguration.currentSchemaVersion)
    }

    @Test("Une clé absente reprend sa valeur par défaut")
    func decodageTolerant() throws {
        let json = """
        {"screens": {"UUID-A": {"source": {"type": "url", "value": "https://exemple.com"}}}}
        """
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))
        let screen = try #require(decoded.screens["UUID-A"])
        #expect(screen.source == .url("https://exemple.com"))
        #expect(screen.parameters == "")
        #expect(screen.isEnabled)
        #expect(decoded.isPaused == false)
        #expect(decoded.schemaVersion == AppConfiguration.currentSchemaVersion)
    }

    @Test("Enregistrement puis relecture sur disque")
    func enregistrementEtRelecture() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConfigurationStore(directory: directory)
        #expect(store.fileURL.lastPathComponent == "config.json")
        #expect(store.load() == AppConfiguration(), "fichier absent = configuration vide")

        var configuration = AppConfiguration()
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran principal",
                                source: .folder("/Users/moi/Pictures/Fonds animés/Galaxies"),
                                parameters: "q=0.7"),
            forUUID: "UUID-A")
        try store.save(configuration)

        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.load() == configuration)
    }

    @Test("Un fichier illisible ne bloque pas le démarrage")
    func fichierIllisible() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(directory: directory)
        try Data("ceci n'est pas du JSON".utf8).write(to: store.fileURL)
        #expect(store.load() == AppConfiguration())
    }

    @Test("Le dossier par défaut est bien ~/Library/Application Support/MultiPlash")
    func dossierParDefaut() {
        let path = ConfigurationStore.defaultDirectory().path
        #expect(path.hasSuffix("Library/Application Support/MultiPlash"), "\(path)")
    }
}

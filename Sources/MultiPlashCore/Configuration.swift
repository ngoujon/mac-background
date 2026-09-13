import Foundation

/// Ce qu'un écran doit afficher.
///
/// Encodé en JSON sous une forme lisible : `{"type": "folder", "value": "/chemin"}`.
public enum ScreenSource: Equatable, Sendable {
    /// Aucune source : l'écran reste vide (fond système visible).
    case none
    /// Une adresse web distante (http/https).
    case url(String)
    /// Un dossier local contenant un `index.html`.
    case folder(String)

    /// Libellé court affiché dans le menu.
    public var displayDescription: String {
        switch self {
        case .none: return "aucune source"
        case .url(let value): return value
        case .folder(let path): return (path as NSString).lastPathComponent
        }
    }
}

extension ScreenSource: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case none, url, folder }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .none:
            self = .none
        case .url:
            self = .url(try container.decode(String.self, forKey: .value))
        case .folder:
            self = .folder(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .type)
        case .url(let value):
            try container.encode(Kind.url, forKey: .type)
            try container.encode(value, forKey: .value)
        case .folder(let path):
            try container.encode(Kind.folder, forKey: .type)
            try container.encode(path, forKey: .value)
        }
    }
}

/// Réglages d'un écran donné, identifié par l'UUID de son affichage.
public struct ScreenConfiguration: Codable, Equatable, Sendable {
    /// Nom lisible de l'écran au moment du dernier enregistrement (purement informatif).
    public var displayName: String
    /// Source à charger.
    public var source: ScreenSource
    /// Paramètres ajoutés en query string à la source, par exemple `fps=30&q=0.7`.
    public var parameters: String
    /// Faux = l'écran est laissé tel quel (pas de fenêtre créée).
    public var isEnabled: Bool

    public init(displayName: String = "",
                source: ScreenSource = .none,
                parameters: String = "",
                isEnabled: Bool = true) {
        self.displayName = displayName
        self.source = source
        self.parameters = parameters
        self.isEnabled = isEnabled
    }

    // Décodage tolérant : une clé absente reprend la valeur par défaut,
    // ce qui permet de faire évoluer le format sans casser les fichiers existants.
    private enum CodingKeys: String, CodingKey { case displayName, source, parameters, isEnabled }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        source = try container.decodeIfPresent(ScreenSource.self, forKey: .source) ?? .none
        parameters = try container.decodeIfPresent(String.self, forKey: .parameters) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// Configuration complète de l'application, telle qu'elle est écrite dans `config.json`.
public struct AppConfiguration: Codable, Equatable, Sendable {
    /// Version du format, pour d'éventuelles migrations futures.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Pause globale : toutes les fenêtres sont suspendues.
    public var isPaused: Bool
    /// Minutes d'inactivité avant de lancer l'économiseur d'écran (0 = jamais).
    ///
    /// Cette minuterie est celle de MultiPlash, pas celle de macOS : elle ignore
    /// les applications qui maintiennent l'écran allumé (verrou système
    /// « PreventUserIdleDisplaySleep »), lesquelles empêchent normalement
    /// l'économiseur de démarrer.
    public var screenSaverAfterMinutes: Int
    /// Réglages indexés par UUID d'écran (`CGDisplayCreateUUIDFromDisplayID`).
    public var screens: [String: ScreenConfiguration]

    public init(schemaVersion: Int = AppConfiguration.currentSchemaVersion,
                isPaused: Bool = false,
                screenSaverAfterMinutes: Int = 5,
                screens: [String: ScreenConfiguration] = [:]) {
        self.schemaVersion = schemaVersion
        self.isPaused = isPaused
        self.screenSaverAfterMinutes = screenSaverAfterMinutes
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, isPaused, screenSaverAfterMinutes, screens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppConfiguration.currentSchemaVersion
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        screenSaverAfterMinutes = try container.decodeIfPresent(Int.self, forKey: .screenSaverAfterMinutes) ?? 5
        screens = try container.decodeIfPresent([String: ScreenConfiguration].self, forKey: .screens) ?? [:]
    }

    /// Réglages d'un écran. Un écran inconnu reçoit une configuration par défaut
    /// (activée, sans source) portant le nom fourni : rien n'est enregistré tant
    /// que l'utilisateur n'a pas choisi de source.
    public func configuration(forUUID uuid: String, displayName: String = "") -> ScreenConfiguration {
        if var existing = screens[uuid] {
            // Le nom peut avoir changé (écran renommé, remplacé par un modèle identique).
            if !displayName.isEmpty { existing.displayName = displayName }
            return existing
        }
        return ScreenConfiguration(displayName: displayName)
    }

    /// Vrai si cet écran a déjà été configuré explicitement.
    public func isKnown(uuid: String) -> Bool { screens[uuid] != nil }

    public mutating func setConfiguration(_ configuration: ScreenConfiguration, forUUID uuid: String) {
        screens[uuid] = configuration
    }

    /// Modifie (ou crée) les réglages d'un écran sur place.
    @discardableResult
    public mutating func update(uuid: String,
                                displayName: String = "",
                                _ body: (inout ScreenConfiguration) -> Void) -> ScreenConfiguration {
        var configuration = self.configuration(forUUID: uuid, displayName: displayName)
        body(&configuration)
        screens[uuid] = configuration
        return configuration
    }
}

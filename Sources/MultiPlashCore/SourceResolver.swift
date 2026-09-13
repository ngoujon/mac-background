import Foundation

/// Ce qu'il faut demander au WKWebView pour afficher une source donnée.
public enum LoadDestination: Equatable {
    /// Adresse distante à charger telle quelle.
    case remote(URL)
    /// Fichier local `index` à charger, avec accès en lecture accordé à `readAccess`
    /// (le dossier), pour que les ressources voisines (shaders, textures…) se chargent.
    case local(index: URL, readAccess: URL)
}

/// Traduit une `ScreenConfiguration` en URL réellement chargée.
public enum SourceResolver {

    /// Nettoie le champ « paramètres » saisi par l'utilisateur :
    /// on accepte aussi bien `fps=30&q=0.7` que `?fps=30&q=0.7`.
    public static func normalizedParameters(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("?") || value.hasPrefix("&") { value.removeFirst() }
        while value.hasSuffix("&") { value.removeLast() }
        return value
    }

    /// Ajoute les paramètres en query string, en conservant ceux déjà présents.
    public static func applyingParameters(_ raw: String, to url: URL) -> URL {
        let parameters = normalizedParameters(raw)
        guard !parameters.isEmpty else { return url }
        let text = url.absoluteString
        // Le fragment (#…) doit rester en dernier.
        let separator = text.contains("?") ? "&" : "?"
        if let hashIndex = text.firstIndex(of: "#") {
            let head = String(text[text.startIndex..<hashIndex])
            let tail = String(text[hashIndex...])
            return URL(string: head + separator + parameters + tail) ?? url
        }
        return URL(string: text + separator + parameters) ?? url
    }

    /// Destination à charger, ou `nil` si la source est vide/invalide.
    public static func destination(for configuration: ScreenConfiguration) -> LoadDestination? {
        switch configuration.source {
        case .none:
            return nil

        case .url(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // On tolère « exemple.com » en complétant le schéma.
            let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard let url = URL(string: withScheme), url.host != nil else { return nil }
            return .remote(applyingParameters(configuration.parameters, to: url))

        case .folder(let path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let folder = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
            let index = folder.appendingPathComponent("index.html")
            return .local(index: applyingParameters(configuration.parameters, to: index),
                          readAccess: folder)
        }
    }

    /// Vrai si le dossier contient bien un `index.html` lisible.
    public static func folderContainsIndex(_ path: String) -> Bool {
        let folder = (path as NSString).expandingTildeInPath
        let index = (folder as NSString).appendingPathComponent("index.html")
        return FileManager.default.isReadableFile(atPath: index)
    }
}

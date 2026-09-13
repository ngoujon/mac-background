import Testing
import Foundation
@testable import MultiPlashCore

/// Construction de l'URL réellement chargée (source + paramètres).
@Suite("Résolution des sources")
struct SourceResolverTests {

    @Test("Les paramètres saisis sont nettoyés")
    func nettoyageParametres() {
        #expect(SourceResolver.normalizedParameters("  ?fps=30&q=0.7&  ") == "fps=30&q=0.7")
        #expect(SourceResolver.normalizedParameters("") == "")
        #expect(SourceResolver.normalizedParameters("   ") == "")
    }

    @Test("Les paramètres sont ajoutés en query string")
    func parametresAjoutes() throws {
        let base = try #require(URL(string: "https://exemple.com/fond"))
        #expect(SourceResolver.applyingParameters("fps=30", to: base).absoluteString
                == "https://exemple.com/fond?fps=30")

        let avecQuery = try #require(URL(string: "https://exemple.com/fond?a=1"))
        #expect(SourceResolver.applyingParameters("fps=30", to: avecQuery).absoluteString
                == "https://exemple.com/fond?a=1&fps=30")

        let avecFragment = try #require(URL(string: "https://exemple.com/fond#haut"))
        #expect(SourceResolver.applyingParameters("fps=30", to: avecFragment).absoluteString
                == "https://exemple.com/fond?fps=30#haut")

        #expect(SourceResolver.applyingParameters("", to: base) == base)
    }

    @Test("Un dossier local donne index.html + accès au dossier")
    func destinationLocale() throws {
        let configuration = ScreenConfiguration(displayName: "X",
                                                source: .folder("/Users/moi/Fonds/Trou noir"),
                                                parameters: "fps=30&q=0.7")
        let destination = try #require(SourceResolver.destination(for: configuration))
        guard case .local(let index, let readAccess) = destination else {
            Issue.record("destination locale attendue")
            return
        }
        #expect(readAccess.path == "/Users/moi/Fonds/Trou noir")
        #expect(index.absoluteString.hasSuffix("index.html?fps=30&q=0.7"), "\(index.absoluteString)")
    }

    @Test("Le tilde est développé dans les chemins")
    func tildeDeveloppe() throws {
        let configuration = ScreenConfiguration(source: .folder("~/Fonds/Galaxies"))
        let destination = try #require(SourceResolver.destination(for: configuration))
        guard case .local(_, let readAccess) = destination else {
            Issue.record("destination locale attendue")
            return
        }
        #expect(readAccess.path.hasPrefix(NSHomeDirectory()))
    }

    @Test("Une adresse sans schéma est complétée en https")
    func schemaImplicite() throws {
        let configuration = ScreenConfiguration(source: .url("exemple.com/fond"))
        let destination = try #require(SourceResolver.destination(for: configuration))
        #expect(destination == .remote(URL(string: "https://exemple.com/fond")!))
    }

    @Test("Les sources vides ou invalides ne donnent aucune destination")
    func sourcesVides() {
        #expect(SourceResolver.destination(for: ScreenConfiguration(source: .none)) == nil)
        #expect(SourceResolver.destination(for: ScreenConfiguration(source: .url("   "))) == nil)
        #expect(SourceResolver.destination(for: ScreenConfiguration(source: .folder(""))) == nil)
    }
}

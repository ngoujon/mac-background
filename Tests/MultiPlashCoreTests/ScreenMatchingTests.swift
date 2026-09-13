import Testing
import Foundation
@testable import MultiPlashCore

/// Association écran ↔ configuration par UUID d'affichage.
@Suite("Association écran ↔ configuration")
struct ScreenMatchingTests {

    private let uuidPrincipal = "11111111-2222-3333-4444-555555555555"
    private let uuidSecondaire = "4C4A2E4F-0000-0000-0000-000000000001"

    private func configurationDeuxEcrans() -> AppConfiguration {
        var configuration = AppConfiguration()
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran principal",
                                source: .folder("/Users/moi/Pictures/Fonds animés/Trou noir"),
                                parameters: "fps=30"),
            forUUID: uuidPrincipal)
        configuration.setConfiguration(
            ScreenConfiguration(displayName: "Écran secondaire",
                                source: .folder("/Users/moi/Pictures/Fonds animés/Galaxies")),
            forUUID: uuidSecondaire)
        return configuration
    }

    @Test("Chaque écran connu retrouve sa propre configuration")
    func ecransConnus() {
        let configuration = configurationDeuxEcrans()

        let principal = configuration.configuration(forUUID: uuidPrincipal, displayName: "Écran principal")
        #expect(principal.source == .folder("/Users/moi/Pictures/Fonds animés/Trou noir"))
        #expect(principal.parameters == "fps=30")

        let secondaire = configuration.configuration(forUUID: uuidSecondaire, displayName: "Écran secondaire")
        #expect(secondaire.source == .folder("/Users/moi/Pictures/Fonds animés/Galaxies"))

        #expect(principal.source != secondaire.source, "les écrans ne doivent pas se mélanger")
    }

    @Test("Un écran inconnu reçoit une configuration par défaut")
    func ecranInconnu() {
        let configuration = configurationDeuxEcrans()
        #expect(configuration.isKnown(uuid: "UUID-JAMAIS-VU") == false)

        let inconnu = configuration.configuration(forUUID: "UUID-JAMAIS-VU", displayName: "Écran neuf")
        #expect(inconnu.source == .none)
        #expect(inconnu.parameters == "")
        #expect(inconnu.isEnabled, "un écran inconnu est actif, simplement sans source")
        #expect(inconnu.displayName == "Écran neuf")

        // La simple consultation n'enregistre rien.
        #expect(configuration.screens.count == 2)
    }

    @Test("Le nom d'écran est rafraîchi sans perdre la source")
    func nomRafraichi() {
        let configuration = configurationDeuxEcrans()
        let renomme = configuration.configuration(forUUID: uuidPrincipal, displayName: "Écran principal (bureau)")
        #expect(renomme.displayName == "Écran principal (bureau)")
        #expect(renomme.source == .folder("/Users/moi/Pictures/Fonds animés/Trou noir"))
    }

    @Test("La mise à jour crée l'entrée d'un écran inconnu sans toucher aux autres")
    func miseAJourEcranInconnu() {
        var configuration = configurationDeuxEcrans()
        let resultat = configuration.update(uuid: "UUID-NEUF", displayName: "Écran neuf") { screen in
            screen.source = .url("https://exemple.com")
            screen.parameters = "q=0.7"
        }
        #expect(resultat.source == .url("https://exemple.com"))
        #expect(configuration.screens.count == 3)
        #expect(configuration.isKnown(uuid: "UUID-NEUF"))
        #expect(configuration.screens["UUID-NEUF"]?.displayName == "Écran neuf")
        #expect(configuration.screens[uuidSecondaire]?.source
                == .folder("/Users/moi/Pictures/Fonds animés/Galaxies"))
    }

    @Test("Débranchement puis rebranchement : la configuration est retrouvée")
    func debranchementRebranchement() throws {
        var configuration = configurationDeuxEcrans()
        let avant = configuration.configuration(forUUID: uuidSecondaire, displayName: "Écran secondaire")

        // L'écran disparaît puis revient ; entre-temps la configuration passe par le disque.
        let data = try JSONEncoder().encode(configuration)
        configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        let apres = configuration.configuration(forUUID: uuidSecondaire, displayName: "Écran secondaire")
        #expect(avant == apres)
    }

    @Test("Désactiver un écran n'efface pas sa source")
    func desactivationConserveLaSource() {
        var configuration = configurationDeuxEcrans()
        configuration.update(uuid: uuidPrincipal) { $0.isEnabled = false }
        let apres = configuration.configuration(forUUID: uuidPrincipal)
        #expect(apres.isEnabled == false)
        #expect(apres.source == .folder("/Users/moi/Pictures/Fonds animés/Trou noir"))
    }
}

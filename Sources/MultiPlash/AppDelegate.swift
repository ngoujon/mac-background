import AppKit
import ServiceManagement
import MultiPlashCore

/// Cœur de l'application : gestion des écrans, du menu et des évènements système.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let store = ConfigurationStore()
    private var configuration = AppConfiguration()

    /// Un contrôleur de fenêtre par écran, indexé par UUID d'affichage.
    private var controllers: [String: WallpaperWindowController] = [:]

    private var statusItem: NSStatusItem!
    private var rebuildWorkItem: DispatchWorkItem?

    /// Surveillance de config.json : un fichier modifié à la main (ou par un autre
    /// outil) est appliqué sans relancer l'application.
    private var configurationWatcher: Timer?
    private var lastKnownConfigurationStamp: Date?

    /// Détection des applications en plein écran (complète `occlusionState`).
    private var fullScreenWatcher: Timer?
    /// Dernière application repérée en train de couvrir chaque écran (pour le journal).
    private var lastCoveringApp: [CGDirectDisplayID: String] = [:]

    /// Minuterie d'inactivité qui déclenche l'économiseur d'écran.
    private var idleWatcher: Timer?

    // MARK: - Démarrage

    func applicationDidFinishLaunching(_ notification: Notification) {
        configuration = store.load()
        Log.config.log("Configuration chargée depuis \(self.store.fileURL.path, privacy: .public) : \(self.configuration.screens.count, privacy: .public) écran(s) enregistré(s), pause=\(self.configuration.isPaused, privacy: .public)")
        for (uuid, screenConfiguration) in configuration.screens.sorted(by: { $0.key < $1.key }) {
            Log.config.log("  écran enregistré \(uuid, privacy: .public) « \(screenConfiguration.displayName, privacy: .public) » source=\(screenConfiguration.source.displayDescription, privacy: .public) paramètres=\(screenConfiguration.parameters, privacy: .public) activé=\(screenConfiguration.isEnabled, privacy: .public)")
        }

        setUpStatusItem()
        registerObservers()
        rebuildWindows(reason: "démarrage")
        startWatchingConfigurationFile()
        startWatchingFullScreenCoverage()
        startWatchingUserIdle()
        Log.app.log("MultiPlash démarré (pid \(ProcessInfo.processInfo.processIdentifier, privacy: .public))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers.values { controller.close() }
        Log.app.log("MultiPlash s'arrête")
    }

    // MARK: - Observateurs système

    private func registerObservers() {
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(screenParametersChanged),
                           name: NSApplication.didChangeScreenParametersNotification,
                           object: nil)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemDidWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Verrouillage de session : notifications distribuées publiques.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked),
                                name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked),
                                name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func screenParametersChanged() {
        // Les notifications arrivent en rafale lors d'un branchement : on temporise.
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildWindows(reason: "changement de configuration d'écrans")
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func systemDidWake() {
        Log.power.log("Sortie de veille du Mac")
        rebuildWindows(reason: "sortie de veille")
        setSuspendedAll(false, reason: "sortie de veille")
    }

    @objc private func screensDidSleep() {
        Log.power.log("Écrans en veille")
        setSuspendedAll(true, reason: "écrans en veille")
    }

    @objc private func screensDidWake() {
        Log.power.log("Écrans réveillés")
        setSuspendedAll(false, reason: "écrans réveillés")
    }

    @objc private func screenLocked() {
        Log.power.log("Session verrouillée")
        setSuspendedAll(true, reason: "session verrouillée")
    }

    @objc private func screenUnlocked() {
        Log.power.log("Session déverrouillée")
        setSuspendedAll(false, reason: "session déverrouillée")
    }

    // MARK: - Applications en plein écran

    /// Un fond d'écran recouvert par une application en plein écran ne sert à rien :
    /// `occlusionState` le signale en général, mais pas toujours selon les espaces.
    /// Cette vérification périodique, très peu coûteuse, complète le mécanisme.
    private func startWatchingFullScreenCoverage() {
        updateFullScreenCoverage()
        fullScreenWatcher = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateFullScreenCoverage()
        }
    }

    /// Vérification périodique de l'état réel de chaque écran.
    ///
    /// On ne se fie pas qu'aux notifications : une seule notification manquée
    /// (réveil, déverrouillage, changement d'espace) laisserait un fond suspendu
    /// pour toujours. Ici on relit directement l'état du système, ce qui répare
    /// automatiquement toute désynchronisation.
    private func updateFullScreenCoverage() {
        let covered = displaysCoveredByAnotherWindow()
        let sessionLocked = isSessionLocked()
        // Pendant l'économiseur d'écran, plus personne ne voit les fonds : inutile
        // de faire tourner deux scènes WebGL par-dessus une animation plein écran.
        let screenSaver = isScreenSaverRunning()

        for (identity, _) in currentIdentities() {
            guard let controller = controllers[identity.uuid] else { continue }
            controller.setCoveredByFullScreenWindow(covered.contains(identity.displayID))

            let asleep = CGDisplayIsAsleep(identity.displayID) != 0
            let raison = sessionLocked ? "session verrouillée"
                : (screenSaver ? "économiseur d'écran actif" : "écran en veille")
            controller.setSuspended(sessionLocked || asleep || screenSaver, reason: raison)

            // L'occlusion est relue elle aussi : la notification correspondante
            // peut manquer après une veille ou un changement de bureau.
            controller.refreshOcclusionState()
        }
    }

    // MARK: - Économiseur d'écran

    /// Lance l'économiseur d'écran après un temps d'inactivité réelle.
    ///
    /// macOS refuse de démarrer son économiseur tant qu'une application maintient
    /// l'écran allumé (un lecteur vidéo, un tableau de bord…), et il n'existe aucun
    /// moyen de lever le verrou d'une autre application. On mesure donc nous-mêmes
    /// l'inactivité du clavier et de la souris, et on lance l'économiseur
    /// directement : ce chemin-là ignore complètement ces verrous.
    private func startWatchingUserIdle() {
        idleWatcher = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkUserIdle()
        }
    }

    private func checkUserIdle() {
        let minutes = configuration.screenSaverAfterMinutes
        guard minutes > 0 else { return }
        guard userIdleSeconds() >= Double(minutes) * 60 else { return }
        guard !isScreenSaverRunning(), !isSessionLocked() else { return }
        Log.power.log("Inactivité de \(minutes, privacy: .public) min : lancement de l'économiseur d'écran")
        startScreenSaver()
    }

    /// Secondes écoulées depuis la dernière action au clavier ou à la souris.
    private func userIdleSeconds() -> Double {
        guard let tousEvenements = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                       eventType: tousEvenements)
    }

    private func isScreenSaverRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine"
                || $0.executableURL?.lastPathComponent == "ScreenSaverEngine"
        }
    }

    private func startScreenSaver() {
        let moteur = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: moteur,
                                           configuration: NSWorkspace.OpenConfiguration()) { _, erreur in
            if let erreur {
                Log.power.error("Économiseur d'écran : \(erreur.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Vrai si la session est verrouillée (API publique CoreGraphics).
    private func isSessionLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// Écrans dont toute la surface est couverte par une fenêtre opaque d'une autre
    /// application. Utilise uniquement des API publiques (aucune autorisation requise :
    /// on ne lit que la géométrie des fenêtres, jamais leur titre ni leur contenu).
    private func displaysCoveredByAnotherWindow() -> Set<CGDirectDisplayID> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return [] }

        // Cadres des vraies fenêtres d'application susceptibles de masquer le bureau.
        //
        // Seule la couche 0 est retenue : c'est celle des fenêtres applicatives,
        // y compris en plein écran. Les couches supérieures sont des habillages du
        // système — le Dock, par exemple, possède en permanence une fenêtre de la
        // taille de l'écran (couche 20) qui ne masque rien du tout.
        var frames: [(CGRect, String)] = []
        for info in list {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID { continue }
            guard (info[kCGWindowLayer as String] as? Int ?? -1) == 0 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.95 { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            frames.append((rect, owner))
        }

        // Le repère de CoreGraphics a son origine en haut à gauche de l'écran principal.
        var covered: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let f = screen.frame
            let screenRect = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
                .insetBy(dx: 2, dy: 2)            // tolérance d'un ou deux pixels
            if let (_, owner) = frames.first(where: { $0.0.contains(screenRect) }) {
                covered.insert(displayID)
                if lastCoveringApp[displayID] != owner {
                    lastCoveringApp[displayID] = owner
                    Log.power.log("Écran \"\(screen.localizedName, privacy: .public)\" entièrement recouvert par « \(owner, privacy: .public) »")
                }
            } else {
                lastCoveringApp[displayID] = nil
            }
        }
        return covered
    }

    private func setSuspendedAll(_ suspended: Bool, reason: String) {
        for controller in controllers.values {
            controller.setSuspended(suspended, reason: reason)
        }
    }

    // MARK: - Fenêtres

    /// Crée, met à jour et supprime les fenêtres pour coller aux écrans présents.
    private func rebuildWindows(reason: String) {
        let identities = currentIdentities()
        Log.windows.log("Reconstruction des fenêtres (\(reason, privacy: .public)) : \(identities.count, privacy: .public) écran(s) détecté(s)")

        var seen = Set<String>()
        for (identity, screen) in identities {
            seen.insert(identity.uuid)
            let screenConfiguration = configuration.configuration(forUUID: identity.uuid,
                                                                  displayName: identity.name)
            if !configuration.isKnown(uuid: identity.uuid) {
                Log.config.log("Écran inconnu \"\(identity.name, privacy: .public)\" uuid=\(identity.uuid, privacy: .public) : configuration par défaut appliquée")
            }

            if let controller = controllers[identity.uuid] {
                controller.update(screen: screen, identity: identity)
                controller.apply(configuration: screenConfiguration)
            } else {
                let controller = WallpaperWindowController(identity: identity,
                                                           screen: screen,
                                                           configuration: screenConfiguration)
                controllers[identity.uuid] = controller
                controller.start()
            }
            controllers[identity.uuid]?.setHiddenByUser(configuration.isPaused,
                                                        reason: "pause globale")
        }
        updateFullScreenCoverage()

        // Écrans débranchés : on ferme leurs fenêtres (la configuration est conservée).
        for (uuid, controller) in controllers where !seen.contains(uuid) {
            controller.close()
            controllers.removeValue(forKey: uuid)
            Log.windows.log("Écran débranché uuid=\(uuid, privacy: .public) : fenêtre retirée")
        }
    }

    /// Écrans présents, associés à leur identité.
    private func currentIdentities() -> [(ScreenIdentity, NSScreen)] {
        NSScreen.screens.compactMap { screen in
            guard let identity = screen.identity else { return nil }
            return (identity, screen)
        }
    }

    // MARK: - Persistance

    /// Date de dernière modification de config.json (nil si absent).
    private func configurationFileStamp() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
    }

    /// Applique automatiquement un config.json modifié en dehors de l'application.
    private func startWatchingConfigurationFile() {
        lastKnownConfigurationStamp = configurationFileStamp()
        configurationWatcher = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let stamp = self.configurationFileStamp()
            guard stamp != self.lastKnownConfigurationStamp else { return }
            self.lastKnownConfigurationStamp = stamp
            self.configuration = self.store.load()
            Log.config.log("config.json modifié à l'extérieur : configuration rechargée")
            self.rebuildWindows(reason: "config.json modifié")
            // On remesure le débit pour voir l'effet du nouveau réglage.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.controllers.values.forEach { $0.measureFrameRate() }
            }
        }
    }

    private func saveConfiguration() {
        do {
            try store.save(configuration)
            lastKnownConfigurationStamp = configurationFileStamp()
            Log.config.log("Configuration enregistrée (\(self.configuration.screens.count, privacy: .public) écran(s))")
        } catch {
            Log.config.error("Échec d'enregistrement : \(error.localizedDescription, privacy: .public)")
            presentError("Impossible d'enregistrer la configuration", detail: error.localizedDescription)
        }
    }

    /// Modifie les réglages d'un écran, enregistre et applique immédiatement.
    private func mutateScreen(_ uuid: String, _ body: (inout ScreenConfiguration) -> Void) {
        let identity = currentIdentities().first { $0.0.uuid == uuid }?.0
        let updated = configuration.update(uuid: uuid, displayName: identity?.name ?? "", body)
        saveConfiguration()
        controllers[uuid]?.apply(configuration: updated)
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "MultiPlash")
            button.image?.isTemplate = true
            button.toolTip = "MultiPlash"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "MultiPlash", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        for (identity, _) in currentIdentities() {
            let screenConfiguration = configuration.configuration(forUUID: identity.uuid,
                                                                  displayName: identity.name)
            let label = identity.isMain ? "\(identity.name) (principal)" : identity.name
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            let state = NSMenuItem(title: "Source : \(screenConfiguration.source.displayDescription)",
                                   action: nil, keyEquivalent: "")
            state.isEnabled = false
            submenu.addItem(state)
            if !screenConfiguration.parameters.isEmpty {
                let parameters = NSMenuItem(title: "Paramètres : \(screenConfiguration.parameters)",
                                            action: nil, keyEquivalent: "")
                parameters.isEnabled = false
                submenu.addItem(parameters)
            }
            submenu.addItem(.separator())

            submenu.addItem(makeItem("Choisir un dossier local…", #selector(chooseFolder(_:)), identity.uuid))
            submenu.addItem(makeItem("Saisir une URL…", #selector(enterURL(_:)), identity.uuid))
            submenu.addItem(makeItem("Paramètres…", #selector(editParameters(_:)), identity.uuid))
            submenu.addItem(makeItem("Recharger", #selector(reloadScreen(_:)), identity.uuid))
            submenu.addItem(makeItem(screenConfiguration.isEnabled ? "Désactiver" : "Activer",
                                     #selector(toggleScreen(_:)), identity.uuid))

            item.submenu = submenu
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pause = NSMenuItem(title: configuration.isPaused ? "Reprendre" : "Tout mettre en pause",
                               action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let launch = NSMenuItem(title: "Lancer au démarrage",
                                action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launch.target = self
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launch)

        let saver = NSMenuItem(title: "Lancer l'économiseur d'écran",
                               action: #selector(launchScreenSaver(_:)), keyEquivalent: "")
        saver.target = self
        menu.addItem(saver)

        let delais = NSMenuItem(title: "Économiseur après inactivité", action: nil, keyEquivalent: "")
        let sousMenu = NSMenu()
        for minutes in [0, 1, 2, 5, 10, 20] {
            let titre = minutes == 0 ? "Jamais" : "\(minutes) min"
            let item = NSMenuItem(title: titre, action: #selector(setScreenSaverDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = (configuration.screenSaverAfterMinutes == minutes) ? .on : .off
            sousMenu.addItem(item)
        }
        delais.submenu = sousMenu
        menu.addItem(delais)

        let measure = NSMenuItem(title: "Mesurer les images/s",
                                 action: #selector(measureFrameRates(_:)), keyEquivalent: "")
        measure.target = self
        measure.toolTip = "Résultat dans la Console : log show --predicate 'subsystem == \"MultiPlash\"'"
        menu.addItem(measure)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector, _ uuid: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = uuid
        return item
    }

    // MARK: - Actions par écran

    @objc private func chooseFolder(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Choisir un dossier de fond d'écran"
        panel.message = "Le dossier doit contenir un fichier index.html."
        panel.prompt = "Choisir"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !SourceResolver.folderContainsIndex(url.path) {
            presentError("Aucun index.html dans ce dossier",
                         detail: "MultiPlash charge « index.html » à la racine du dossier choisi.")
            return
        }
        mutateScreen(uuid) { screenConfiguration in
            screenConfiguration.source = .folder(url.path)
            screenConfiguration.isEnabled = true
        }
        Log.config.log("Écran uuid=\(uuid, privacy: .public) : dossier \(url.path, privacy: .public)")
    }

    @objc private func enterURL(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        let current = configuration.configuration(forUUID: uuid)
        let initial: String
        if case .url(let value) = current.source { initial = value } else { initial = "" }

        guard let text = promptForText(title: "Adresse à afficher",
                                       message: "Exemple : https://exemple.com/fond",
                                       initial: initial) else { return }
        mutateScreen(uuid) { screenConfiguration in
            screenConfiguration.source = text.isEmpty ? .none : .url(text)
            screenConfiguration.isEnabled = true
        }
        Log.config.log("Écran uuid=\(uuid, privacy: .public) : URL \(text, privacy: .public)")
    }

    @objc private func editParameters(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        let current = configuration.configuration(forUUID: uuid)
        guard let text = promptForText(title: "Paramètres de la page",
                                       message: "Ajoutés en query string, par exemple : fps=30&q=0.7",
                                       initial: current.parameters) else { return }
        mutateScreen(uuid) { screenConfiguration in
            screenConfiguration.parameters = SourceResolver.normalizedParameters(text)
        }
        Log.config.log("Écran uuid=\(uuid, privacy: .public) : paramètres « \(text, privacy: .public) »")
    }

    @objc private func reloadScreen(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        controllers[uuid]?.reload()
        Log.web.log("Rechargement demandé pour l'écran uuid=\(uuid, privacy: .public)")
    }

    @objc private func toggleScreen(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        mutateScreen(uuid) { screenConfiguration in
            screenConfiguration.isEnabled.toggle()
        }
    }

    // MARK: - Actions globales

    @objc private func togglePause(_ sender: NSMenuItem) {
        configuration.isPaused.toggle()
        saveConfiguration()
        for controller in controllers.values {
            controller.setHiddenByUser(configuration.isPaused, reason: "pause globale")
        }
        Log.app.log("Pause globale : \(self.configuration.isPaused, privacy: .public)")
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                Log.app.log("Lancement au démarrage désactivé")
            } else {
                try service.register()
                Log.app.log("Lancement au démarrage activé")
            }
        } catch {
            Log.app.error("Lancement au démarrage : \(error.localizedDescription, privacy: .public)")
            presentError("Impossible de modifier le lancement au démarrage",
                         detail: error.localizedDescription)
        }
    }

    @objc private func launchScreenSaver(_ sender: NSMenuItem) {
        Log.power.log("Économiseur d'écran lancé depuis le menu")
        startScreenSaver()
    }

    @objc private func setScreenSaverDelay(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        configuration.screenSaverAfterMinutes = minutes
        saveConfiguration()
        Log.power.log("Économiseur après inactivité : \(minutes, privacy: .public) min")
    }

    @objc private func measureFrameRates(_ sender: NSMenuItem) {
        Log.web.log("Mesure des images/s demandée")
        for controller in controllers.values { controller.measureFrameRate() }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - Petites boîtes de dialogue

    private func promptForText(title: String, message: String, initial: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Valider")
        alert.addButton(withTitle: "Annuler")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentError(_ title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

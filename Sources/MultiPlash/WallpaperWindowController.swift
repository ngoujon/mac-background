import AppKit
import WebKit
import MultiPlashCore

/// Paliers d'économie d'énergie appliqués quand le fond n'est plus visible.
///
/// L'idée : plus l'écran reste caché longtemps, plus on rend de ressources au système.
enum PowerLevel: Int, Comparable {
    /// Fond visible : animation normale.
    case active = 0
    /// Page masquée : `document.visibilityState == "hidden"`, requestAnimationFrame
    /// s'arrête, le GPU ne travaille plus. Le contexte WebGL reste chargé.
    case animationStopped = 1
    /// Page déchargée : le contexte WebGL et les textures sont libérés.
    /// La vue web existe toujours, prête à recharger.
    case pageUnloaded = 2
    /// Vue web détruite : le processus de rendu WebKit est libéré (plusieurs
    /// centaines de Mo). Tout est recréé à la réapparition.
    case webViewReleased = 3

    static func < (a: PowerLevel, b: PowerLevel) -> Bool { a.rawValue < b.rawValue }

    var description: String {
        switch self {
        case .active: return "actif"
        case .animationStopped: return "animation arrêtée"
        case .pageUnloaded: return "page déchargée"
        case .webViewReleased: return "vue web libérée"
        }
    }
}

/// Gère une fenêtre de fond d'écran et son WKWebView, pour un écran donné.
final class WallpaperWindowController: NSObject, WKNavigationDelegate {

    // MARK: - Réglages d'économie d'énergie

    /// Délai avant de décharger la page quand le fond reste caché.
    static var pageUnloadDelay: TimeInterval = 180      // 3 minutes
    /// Délai avant de détruire complètement la vue web.
    static var webViewReleaseDelay: TimeInterval = 900  // 15 minutes

    // MARK: - État

    let uuid: String
    private(set) var screenName: String
    private(set) var configuration: ScreenConfiguration

    let window: WallpaperWindow
    /// Vue web courante : nil quand elle a été libérée pour économiser l'énergie.
    private(set) var webView: WKWebView?

    /// Raisons indépendantes de masquer le fond. Le fond est suspendu dès que
    /// l'une d'elles est vraie ; on les garde séparées pour éviter tout va-et-vient.
    private var hiddenByOcclusion = false      // fenêtre recouverte (occlusionState)
    private var hiddenByFullScreen = false     // une fenêtre couvre tout l'écran
    private var hiddenBySystem = false         // écrans en veille, session verrouillée

    /// Masquage complet demandé par l'utilisateur (pause globale, écran désactivé).
    private(set) var isHiddenByUser = false

    /// Vrai si le fond est en économie d'énergie, quelle qu'en soit la raison.
    var isSuspended: Bool { hiddenByOcclusion || hiddenByFullScreen || hiddenBySystem }

    private(set) var powerLevel: PowerLevel = .active
    private var escalationTimer: Timer?

    /// Dernière destination chargée, pour éviter les rechargements inutiles.
    private var loadedDestination: LoadDestination?

    init(identity: ScreenIdentity, screen: NSScreen, configuration: ScreenConfiguration) {
        self.uuid = identity.uuid
        self.screenName = identity.name
        self.configuration = configuration
        window = WallpaperWindow(screenFrame: screen.frame)

        super.init()

        makeWebView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window)

        Log.windows.log("Fenêtre créée pour l'écran \"\(identity.name, privacy: .public)\" uuid=\(self.uuid, privacy: .public) cadre=\(NSStringFromRect(screen.frame), privacy: .public) principal=\(identity.isMain, privacy: .public)")
    }

    deinit {
        escalationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Vue web

    /// Crée (ou recrée) la vue web et l'installe dans la fenêtre.
    private func makeWebView() {
        let size = window.frame.size

        // JavaScript actif, lecture automatique des médias, WebGL par défaut.
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        webConfiguration.suppressesIncrementalRendering = false

        let view = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: webConfiguration)
        view.autoresizingMask = [.width, .height]
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        view.underPageBackgroundColor = .black
        view.navigationDelegate = self

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(view)
        window.contentView = content

        webView = view
    }

    /// Détruit la vue web : WebKit libère son processus de rendu et sa mémoire.
    private func releaseWebView() {
        guard let view = webView else { return }
        view.stopLoading()
        view.navigationDelegate = nil
        view.removeFromSuperview()
        webView = nil
        loadedDestination = nil

        // Une vue noire prend la place : la fenêtre reste opaque, sans rien afficher.
        let content = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = content
    }

    // MARK: - Cycle de vie

    /// Affiche la fenêtre et charge la source.
    func start() {
        applyVisibility()
        reloadIfNeeded(force: true)
    }

    func close() {
        escalationTimer?.invalidate()
        webView?.stopLoading()
        webView = nil
        window.orderOut(nil)
        window.close()
        Log.windows.log("Fenêtre fermée pour l'écran \"\(self.screenName, privacy: .public)\" uuid=\(self.uuid, privacy: .public)")
    }

    /// Repositionne la fenêtre (déplacement d'écran, changement de résolution).
    func update(screen: NSScreen, identity: ScreenIdentity) {
        screenName = identity.name
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
            webView?.frame = NSRect(origin: .zero, size: screen.frame.size)
            Log.windows.log("Fenêtre repositionnée pour l'écran \"\(identity.name, privacy: .public)\" cadre=\(NSStringFromRect(screen.frame), privacy: .public)")
        }
        applyVisibility()
    }

    /// Applique de nouveaux réglages (source, paramètres, activation).
    func apply(configuration newValue: ScreenConfiguration) {
        let previous = configuration
        configuration = newValue
        // Réactiver un écran doit aussi remonter du palier d'économie d'énergie.
        updatePowerLevel(reason: "réglages modifiés")
        applyVisibility()
        if previous.source != newValue.source
            || previous.parameters != newValue.parameters
            || previous.isEnabled != newValue.isEnabled {
            reloadIfNeeded(force: true)
        }
    }

    /// Recharge la page courante.
    func reload() {
        loadedDestination = nil
        reloadIfNeeded(force: true)
    }

    // MARK: - Chargement

    private func reloadIfNeeded(force: Bool) {
        guard configuration.isEnabled, !isHiddenByUser else { return }
        // Inutile de charger quoi que ce soit tant que le fond est caché :
        // il sera chargé au retour à l'écran.
        guard powerLevel < .pageUnloaded else { return }
        if webView == nil { makeWebView() }
        guard let webView else { return }

        guard let destination = SourceResolver.destination(for: configuration) else {
            webView.loadHTMLString("<html><body style=\"background:#000\"></body></html>", baseURL: nil)
            loadedDestination = nil
            return
        }
        if !force, destination == loadedDestination { return }
        loadedDestination = destination

        switch destination {
        case .remote(let url):
            Log.web.log("Chargement distant écran \"\(self.screenName, privacy: .public)\" : \(url.absoluteString, privacy: .public)")
            webView.load(URLRequest(url: url))

        case .local(let index, let readAccess):
            guard FileManager.default.isReadableFile(atPath: index.path) else {
                Log.web.error("index.html introuvable pour l'écran \"\(self.screenName, privacy: .public)\" : \(index.path, privacy: .public)")
                webView.loadHTMLString("<html><body style=\"background:#000\"></body></html>", baseURL: nil)
                return
            }
            Log.web.log("Chargement local écran \"\(self.screenName, privacy: .public)\" : \(index.absoluteString, privacy: .public) (accès dossier \(readAccess.path, privacy: .public))")
            webView.loadFileURL(index, allowingReadAccessTo: readAccess)
        }
    }

    // MARK: - Visibilité et économie d'énergie

    /// Masque ou affiche complètement la fenêtre (pause globale, écran désactivé).
    func setHiddenByUser(_ hidden: Bool, reason: String) {
        guard hidden != isHiddenByUser else { return }
        isHiddenByUser = hidden
        Log.power.log("Écran \"\(self.screenName, privacy: .public)\" : \(hidden ? "fenêtre masquée" : "fenêtre réaffichée", privacy: .public) (\(reason, privacy: .public))")
        updatePowerLevel(reason: reason)
        applyVisibility()
        if !hidden { reloadIfNeeded(force: false) }
    }

    /// La fenêtre est recouverte par d'autres fenêtres (occlusionState d'AppKit).
    func setOccluded(_ occluded: Bool) {
        guard occluded != hiddenByOcclusion else { return }
        hiddenByOcclusion = occluded
        updatePowerLevel(reason: occluded ? "fenêtre recouverte" : "fenêtre de nouveau visible")
    }

    /// Une fenêtre (application en plein écran, fenêtre maximisée…) couvre tout l'écran.
    func setCoveredByFullScreenWindow(_ covered: Bool) {
        guard covered != hiddenByFullScreen else { return }
        hiddenByFullScreen = covered
        updatePowerLevel(reason: covered ? "écran entièrement recouvert (plein écran)" : "écran de nouveau dégagé")
    }

    /// Écrans en veille, session verrouillée, Mac en veille.
    func setSuspended(_ suspended: Bool, reason: String) {
        guard suspended != hiddenBySystem else { return }
        hiddenBySystem = suspended
        updatePowerLevel(reason: reason)
    }

    /// Décide du palier d'économie d'énergie et programme les paliers suivants.
    private func updatePowerLevel(reason: String) {
        escalationTimer?.invalidate()
        escalationTimer = nil

        if isSuspended || isHiddenByUser || !configuration.isEnabled {
            // Premier palier immédiat : on arrête l'animation.
            if powerLevel < .animationStopped {
                setPowerLevel(.animationStopped, reason: reason)
            }
            scheduleEscalation()
        } else if powerLevel != .active {
            setPowerLevel(.active, reason: reason)
        }
    }

    /// Programme le passage au palier suivant si le fond reste caché.
    private func scheduleEscalation() {
        let delay: TimeInterval
        let next: PowerLevel
        switch powerLevel {
        case .animationStopped:
            delay = Self.pageUnloadDelay
            next = .pageUnloaded
        case .pageUnloaded:
            delay = Self.webViewReleaseDelay - Self.pageUnloadDelay
            next = .webViewReleased
        default:
            return
        }
        escalationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isSuspended || self.isHiddenByUser || !self.configuration.isEnabled else { return }
            self.setPowerLevel(next, reason: "fond caché depuis longtemps")
            self.scheduleEscalation()
        }
    }

    /// Applique concrètement un palier.
    private func setPowerLevel(_ level: PowerLevel, reason: String) {
        guard level != powerLevel else { return }
        let previous = powerLevel
        powerLevel = level
        Log.power.log("Écran \"\(self.screenName, privacy: .public)\" : \(previous.description, privacy: .public) → \(level.description, privacy: .public) (\(reason, privacy: .public))")

        switch level {
        case .active:
            if webView == nil { makeWebView() }
            applyVisibility()
            // La page a pu être déchargée : on la recharge avant de réafficher.
            reloadIfNeeded(force: previous >= .pageUnloaded)
            logPageState(prefix: "après reprise")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.measureFrameRate()
            }

        case .animationStopped:
            applyVisibility()

        case .pageUnloaded:
            // Libère le contexte WebGL, les textures et la mémoire de la page.
            webView?.stopLoading()
            webView?.loadHTMLString("<html><body style=\"background:#000\"></body></html>", baseURL: nil)
            loadedDestination = nil
            applyVisibility()

        case .webViewReleased:
            releaseWebView()
        }
    }

    private func applyVisibility() {
        let shouldShowWindow = configuration.isEnabled && !isHiddenByUser
        if shouldShowWindow {
            if !window.isVisible { window.orderFrontRegardless() }
        } else {
            if window.isVisible { window.orderOut(nil) }
        }
        // Masquer la NSView suffit à faire passer la page en arrière-plan côté WebKit :
        // requestAnimationFrame s'arrête et document.visibilityState devient "hidden".
        let contenuVisible = powerLevel == .active && shouldShowWindow
        webView?.isHidden = !contenuVisible

        // Sans contenu, la fenêtre s'efface au lieu de rester un rectangle noir :
        // si une suspension se déclenche à tort, on voit le fond d'écran du système
        // plutôt qu'un écran éteint.
        window.isOpaque = contenuVisible
        window.backgroundColor = contenuVisible ? .black : .clear
        window.contentView?.layer?.backgroundColor = contenuVisible
            ? NSColor.black.cgColor : NSColor.clear.cgColor
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        let visible = window.occlusionState.contains(.visible)
        Log.power.log("Écran \"\(self.screenName, privacy: .public)\" : occlusionState=\(visible ? "visible" : "masqué", privacy: .public)")
        setOccluded(!visible)
    }

    /// Relit l'occlusion réelle de la fenêtre, sans attendre de notification.
    func refreshOcclusionState() {
        guard window.isVisible else { return }
        setOccluded(!window.occlusionState.contains(.visible))
    }

    // MARK: - Diagnostic

    /// Mesure les images par seconde réellement atteintes par la page et les journalise.
    func measureFrameRate(duration: Double = 2.0) {
        guard configuration.isEnabled, !isHiddenByUser, powerLevel == .active, let webView else { return }
        let script = """
        let images = 0;
        const debut = performance.now();
        await new Promise(fini => {
          const pas = () => {
            images++;
            (performance.now() - debut < duree) ? requestAnimationFrame(pas) : fini();
          };
          requestAnimationFrame(pas);
        });
        const toile = document.querySelector('canvas');
        return [
          Math.round(images * 1000 / (performance.now() - debut)),
          toile ? toile.width + 'x' + toile.height : 'pas de canvas',
          'fenêtre ' + innerWidth + 'x' + innerHeight,
          'dpr ' + devicePixelRatio
        ].join(' | ');
        """
        webView.callAsyncJavaScript(script,
                                    arguments: ["duree": duration * 1000],
                                    in: nil,
                                    in: .page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let texte = (value as? String) ?? "?"
                Log.web.log("Écran \"\(self.screenName, privacy: .public)\" : \(texte, privacy: .public) images/s")
            case .failure(let error):
                Log.web.error("Mesure des images/s impossible sur \"\(self.screenName, privacy: .public)\" : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Journalise l'état vu par la page (query string et visibilité), utile au diagnostic.
    func logPageState(prefix: String) {
        guard let webView else { return }
        webView.evaluateJavaScript("[location.search, document.visibilityState].join(' | ')") { [weak self] result, _ in
            guard let self else { return }
            let text = (result as? String) ?? "?"
            Log.web.log("Écran \"\(self.screenName, privacy: .public)\" \(prefix, privacy: .public) : \(text, privacy: .public)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.web.log("Page chargée sur l'écran \"\(self.screenName, privacy: .public)\"")
        logPageState(prefix: "état page")
        // Mesure automatique une fois l'animation lancée (le temps que la page se stabilise).
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.measureFrameRate()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.web.error("Échec de chargement sur \"\(self.screenName, privacy: .public)\" : \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.web.error("Échec de chargement (provisoire) sur \"\(self.screenName, privacy: .public)\" : \(error.localizedDescription, privacy: .public)")
    }
}

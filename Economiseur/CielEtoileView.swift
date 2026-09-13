import ScreenSaver
import QuartzCore
import os

/// Couche des éléments animés (étoiles scintillantes, planètes, Lune, satellites,
/// étoiles filantes). Le fond étoilé, lui, est une couche séparée que le GPU fait
/// tourner : c'est ce qui évite de rééchantillonner une énorme image en CPU.
private final class CoucheElements: CALayer {
    weak var scene: CielScene?
    override func draw(in ctx: CGContext) {
        scene?.dessinerElements(dans: ctx, temps: Date().timeIntervalSince1970)
    }
}

/// Économiseur d'écran « Ciel étoilé ».
///
/// macOS affiche l'économiseur sur l'écran de verrouillage : c'est le seul moyen
/// supporté d'y faire tourner une animation. Le rendu est natif (Core Graphics) :
/// un WKWebView ne fonctionne pas ici, macOS hébergeant la vue à distance, WebKit
/// considère la page comme masquée et ne la peint jamais.
@objc(CielEtoileView)
final class CielEtoileView: ScreenSaverView {

    private var scene: CielScene?
    private var coucheCiel: CALayer?
    private var coucheElements: CoucheElements?
    private var couchesAstres: [CALayer] = []
    private let journal = Logger(subsystem: "MultiPlash", category: "economiseur")

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        preparer(apercu: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        preparer(apercu: false)
    }

    private func preparer(apercu: Bool) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0
        journal.log("Économiseur créé (aperçu=\(apercu, privacy: .public)) \(NSStringFromRect(self.bounds), privacy: .public)")
    }

    /// La scène dépend de la taille : on la construit au premier dessin utile.
    private func sceneCourante() -> CielScene? {
        if let scene { return scene }
        guard bounds.width > 10, bounds.height > 10 else { return nil }
        let debut = Date()
        let nouvelle = CielScene(taille: bounds.size)
        scene = nouvelle
        installerCouches(nouvelle)
        journal.log("Scène construite en \(Int(Date().timeIntervalSince(debut) * 1000), privacy: .public) ms pour \(NSStringFromSize(self.bounds.size), privacy: .public)")
        return nouvelle
    }

    /// Deux couches : le fond étoilé (tourné par le GPU) et les éléments animés.
    private func installerCouches(_ scene: CielScene) {
        coucheCiel?.removeFromSuperlayer()
        coucheElements?.removeFromSuperlayer()

        let echelle = window?.backingScaleFactor ?? 1

        // Le calque de la vue doit être opaque : sans lui, l'économiseur laisse
        // voir le fond d'écran à travers. (Le réglage fait dans l'initialiseur ne
        // suffit pas, le calque n'existe pas encore à ce moment-là.)
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.isOpaque = true

        let fond = CALayer()
        fond.backgroundColor = NSColor.black.cgColor   // filet de sécurité
        fond.contents = scene.imageCiel
        journal.log("fond étoilé : \(scene.imageCiel != nil ? "image prête" : "IMAGE ABSENTE", privacy: .public)")
        fond.bounds = CGRect(x: 0, y: 0, width: scene.rayon * 2, height: scene.rayon * 2)
        fond.position = scene.centre
        fond.contentsGravity = .resize
        fond.isGeometryFlipped = false
        layer?.addSublayer(fond)
        coucheCiel = fond

        // Étoiles scintillantes, satellites et étoiles filantes : un seul calque,
        // redessiné à chaque image mais en demi-résolution — ce sont des halos flous,
        // la finesse n'y change rien et cela divise par quatre le travail du processeur.
        let elements = CoucheElements()
        elements.scene = scene
        elements.frame = bounds
        elements.contentsScale = echelle * 0.4
        elements.isOpaque = false
        layer?.addSublayer(elements)
        coucheElements = elements

        // Lune et planètes : un calque chacun, simplement déplacé à chaque image.
        // Ils gardent leur pleine définition sans rien coûter au processeur.
        couchesAstres.forEach { $0.removeFromSuperlayer() }
        couchesAstres = scene.astres(temps: Date().timeIntervalSince1970).map { astre in
            let couche = CALayer()
            couche.contents = astre.image
            couche.bounds = CGRect(x: 0, y: 0,
                                   width: CGFloat(astre.image.width), height: CGFloat(astre.image.height))
            couche.position = astre.centre
            couche.contentsScale = echelle
            layer?.addSublayer(couche)
            return couche
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changement = newSize != frame.size
        super.setFrameSize(newSize)
        if changement { scene = nil }        // reconstruite à la nouvelle taille
    }

    override func startAnimation() {
        super.startAnimation()
        journal.log("startAnimation")
        _ = sceneCourante()
    }

    override func stopAnimation() {
        super.stopAnimation()
        journal.log("stopAnimation")
    }

    override func animateOneFrame() {
        guard let scene else { return }
        let T = Date().timeIntervalSince1970
        // Le fond : une simple transformation de couche, exécutée par le GPU.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        coucheCiel?.position = scene.polePosition(temps: T)
        coucheCiel?.setAffineTransform(CGAffineTransform(rotationAngle: scene.angle(temps: T)))
        let astres = scene.astres(temps: T)
        for (couche, astre) in zip(couchesAstres, astres) {
            couche.isHidden = !astre.visible
            if astre.visible { couche.position = astre.centre }
        }
        CATransaction.commit()
        // Les éléments animés, eux, sont redessinés — mais ce ne sont que des sprites.
        coucheElements?.setNeedsDisplay()
    }

    private var images = 0
    private var derniereTrace = Date.distantPast

    override func draw(_ rect: NSRect) {
        images += 1
        if Date().timeIntervalSince(derniereTrace) > 1 {
            derniereTrace = Date()
            journal.log("draw #\(self.images, privacy: .public) rect=\(NSStringFromRect(rect), privacy: .public) fenêtre=\(self.window != nil, privacy: .public) calque=\(self.layer != nil, privacy: .public) contexte=\(NSGraphicsContext.current != nil, privacy: .public)")
        }
        _ = sceneCourante()           // construit la scène et ses couches au besoin
        NSColor.black.setFill()
        rect.fill()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}

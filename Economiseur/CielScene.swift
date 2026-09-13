import AppKit
import CoreGraphics

/// Scène du ciel étoilé, dessinée nativement en Core Graphics.
///
/// C'est le portage de la page web `Fonds/Ciel étoilé/index.html` : un économiseur
/// d'écran ne peut pas afficher de WKWebView (macOS héberge sa vue à distance et
/// WebKit considère la page comme masquée, donc ne la peint jamais).
/// Les réglages et les rythmes sont identiques à ceux de la page.
final class CielScene {

    // Rythmes (identiques à la page web)
    var minutesParTour: Double = 5        // un tour complet du ciel
    var minutesDeriveLune: Double = 22    // dérive de la Lune parmi les étoiles
    var secondesEntreMeteores: Double = 4
    var nombreEtoiles = 2200              // pour une surface de 2560×1440
    var nombreScintillantes = 320
    var nombreSatellites = 3

    private let taille: CGSize
    private let pole: CGPoint
    private let rayonCiel: CGFloat        // du pôle au coin le plus éloigné
    private let amplitudeDerive: CGFloat

    private var ciel: CGImage?            // fond + voie lactée + étoiles fixes
    private var lune: CGImage?
    private var planetes: [(image: CGImage, distance: CGFloat, ecart: CGFloat, minutes: Double)] = []
    private var scintillantes: [Etoile] = []
    private var satellites: [Satellite] = []
    private var meteores: [Meteore] = []
    private var prochainMeteore: Double = 2
    private var dernierTemps: Double = 0

    private var alea = Alea(graine: 7)

    // Exposés à la vue : le fond est confié à une couche Core Animation, que le
    // GPU fait tourner. Le processeur n'a plus à rééchantillonner une image de
    // plus de 3000 px de côté à chaque image.
    var imageCiel: CGImage? { ciel }
    var rayon: CGFloat { rayonCiel }
    var centre: CGPoint { pole }

    /// Angle de rotation du ciel à un instant donné.
    func angle(temps T: Double) -> CGFloat { CGFloat(T / (minutesParTour * 60)) * .pi * 2 }

    /// Images et positions des astres à un instant donné, pour les porter
    /// en calques Core Animation plutôt que de les redessiner.
    struct Astre { let image: CGImage; let centre: CGPoint; let visible: Bool }

    func astres(temps T: Double) -> [Astre] {
        let angleCiel = angle(temps: T)
        let p = polePosition(temps: T)
        let c = cos(angleCiel), s = sin(angleCiel)
        func versEcran(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: p.x + dx * c - dy * s, y: p.y + dx * s + dy * c)
        }
        var liste: [Astre] = []
        for pl in planetes {
            let a = 0.55 + CGFloat(T / (pl.minutes * 60)) * .pi * 2
            let dx = cos(a) * pl.distance - sin(a) * pl.ecart
            let dy = sin(a) * pl.distance + cos(a) * pl.ecart
            let point = versEcran(dx, dy)
            let demi = CGFloat(pl.image.width) / 2
            let visible = point.x > -demi && point.y > -demi
                && point.x < taille.width + demi && point.y < taille.height + demi
            liste.append(Astre(image: pl.image, centre: point, visible: visible))
        }
        if let lune {
            let a = CGFloat(T / (minutesDeriveLune * 60)) * .pi * 2
            let point = versEcran(cos(a) * rayonCiel * 0.55, sin(a) * rayonCiel * 0.55)
            let demi = CGFloat(lune.width) / 2
            let visible = point.x > -demi && point.y > -demi
                && point.x < taille.width + demi && point.y < taille.height + demi
            liste.append(Astre(image: lune, centre: point, visible: visible))
        }
        return liste
    }

    /// Position du pôle, dérive comprise.
    func polePosition(temps T: Double) -> CGPoint {
        CGPoint(x: pole.x + amplitudeDerive * CGFloat(sin(T / 41)),
                y: pole.y + amplitudeDerive * 0.75 * CGFloat(cos(T / 59)))
    }

    /// Une étoile pré-dessinée par teinte : redimensionner une image est bien plus
    /// rapide que de recalculer un dégradé radial à chaque étoile et à chaque image.
    private var sprites: [CGImage] = []
    private let teintes: [(CGFloat, CGFloat, CGFloat)] = [
        (0.96, 0.97, 1.00),   // blanche
        (0.74, 0.80, 1.00),   // bleutée
        (1.00, 0.89, 0.77),   // dorée
        (1.00, 0.77, 0.66),   // orangée
    ]

    private struct Etoile {
        var x, y: CGFloat                 // relatives au pôle
        var taille: CGFloat
        var teinte: Int
        var phase, vitesse, creux: Double
    }
    private struct Satellite {
        var x, y, vx, vy: CGFloat
        var eclat, rythme, phase, age, duree: Double
        var flare: Double
    }
    private struct Meteore {
        var x, y, vx, vy: CGFloat
        var vie, duree: Double
        var epaisseur: CGFloat
        var couleur: (CGFloat, CGFloat, CGFloat)
    }

    /// Générateur reproductible (xorshift), pour retrouver le même ciel.
    private struct Alea {
        var etat: UInt32
        init(graine: UInt32) { etat = graine == 0 ? 1 : graine }
        mutating func suivant() -> Double {
            etat ^= etat << 13; etat ^= etat >> 17; etat ^= etat << 5
            return Double(etat % 100_000) / 100_000
        }
        mutating func entre(_ a: Double, _ b: Double) -> Double { a + suivant() * (b - a) }
        mutating func entre(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat(entre(Double(a), Double(b))) }
    }

    init(taille: CGSize) {
        self.taille = taille
        // Repère Core Graphics : l'origine est en bas à gauche.
        let centreRotation = CGPoint(x: taille.width * 0.5, y: taille.height * 0.65)
        pole = centreRotation
        let derive = min(taille.width, taille.height) * 0.12
        amplitudeDerive = derive
        let coins = [CGPoint(x: 0, y: 0), CGPoint(x: taille.width, y: 0),
                     CGPoint(x: 0, y: taille.height), CGPoint(x: taille.width, y: taille.height)]
        rayonCiel = coins.map { hypot($0.x - centreRotation.x, $0.y - centreRotation.y) }.max()! + derive + 4
        construire()
    }

    // MARK: - Construction (une seule fois)

    private func construire() {
        construireSprites()
        let cote = Int(ceil(rayonCiel * 2))
        ciel = imageBitmap(largeur: cote, hauteur: cote, opaque: true) { ctx in
            self.dessinerFondEtoile(ctx, cote: CGFloat(cote))
        }

        let rayonLune = max(26, min(taille.width, taille.height) * 0.052)
        lune = construireLune(rayon: rayonLune)

        // Les sept planètes, toutes plus petites que la Lune, le long de l'écliptique.
        let modeles: [(String, CGFloat, CGFloat, Double)] = [
            ("mercure", 0.11, -0.74, 30), ("venus", 0.20, 0.30, 37), ("mars", 0.16, -0.42, 46),
            ("jupiter", 0.46, 0.62, 60), ("saturne", 0.38, -0.18, 74),
            ("uranus", 0.22, 0.86, 91), ("neptune", 0.21, -0.94, 109),
        ]
        for (nom, part, distance, minutes) in modeles {
            let rayon = max(3, rayonLune * part)
            if let image = construirePlanete(nom: nom, rayon: rayon) {
                planetes.append((image, rayonCiel * distance, alea.entre(-0.06, 0.06) * rayonCiel, minutes))
            }
        }

        for _ in 0..<Int(Double(nombreScintillantes) * surfaceRelative()) {
            let (x, y) = positionCiel()
            scintillantes.append(Etoile(x: x - rayonCiel, y: y - rayonCiel,
                                        taille: magnitude() * alea.entre(1.0, 1.6),
                                        teinte: teinte(),
                                        phase: alea.entre(0, 6.2832),
                                        vitesse: alea.entre(1.3, 4.2),
                                        creux: alea.entre(0.35, 0.8)))
        }
        for _ in 0..<nombreSatellites { satellites.append(nouveauSatellite(etale: true)) }
    }

    private func construireSprites() {
        let cote = 64
        sprites = teintes.compactMap { couleur in
            imageBitmap(largeur: cote, hauteur: cote, opaque: false) { ctx in
                let c = CGPoint(x: CGFloat(cote) / 2, y: CGFloat(cote) / 2)
                self.halo(ctx, centre: c, rayon: CGFloat(cote) / 2, couleur: couleur, alpha: 0.95)
            }
        }
    }

    private func surfaceRelative() -> Double {
        Double(rayonCiel * rayonCiel * 4) / (2560 * 1440)
    }

    /// Fond de nuit, voie lactée et étoiles fixes, dans un carré dont le centre est le pôle.
    private func dessinerFondEtoile(_ ctx: CGContext, cote: CGFloat) {
        let centre = CGPoint(x: cote / 2, y: cote / 2)
        ctx.setFillColor(CGColor(red: 0.004, green: 0.008, blue: 0.024, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cote, height: cote))

        // Voie lactée : bande de nuages, puis poussières sombres.
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: -0.42)
        ctx.setBlendMode(.plusLighter)
        for _ in 0..<260 {
            let x = alea.entre(-cote * 0.52, cote * 0.52)
            let y = alea.entre(-cote * 0.13, cote * 0.13) * (1 - 0.4 * abs(x) / (cote * 0.52))
            let r = alea.entre(cote * 0.02, cote * 0.075)
            let a = alea.entre(0.010, 0.030)
            halo(ctx, centre: CGPoint(x: x, y: y), rayon: r,
                 couleur: (0.59, 0.67, 0.84), alpha: CGFloat(a))
        }
        ctx.setBlendMode(.normal)
        for _ in 0..<60 {
            let x = alea.entre(-cote * 0.5, cote * 0.5)
            let y = alea.entre(-cote * 0.10, cote * 0.10)
            let r = alea.entre(cote * 0.012, cote * 0.05)
            halo(ctx, centre: CGPoint(x: x, y: y), rayon: r, couleur: (0.008, 0.012, 0.031), alpha: 0.55)
        }
        ctx.restoreGState()

        for _ in 0..<Int(Double(nombreEtoiles) * surfaceRelative()) {
            let (x, y) = positionCiel()
            etoile(ctx, x: x, y: y, taille: magnitude(), teinte: teinte(), alpha: 1)
        }
    }

    // Position dans le carré du ciel, plus dense le long de la voie lactée.
    private func positionCiel() -> (CGFloat, CGFloat) {
        let cote = rayonCiel * 2
        for _ in 0..<6 {
            let x = alea.entre(0, cote), y = alea.entre(0, cote)
            let dx = x - rayonCiel, dy = y - rayonCiel
            let d = abs(dy * cos(-0.42) - dx * sin(-0.42)) / (cote * 0.16)
            let densite = 0.35 + 0.65 * exp(-Double(d * d) * 2.2)
            if alea.suivant() < densite { return (x, y) }
        }
        return (alea.entre(0, cote), alea.entre(0, cote))
    }

    private func magnitude() -> CGFloat { 0.35 + CGFloat(pow(alea.suivant(), 7)) * 2.6 }

    private func teinte() -> Int {
        let t = alea.suivant()
        if t < 0.10 { return 1 }
        if t < 0.25 { return 2 }
        if t < 0.31 { return 3 }
        return 0
    }

    // MARK: - Dessin d'une image

    /// Dessine tout sauf le fond étoilé, qui est porté par une couche à part.
    func dessinerElements(dans ctx: CGContext, temps T: Double) {
        let dt = dernierTemps > 0 ? min(T - dernierTemps, 0.1) : 1.0 / 60
        dernierTemps = T

        let angle = self.angle(temps: T)
        let p = polePosition(temps: T)
        let px = p.x, py = p.y
        let c = cos(angle), s = sin(angle)
        func versEcran(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: px + dx * c - dy * s, y: py + dx * s + dy * c)
        }

        // Étoiles qui scintillent.
        for e in scintillantes {
            let p = versEcran(e.x, e.y)
            guard p.x > -20, p.y > -20, p.x < taille.width + 20, p.y < taille.height + 20 else { continue }
            let v = 1 - e.creux * (0.5 + 0.5 * sin(T * e.vitesse + e.phase))
            etoile(ctx, x: p.x, y: p.y, taille: e.taille * CGFloat(0.75 + 0.35 * v),
                   teinte: e.teinte, alpha: CGFloat(v))
        }

        // Les planètes et la Lune sont portées par des calques, voir astres(temps:).

        dessinerSatellites(ctx, dt: dt, T: T)
        dessinerMeteores(ctx, dt: dt)
    }

    // MARK: - Satellites et étoiles filantes

    private func nouveauSatellite(etale: Bool = false) -> Satellite {
        let marge: CGFloat = 40
        var x: CGFloat = 0, y: CGFloat = 0
        switch Int(alea.suivant() * 4) {
        case 0: x = -marge; y = alea.entre(0, taille.height)
        case 1: x = taille.width + marge; y = alea.entre(0, taille.height)
        case 2: x = alea.entre(0, taille.width); y = -marge
        default: x = alea.entre(0, taille.width); y = taille.height + marge
        }
        let duree = alea.entre(22.0, 55.0)
        let cible = CGPoint(x: alea.entre(0, taille.width), y: alea.entre(0, taille.height * 0.9))
        let dx = cible.x - x, dy = cible.y - y
        let l = max(hypot(dx, dy), 1)
        let distance = hypot(taille.width, taille.height) * 1.3
        var s = Satellite(x: x, y: y,
                          vx: dx / l * distance / CGFloat(duree),
                          vy: dy / l * distance / CGFloat(duree),
                          eclat: alea.entre(0.45, 0.9), rythme: alea.entre(0.25, 1.1),
                          phase: alea.entre(0, 6.2832), age: 0, duree: duree,
                          flare: alea.suivant() < 0.25 ? alea.entre(0.25, 0.75) : 0)
        if etale {
            s.age = alea.entre(0, duree)
            s.x += s.vx * CGFloat(s.age); s.y += s.vy * CGFloat(s.age)
        }
        return s
    }

    private func dessinerSatellites(_ ctx: CGContext, dt: Double, T: Double) {
        for i in satellites.indices.reversed() {
            satellites[i].age += dt
            satellites[i].x += satellites[i].vx * CGFloat(dt)
            satellites[i].y += satellites[i].vy * CGFloat(dt)
            let s = satellites[i]
            let marge: CGFloat = 60
            if s.age > s.duree * 1.4 || s.x < -marge || s.x > taille.width + marge
                || s.y < -marge || s.y > taille.height + marge {
                satellites[i] = nouveauSatellite()
                continue
            }
            var eclat = s.eclat * (0.45 + 0.55 * abs(sin(T * s.rythme + s.phase)))
            if s.flare > 0 {
                let d = abs(s.age / s.duree - s.flare)
                eclat += 1.6 * exp(-d * d * 900)
            }
            let r = 1.1 + CGFloat(eclat) * 1.2
            if let sprite = sprites.first {
                ctx.setAlpha(CGFloat(min(1, eclat)))
                let rr = r * 3.6
                ctx.draw(sprite, in: CGRect(x: s.x - rr, y: s.y - rr, width: rr * 2, height: rr * 2))
                ctx.setAlpha(1)
            }
        }
    }

    private func dessinerMeteores(_ ctx: CGContext, dt: Double) {
        prochainMeteore -= dt
        if prochainMeteore <= 0 {
            let x = alea.entre(taille.width * 0.25, taille.width * 1.15)
            let y = alea.entre(taille.height * 0.55, taille.height * 1.05)
            let angle = alea.entre(3.43, 4.13)                  // vers le bas à gauche
            let v = alea.entre(0.35, 0.8) * hypot(taille.width, taille.height)
            let bleue = alea.suivant() < 0.22
            meteores.append(Meteore(x: x, y: y, vx: cos(angle) * v, vy: sin(angle) * v,
                                    vie: 0, duree: alea.entre(0.6, 1.6),
                                    epaisseur: alea.entre(1.0, 2.4),
                                    couleur: bleue ? (0.75, 0.88, 1.0) : (1.0, 0.93, 0.80)))
            prochainMeteore = alea.suivant() < 0.18
                ? alea.entre(0.3, 1.2)
                : alea.entre(secondesEntreMeteores * 0.45, secondesEntreMeteores * 1.7)
        }
        for i in meteores.indices.reversed() {
            meteores[i].vie += dt
            let m = meteores[i]
            if m.vie > m.duree { meteores.remove(at: i); continue }
            let t = m.vie / m.duree
            let opacite = CGFloat(sin(.pi * min(1, t * 1.25)))
            let x = m.x + m.vx * CGFloat(m.vie), y = m.y + m.vy * CGFloat(m.vie)
            let v = max(hypot(m.vx, m.vy), 1)
            let lg = v * CGFloat(min(0.30, m.duree * 0.4))
            let queue = CGPoint(x: x - m.vx / v * lg, y: y - m.vy / v * lg)

            let couleurs = [CGColor(red: m.couleur.0, green: m.couleur.1, blue: m.couleur.2, alpha: 0.9 * opacite),
                            CGColor(red: m.couleur.0, green: m.couleur.1, blue: m.couleur.2, alpha: 0)]
            if let degrade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: couleurs as CFArray, locations: [0, 1]) {
                ctx.saveGState()
                ctx.setLineWidth(m.epaisseur)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: queue)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                ctx.drawLinearGradient(degrade, start: CGPoint(x: x, y: y), end: queue, options: [])
                ctx.restoreGState()
            }
            halo(ctx, centre: CGPoint(x: x, y: y), rayon: m.epaisseur * 6,
                 couleur: (1, 1, 1), alpha: opacite)
        }
    }

    // MARK: - Primitives

    /// Petit disque lumineux dégradé (étoile, halo, tête de météore).
    private func halo(_ ctx: CGContext, centre: CGPoint, rayon: CGFloat,
                      couleur: (CGFloat, CGFloat, CGFloat), alpha: CGFloat) {
        guard rayon > 0, alpha > 0.002 else { return }
        let couleurs = [CGColor(red: couleur.0, green: couleur.1, blue: couleur.2, alpha: alpha),
                        CGColor(red: couleur.0, green: couleur.1, blue: couleur.2, alpha: alpha * 0.35),
                        CGColor(red: couleur.0, green: couleur.1, blue: couleur.2, alpha: 0)]
        guard let degrade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: couleurs as CFArray, locations: [0, 0.3, 1]) else { return }
        ctx.drawRadialGradient(degrade, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: rayon, options: [])
    }

    private func etoile(_ ctx: CGContext, x: CGFloat, y: CGFloat, taille: CGFloat,
                        teinte: Int, alpha: CGFloat) {
        let couleur = teintes[min(teinte, teintes.count - 1)]
        if taille < 0.7 {
            ctx.setFillColor(CGColor(red: couleur.0, green: couleur.1, blue: couleur.2, alpha: 0.55 * alpha))
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            return
        }
        if let sprite = sprites[safe: teinte] {
            let r = taille * 3.2
            ctx.setAlpha(alpha)
            ctx.draw(sprite, in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ctx.setAlpha(1)
        }
        if taille > 2.55 {                       // aigrettes des plus brillantes
            ctx.setStrokeColor(CGColor(red: couleur.0, green: couleur.1, blue: couleur.2, alpha: 0.13 * alpha))
            ctx.setLineWidth(0.8)
            let l = taille * 6
            ctx.move(to: CGPoint(x: x - l, y: y)); ctx.addLine(to: CGPoint(x: x + l, y: y))
            ctx.move(to: CGPoint(x: x, y: y - l)); ctx.addLine(to: CGPoint(x: x, y: y + l))
            ctx.strokePath()
        }
    }

    private func imageBitmap(largeur: Int, hauteur: Int, opaque: Bool,
                             _ dessin: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: largeur, height: hauteur,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if opaque {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        }
        dessin(ctx)
        return ctx.makeImage()
    }

    // MARK: - Lune et planètes

    private func construireLune(rayon: CGFloat) -> CGImage? {
        let cote = Int(ceil(rayon * 2)) + 4
        return imageBitmap(largeur: cote, hauteur: cote, opaque: false) { ctx in
            let c = CGPoint(x: CGFloat(cote) / 2, y: CGFloat(cote) / 2)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - rayon, y: c.y - rayon, width: rayon * 2, height: rayon * 2))
            ctx.clip()
            let couleurs = [CGColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1),
                            CGColor(red: 0.87, green: 0.85, blue: 0.80, alpha: 1),
                            CGColor(red: 0.72, green: 0.70, blue: 0.66, alpha: 1)]
            if let d = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: couleurs as CFArray, locations: [0, 0.65, 1]) {
                ctx.drawRadialGradient(d, startCenter: CGPoint(x: c.x - rayon * 0.28, y: c.y + rayon * 0.3),
                                       startRadius: rayon * 0.1, endCenter: c, endRadius: rayon, options: [])
            }
            for _ in 0..<9 {                      // mers lunaires
                let a = alea.entre(0, 6.2832), dd = alea.entre(0, rayon * 0.72)
                halo(ctx, centre: CGPoint(x: c.x + cos(a) * dd, y: c.y + sin(a) * dd),
                     rayon: alea.entre(rayon * 0.14, rayon * 0.38), couleur: (0.38, 0.39, 0.43), alpha: 0.40)
            }
            for _ in 0..<90 {                     // cratères
                let a = alea.entre(0, 6.2832), dd = CGFloat(sqrt(alea.suivant())) * rayon * 0.94
                let r = alea.entre(rayon * 0.012, rayon * 0.075)
                let p = CGPoint(x: c.x + cos(a) * dd, y: c.y + sin(a) * dd)
                halo(ctx, centre: p, rayon: r, couleur: (0.27, 0.27, 0.31), alpha: 0.30)
                ctx.setStrokeColor(CGColor(red: 1, green: 0.99, blue: 0.96, alpha: 0.18))
                ctx.setLineWidth(max(0.5, r * 0.14))
                ctx.addArc(center: CGPoint(x: p.x - r * 0.12, y: p.y + r * 0.12), radius: r * 0.92,
                           startAngle: 0.4, endAngle: 2.7, clockwise: false)
                ctx.strokePath()
            }
            // Phase : on efface la partie non éclairée.
            ctx.setBlendMode(.destinationOut)
            let k = cos(0.62 * 6.2832)
            halo(ctx, centre: CGPoint(x: c.x + CGFloat(k) * rayon * 1.02, y: c.y),
                 rayon: rayon * 1.12, couleur: (0, 0, 0), alpha: 1)
            ctx.restoreGState()
        }
    }

    private func construirePlanete(nom: String, rayon: CGFloat) -> CGImage? {
        let marge = nom == "saturne" ? rayon * 2.6 : rayon * 1.8
        let cote = Int(ceil((rayon + marge) * 2))
        let couleurs: [String: ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
            "mercure": ((0.66, 0.63, 0.58), (0.43, 0.40, 0.36)),
            "venus":   ((0.99, 0.95, 0.81), (0.85, 0.75, 0.56)),
            "mars":    ((0.83, 0.40, 0.29), (0.56, 0.23, 0.15)),
            "jupiter": ((0.91, 0.83, 0.69), (0.73, 0.56, 0.40)),
            "saturne": ((0.91, 0.86, 0.71), (0.75, 0.66, 0.47)),
            "uranus":  ((0.75, 0.91, 0.93), (0.50, 0.73, 0.77)),
            "neptune": ((0.49, 0.61, 0.91), (0.25, 0.36, 0.67)),
        ]
        guard let (clair, sombre) = couleurs[nom] else { return nil }

        return imageBitmap(largeur: cote, hauteur: cote, opaque: false) { ctx in
            let c = CGPoint(x: CGFloat(cote) / 2, y: CGFloat(cote) / 2)
            halo(ctx, centre: c, rayon: rayon * 4.2, couleur: clair, alpha: 0.20)
            if nom == "saturne" { anneaux(ctx, centre: c, rayon: rayon, arriere: true) }

            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - rayon, y: c.y - rayon, width: rayon * 2, height: rayon * 2))
            ctx.clip()
            let liste = [CGColor(red: clair.0, green: clair.1, blue: clair.2, alpha: 1),
                         CGColor(red: sombre.0, green: sombre.1, blue: sombre.2, alpha: 1),
                         CGColor(red: sombre.0 * 0.45, green: sombre.1 * 0.45, blue: sombre.2 * 0.45, alpha: 1)]
            if let d = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: liste as CFArray, locations: [0, 0.75, 1]) {
                ctx.drawRadialGradient(d, startCenter: CGPoint(x: c.x - rayon * 0.35, y: c.y + rayon * 0.35),
                                       startRadius: rayon * 0.05, endCenter: c, endRadius: rayon * 1.05, options: [])
            }
            if nom == "jupiter" || nom == "saturne" {
                let bandes = nom == "jupiter" ? 9 : 7
                for i in 0..<bandes {
                    let y = c.y - rayon + (CGFloat(i) + 0.5) * (2 * rayon / CGFloat(bandes))
                    let h = (2 * rayon / CGFloat(bandes)) * alea.entre(0.45, 0.95)
                    let t = i % 2 == 0 ? clair : sombre
                    ctx.setFillColor(CGColor(red: t.0, green: t.1, blue: t.2, alpha: alea.entre(0.10, 0.30)))
                    ctx.fillEllipse(in: CGRect(x: c.x - rayon * 1.05, y: y - h / 2, width: rayon * 2.1, height: h))
                }
                if nom == "jupiter" {            // la Grande Tache rouge
                    ctx.setFillColor(CGColor(red: 0.71, green: 0.33, blue: 0.24, alpha: 0.55))
                    ctx.fillEllipse(in: CGRect(x: c.x + rayon * 0.04, y: c.y - rayon * 0.36,
                                               width: rayon * 0.52, height: rayon * 0.28))
                }
            } else if nom == "mars" {
                for _ in 0..<7 {
                    let a = alea.entre(0, 6.2832), dd = alea.entre(0, rayon * 0.7)
                    ctx.setFillColor(CGColor(red: 0.41, green: 0.16, blue: 0.11, alpha: alea.entre(0.10, 0.26)))
                    ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * dd - rayon * 0.2, y: c.y + sin(a) * dd - rayon * 0.1,
                                               width: rayon * alea.entre(0.3, 0.8), height: rayon * alea.entre(0.16, 0.44)))
                }
                ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 0.85))
                ctx.fillEllipse(in: CGRect(x: c.x - rayon * 0.42, y: c.y + rayon * 0.75, width: rayon * 0.84, height: rayon * 0.36))
                ctx.fillEllipse(in: CGRect(x: c.x - rayon * 0.30, y: c.y - rayon * 1.07, width: rayon * 0.60, height: rayon * 0.24))
            } else if nom == "mercure" {
                for _ in 0..<18 {
                    let a = alea.entre(0, 6.2832), dd = CGFloat(sqrt(alea.suivant())) * rayon * 0.9
                    let r = alea.entre(rayon * 0.05, rayon * 0.16)
                    ctx.setFillColor(CGColor(red: 0.31, green: 0.29, blue: 0.27, alpha: 0.22))
                    ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * dd - r, y: c.y + sin(a) * dd - r, width: r * 2, height: r * 2))
                }
            }
            // Côté nuit.
            let nuit = [CGColor(red: 0, green: 0, blue: 0.02, alpha: 0),
                        CGColor(red: 0, green: 0, blue: 0.02, alpha: nom == "venus" || nom == "mercure" ? 0.7 : 0.45)]
            if let d = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: nuit as CFArray, locations: [0.45, 1]) {
                ctx.drawLinearGradient(d, start: CGPoint(x: c.x - rayon, y: c.y + rayon),
                                       end: CGPoint(x: c.x + rayon, y: c.y - rayon), options: [])
            }
            ctx.restoreGState()
            if nom == "saturne" { anneaux(ctx, centre: c, rayon: rayon, arriere: false) }
        }
    }

    /// Anneaux de Saturne vus de biais : moitié arrière, puis moitié avant.
    private func anneaux(_ ctx: CGContext, centre: CGPoint, rayon: CGFloat, arriere: Bool) {
        let bandes: [(CGFloat, CGFloat, CGFloat)] = [(1.35, 1.62, 0.30), (1.62, 2.05, 0.55), (2.13, 2.32, 0.34)]
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: -0.28)
        ctx.scaleBy(x: 1, y: 0.30)
        for (r1, r2, a) in bandes {
            ctx.setStrokeColor(CGColor(red: 0.94, green: 0.90, blue: 0.79, alpha: a))
            ctx.setLineWidth(rayon * (r2 - r1))
            let r = rayon * (r1 + r2) / 2
            ctx.addArc(center: .zero, radius: r,
                       startAngle: arriere ? 0 : .pi, endAngle: arriere ? .pi : .pi * 2, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import AppKit
import WebKit

// Capture une image fixe d'une page de fond d'écran.
// usage : swift Outils/capture-fond.swift <url> <largeur> <hauteur> <attente s> <sortie.png>

let args = CommandLine.arguments
guard args.count == 6,
      let url = URL(string: args[1]),
      let largeur = Int(args[2]), let hauteur = Int(args[3]),
      let attente = Double(args[4]) else {
    FputsErr("usage : capture-fond.swift <url> <largeur> <hauteur> <attente> <sortie.png>")
    exit(2)
}
func FputsErr(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
let sortie = URL(fileURLWithPath: args[5])

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Capteur: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let fenetre: NSWindow
    init(taille: NSSize) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(origin: .zero, size: taille), configuration: config)
        // La page doit être dans une fenêtre visible pour que WebKit l'anime réellement.
        fenetre = NSWindow(contentRect: NSRect(origin: .zero, size: taille),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        fenetre.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)))
        fenetre.isOpaque = true
        fenetre.backgroundColor = .black
        fenetre.contentView = webView
        super.init()
    }
    func afficher() { fenetre.orderFrontRegardless() }
    func capturer(vers: URL, apres: Double, fin: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + apres) { [self] in
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
            webView.takeSnapshot(with: config) { image, erreur in
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FputsErr("capture impossible : \(erreur?.localizedDescription ?? "inconnue")")
                    return fin(false)
                }
                do { try png.write(to: vers); fin(true) }
                catch { FputsErr("écriture impossible : \(error)"); fin(false) }
            }
        }
    }
}

let capteur = Capteur(taille: NSSize(width: largeur, height: hauteur))
capteur.afficher()
capteur.webView.load(URLRequest(url: url))
capteur.capturer(vers: sortie, apres: attente) { ok in
    print(ok ? "écrit : \(sortie.path)" : "échec")
    exit(ok ? 0 : 1)
}
app.run()

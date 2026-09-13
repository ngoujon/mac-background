import AppKit

/// Fenêtre sans bordure placée au niveau du bureau : sous les icônes,
/// jamais focalisable, absente de Cmd-Tab et de Mission Control.
final class WallpaperWindow: NSWindow {

    init(screenFrame: NSRect) {
        super.init(contentRect: screenFrame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        // Niveau « bureau » : au-dessus du fond d'écran système, sous les icônes
        // (kCGDesktopIconWindowLevel) et sous toutes les fenêtres applicatives.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Présente sur tous les bureaux, ne bouge pas avec les espaces,
        // ignorée par Cmd-Tab / Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        ignoresMouseEvents = true          // les clics vont au bureau/aux icônes
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true
        animationBehavior = .none
        // Suit l'écran sans être redimensionnée par le système.
        setFrame(screenFrame, display: false)
    }

    // Une fenêtre de fond d'écran ne prend jamais le focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

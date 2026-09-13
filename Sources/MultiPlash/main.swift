import AppKit

// Application sans icône dans le Dock : uniquement un élément de barre des menus.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

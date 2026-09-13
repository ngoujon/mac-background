import AppKit
import CoreGraphics

/// Identité stable d'un écran : l'UUID de l'affichage survit au redémarrage
/// et au rebranchement, contrairement au `CGDirectDisplayID` qui peut changer.
struct ScreenIdentity: Equatable {
    let uuid: String
    let displayID: CGDirectDisplayID
    let name: String
    let isMain: Bool
}

extension NSScreen {

    /// Identifiant matériel de l'affichage (clé `NSScreenNumber`).
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// UUID de l'affichage, via `CGDisplayCreateUUIDFromDisplayID` (API publique).
    /// En cas d'échec (rare), on retombe sur un identifiant dérivé du displayID.
    var identity: ScreenIdentity? {
        guard let displayID else { return nil }
        var uuid = "display-\(displayID)"
        if let reference = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, reference) as String? {
            uuid = string
        }
        let name = localizedName.isEmpty ? "Écran \(displayID)" : localizedName
        return ScreenIdentity(uuid: uuid,
                              displayID: displayID,
                              name: name,
                              isMain: self == NSScreen.screens.first)
    }
}

import AppKit

// Définit l'image de fond d'écran sur tous les écrans.
// macOS réutilise cette image pour l'écran de verrouillage.
// usage : swift Outils/definir-fond.swift <chemin de l'image>

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage : definir-fond.swift <image>\n".data(using: .utf8)!)
    exit(2)
}
let image = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard FileManager.default.isReadableFile(atPath: image.path) else {
    FileHandle.standardError.write("image introuvable : \(image.path)\n".data(using: .utf8)!)
    exit(1)
}

let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
    .allowClipping: true,
]
var erreurs = 0
for ecran in NSScreen.screens {
    do {
        try NSWorkspace.shared.setDesktopImageURL(image, for: ecran, options: options)
        let nom = ecran.localizedName
        print("fond défini sur « \(nom) »")
    } catch {
        FileHandle.standardError.write("échec sur un écran : \(error)\n".data(using: .utf8)!)
        erreurs += 1
    }
}
// Vérification
for ecran in NSScreen.screens {
    let actuel = NSWorkspace.shared.desktopImageURL(for: ecran)?.lastPathComponent ?? "aucun"
    print("  \(ecran.localizedName) → \(actuel)")
}
exit(erreurs == 0 ? 0 : 1)

#!/bin/bash
# Compile et assemble ./dist/CielEtoile.saver (économiseur d'écran « Ciel étoilé »).
set -euo pipefail
cd "$(dirname "$0")"

NOM="CielEtoile"
DIST="dist"
SAVER="$DIST/$NOM.saver"

echo "==> Compilation"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

swiftc -O -target arm64-apple-macos14.0 \
    -module-name "$NOM" -parse-as-library \
    -emit-library -Xlinker -bundle \
    -framework ScreenSaver -framework AppKit \
    -o "$SAVER/Contents/MacOS/$NOM" \
    Economiseur/CielEtoileView.swift Economiseur/CielScene.swift

echo "==> Assemblage"

cat > "$SAVER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>Ciel étoilé</string>
    <key>CFBundleDisplayName</key>           <string>Ciel étoilé</string>
    <key>CFBundleExecutable</key>            <string>$NOM</string>
    <key>CFBundleIdentifier</key>            <string>com.multiplash.CielEtoile</string>
    <key>CFBundlePackageType</key>           <string>BNDL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>NSPrincipalClass</key>              <string>CielEtoileView</string>
    <key>NSHighResolutionCapable</key>       <true/>
</dict>
</plist>
PLIST

echo "==> Signature ad hoc"
codesign --force --sign - --timestamp=none "$SAVER"
codesign --verify --strict --verbose=1 "$SAVER"
echo "==> Terminé : $SAVER"

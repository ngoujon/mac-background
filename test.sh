#!/bin/bash
# Lance la suite de tests.
#
# Sans Xcode installé (simples Command Line Tools), SwiftPM ne repère
# swift-testing que si l'emplacement de Testing.framework lui est donné en
# ligne de commande : un « swift test » nu compile alors les tests mais
# n'exécute rien. Ce script ajoute ce qu'il faut.
set -euo pipefail
cd "$(dirname "$0")"

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

if [ -d "/Applications/Xcode.app" ] || [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
    exec swift test "$@"
fi

exec swift test -Xswiftc -F -Xswiftc "$FRAMEWORKS" "$@"

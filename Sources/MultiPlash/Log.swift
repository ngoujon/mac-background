import Foundation
import os

/// Journalisation : `log show --predicate 'subsystem == "MultiPlash"' --last 5m`
///
/// On utilise systématiquement le niveau « default » (`log(...)`), seul niveau
/// conservé dans le journal persistant sans option supplémentaire.
enum Log {
    static let subsystem = "MultiPlash"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let windows = Logger(subsystem: subsystem, category: "fenetres")
    static let web = Logger(subsystem: subsystem, category: "web")
    static let power = Logger(subsystem: subsystem, category: "energie")
    static let config = Logger(subsystem: subsystem, category: "config")
}

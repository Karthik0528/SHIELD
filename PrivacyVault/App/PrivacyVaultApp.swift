import SwiftUI

public func shieldLog(_ message: String) {
    let formatted = message.hasSuffix("\n") ? message : message + "\n"
    fputs(formatted, stderr)
    fflush(stderr)
    NSLog("%@", message)
}

@main
struct PrivacyVaultApp: App {
    init() {
        shieldLog("[SHIELD_STARTUP] App init BEGIN")
        shieldLog("[SHIELD_STARTUP] App init END")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


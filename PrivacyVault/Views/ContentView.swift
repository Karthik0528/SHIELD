import SwiftUI

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager()
    @State private var refreshId: UUID = UUID()
    @State private var isInactive: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    // Auto-lock heartbeat timer when session is authenticated
    private let autoLockTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Group {
                if !vaultManager.authenticationManager.isSetupComplete {
                    SetupFlowView(vaultManager: vaultManager) {
                        refreshId = UUID()
                    }
                } else if !vaultManager.session.isAuthenticated {
                    LockScreenView(vaultManager: vaultManager)
                } else {
                    VaultGalleryView(vaultManager: vaultManager)
                }
            }
            .id(refreshId)
            
            // Background / Inactive Privacy Blur Overlay
            if isInactive && vaultManager.session.isAuthenticated {
                PrivacyOverlayView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .inactive, .background:
                isInactive = true
                vaultManager.checkAutoLock()
                if vaultManager.session.activeVaultType != nil {
                    vaultManager.lock()
                    refreshId = UUID()
                }
            case .active:
                isInactive = false
                vaultManager.checkAutoLock()
                refreshId = UUID()
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            isInactive = true
            vaultManager.lock()
            refreshId = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            isInactive = false
        }
        .onReceive(autoLockTimer) { _ in
            if vaultManager.session.isAuthenticated {
                let wasAuthenticated = vaultManager.session.isAuthenticated
                vaultManager.checkAutoLock()
                if wasAuthenticated != vaultManager.session.isAuthenticated {
                    refreshId = UUID()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

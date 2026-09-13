

import SwiftUI

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager()
    @State private var refreshId: UUID = UUID()
    @State private var isInactive: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    // Auto-lock heartbeat timer when session is authenticated
    private let autoLockTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    init() {
        shieldLog("[SHIELD_STARTUP] ContentView created")
    }
    
    var body: some View {
        let _ = shieldLog("[SHIELD_STARTUP] Rendering state: \(vaultManager.startupState)")
        return ZStack {
            Group {
                switch vaultManager.startupState {
                case .loading:
                    VaultLoadingView()
                case .uninitialized:
                    SetupFlowView(vaultManager: vaultManager) {
                        vaultManager.evaluateStartupState()
                        refreshId = UUID()
                    }
                case .ready:
                    if !vaultManager.session.isAuthenticated {
                        LockScreenView(vaultManager: vaultManager)
                    } else {
                        VaultGalleryView(vaultManager: vaultManager)
                    }
                case .vaultIntegrityError(let reason):
                    VaultIntegrityErrorView(reason: reason) {
                        vaultManager.evaluateStartupState()
                        refreshId = UUID()
                    }
                }
            }
            .id(refreshId)
            
            // Background / Inactive Privacy Blur Overlay
            if isInactive && vaultManager.session.isAuthenticated {
                PrivacyOverlayView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            vaultManager.evaluateStartupState()
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

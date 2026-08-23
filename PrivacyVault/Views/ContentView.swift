import SwiftUI

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager()
    @State private var refreshId: UUID = UUID()
    
    var body: some View {
        Group {
            if !vaultManager.authenticationManager.isSetupComplete {
                SetupFlowView(vaultManager: vaultManager) {
                    refreshId = UUID()
                }
            } else if !vaultManager.session.isAuthenticated {
                LockScreenView(vaultManager: vaultManager)
            } else {
                UnlockedVaultView(vaultManager: vaultManager)
            }
        }
        .id(refreshId)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            vaultManager.lock()
            refreshId = UUID()
        }
    }
}

/// Placeholder view when a vault session is unlocked.
struct UnlockedVaultView: View {
    let vaultManager: VaultManager
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: vaultManager.session.activeVaultType == .main ? "lock.open.fill" : "shield.fill")
                .font(.system(size: 64))
                .foregroundColor(vaultManager.session.activeVaultType == .main ? .green : .orange)
            
            Text(vaultManager.session.activeVaultType == .main ? "Main Vault Unlocked" : "Decoy Vault Unlocked")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your vault session is active and secure.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                vaultManager.lock()
            }) {
                Text("Lock Vault")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    ContentView()
}

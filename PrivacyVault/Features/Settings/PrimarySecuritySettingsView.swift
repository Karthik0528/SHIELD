import SwiftUI

/// Security settings view accessible ONLY when Primary Vault is active and authenticated.
/// Enables changing the Recovery Key.
public struct PrimarySecuritySettingsView: View {
    @ObservedObject private var vaultManager: VaultManager
    public let onDismiss: () -> Void
    
    @State private var newRecoveryKey: String = ""
    @State private var confirmRecoveryKey: String = ""
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    
    public init(vaultManager: VaultManager, onDismiss: @escaping () -> Void) {
        self.vaultManager = vaultManager
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 24) {
                // Top Bar
                HStack {
                    Text("Security Settings")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: dismissAndClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 24))
                                .foregroundColor(VaultTheme.secondaryViolet)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Change Recovery Key")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(VaultTheme.textPrimary)
                                
                                Text("Update the recovery key used to restore your Primary Vault PIN.")
                                    .font(.system(size: 13))
                                    .foregroundColor(VaultTheme.textSecondary)
                            }
                        }
                        
                        VStack(spacing: 12) {
                            SecureField("New Recovery Key", text: $newRecoveryKey)
                                .font(.system(size: 16))
                                .foregroundColor(VaultTheme.textPrimary)
                                .padding()
                                .background(VaultTheme.glassSurface)
                                .cornerRadius(VaultTheme.cornerRadiusMedium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                                        .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                                )
                            
                            SecureField("Confirm New Recovery Key", text: $confirmRecoveryKey)
                                .font(.system(size: 16))
                                .foregroundColor(VaultTheme.textPrimary)
                                .padding()
                                .background(VaultTheme.glassSurface)
                                .cornerRadius(VaultTheme.cornerRadiusMedium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                                        .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                                )
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.85))
                        }
                        
                        if let success = successMessage {
                            Text(success)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.green.opacity(0.9))
                        }
                        
                        PrimaryGradientButton(title: "Save New Recovery Key", systemImage: "checkmark.shield") {
                            saveRecoveryKey()
                        }
                        .disabled(newRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(newRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                    }
                    .padding(20)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
    }
    
    private func dismissAndClear() {
        clearSensitiveFields()
        onDismiss()
    }
    
    private func clearSensitiveFields() {
        newRecoveryKey = ""
        confirmRecoveryKey = ""
    }
    
    private func saveRecoveryKey() {
        let trimmedNew = newRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedNew.count >= 4 else {
            errorMessage = "Recovery key must be at least 4 characters."
            successMessage = nil
            return
        }
        guard newRecoveryKey == confirmRecoveryKey else {
            errorMessage = "Recovery keys do not match."
            successMessage = nil
            return
        }
        
        let keyToSave = newRecoveryKey
        do {
            try vaultManager.changeRecoveryKey(newRecoveryKey: keyToSave)
            errorMessage = nil
            successMessage = "Recovery key updated successfully."
            clearSensitiveFields()
        } catch {
            errorMessage = "Failed to update recovery key."
            successMessage = nil
        }
    }
}

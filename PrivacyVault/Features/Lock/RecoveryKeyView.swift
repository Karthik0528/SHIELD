import SwiftUI

/// Secure Recovery Key View presented when tapping the camouflaged shield-lock trigger after failed attempt threshold.
public struct RecoveryKeyView: View {
    @ObservedObject private var vaultManager: VaultManager
    public let onDismiss: () -> Void
    
    @State private var recoveryKey: String = ""
    @State private var isKeyVerified: Bool = false
    @State private var verifiedRecoveryKey: String = ""
    @State private var newPinStep: Int = 1 // 1: Create, 2: Confirm
    @State private var tempNewPin: String = ""
    @State private var errorMessage: String? = nil
    
    @FocusState private var isFieldFocused: Bool
    
    public init(vaultManager: VaultManager, onDismiss: @escaping () -> Void) {
        self.vaultManager = vaultManager
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                // Header bar
                HStack {
                    Button(action: dismissAndClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Spacer()
                
                if !isKeyVerified {
                    // Step 1: Enter Recovery Key
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(VaultTheme.primaryGradient)
                            .shadow(color: VaultTheme.glowPurple, radius: 16)
                        
                        Text("SHIELD")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(VaultTheme.textPrimary)
                        
                        Text("Enter Recovery Key")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                    
                    GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                        VStack(spacing: 16) {
                            SecureField("Recovery Key", text: $recoveryKey)
                                .focused($isFieldFocused)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(VaultTheme.textPrimary)
                                .padding()
                                .background(VaultTheme.glassSurface)
                                .cornerRadius(VaultTheme.cornerRadiusMedium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                                        .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                                )
                                .submitLabel(.continue)
                                .onSubmit {
                                    verifyKey()
                                }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 24)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.red.opacity(0.85))
                            .transition(.opacity)
                    } else {
                        Spacer().frame(height: 20)
                    }
                    
                    Spacer()
                    
                    PrimaryGradientButton(title: "Continue", systemImage: "arrow.right") {
                        verifyKey()
                    }
                    .disabled(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                } else {
                    // Step 2: Create & Confirm New Primary 4-Digit PIN
                    if newPinStep == 1 {
                        PinInputView(
                            title: "Create New Primary PIN",
                            subtitle: "Choose a new 4-digit Primary PIN.",
                            errorMessage: errorMessage
                        ) { pin in
                            tempNewPin = pin
                            errorMessage = nil
                            newPinStep = 2
                        }
                    } else {
                        PinInputView(
                            title: "Confirm New Primary PIN",
                            subtitle: "Re-enter your new 4-digit Primary PIN.",
                            errorMessage: errorMessage
                        ) { pin in
                            guard pin == tempNewPin else {
                                errorMessage = "PINs do not match. Try again."
                                tempNewPin = ""
                                newPinStep = 1
                                return
                            }
                            
                            let keyToUse = verifiedRecoveryKey
                            let pinToUse = pin
                            Task {
                                let result = await vaultManager.recoverPrimaryPin(recoveryKey: keyToUse, newPin: pinToUse)
                                switch result {
                                case .success:
                                    await MainActor.run {
                                        dismissAndClear()
                                    }
                                case .failure:
                                    await MainActor.run {
                                        errorMessage = "Recovery failed. Try again."
                                        clearSensitiveState()
                                        isKeyVerified = false
                                        newPinStep = 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            isFieldFocused = true
        }
    }
    
    private func dismissAndClear() {
        clearSensitiveState()
        onDismiss()
    }
    
    private func clearSensitiveState() {
        recoveryKey = ""
        verifiedRecoveryKey = ""
        tempNewPin = ""
    }
    
    private func verifyKey() {
        let key = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        
        let testKey = recoveryKey
        Task {
            do {
                _ = try vaultManager.keyManager.unlockPrimaryMasterKeyWithRecoveryKey(recoveryKey: testKey)
                await MainActor.run {
                    verifiedRecoveryKey = testKey
                    recoveryKey = ""
                    errorMessage = nil
                    isKeyVerified = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Incorrect recovery key."
                    clearSensitiveState()
                }
            }
        }
    }
}

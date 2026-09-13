import SwiftUI

public enum ChangePinTarget: String, Identifiable {
    case primary = "Primary Vault"
    case secondary = "Secondary Vault"
    
    public var id: String { rawValue }
    
    public var vaultType: VaultType {
        switch self {
        case .primary: return .main
        case .secondary: return .decoy
        }
    }
}

/// Secure PIN Management view accessible ONLY from Primary Security Settings.
/// Allows re-wrapping VMK_main or VMK_decoy with a new 4-digit PIN using active key hierarchy.
public struct ChangePinView: View {
    @ObservedObject private var vaultManager: VaultManager
    public let onDismiss: () -> Void
    
    @State private var selectedTarget: ChangePinTarget? = nil
    @State private var step: Int = 1 // 1: Enter Current, 2: Enter New, 3: Confirm New
    @State private var tempOldPin: String = ""
    @State private var tempNewPin: String = ""
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
                // Top Header Bar
                HStack {
                    Button(action: handleBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16))
                        }
                        .foregroundColor(VaultTheme.textPrimary)
                    }
                    
                    Spacer()
                    
                    Text("PIN Management")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Spacer()
                    
                    Button(action: dismissAndClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VaultTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                if let target = selectedTarget {
                    // Target PIN Change Workflow
                    VStack(spacing: 20) {
                        Text(target.rawValue)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(VaultTheme.secondaryViolet)
                        
                        if step == 1 {
                            PinInputView(
                                title: "Enter Current \(target.rawValue) PIN",
                                subtitle: "Verify current 4-digit PIN to proceed.",
                                errorMessage: errorMessage
                            ) { pin in
                                tempOldPin = pin
                                errorMessage = nil
                                step = 2
                            }
                        } else if step == 2 {
                            PinInputView(
                                title: "Enter New \(target.rawValue) PIN",
                                subtitle: "Choose a new 4-digit PIN.",
                                errorMessage: errorMessage
                            ) { pin in
                                tempNewPin = pin
                                errorMessage = nil
                                step = 3
                            }
                        } else {
                            PinInputView(
                                title: "Confirm New \(target.rawValue) PIN",
                                subtitle: "Re-enter your new 4-digit PIN.",
                                errorMessage: errorMessage
                            ) { confirmPin in
                                guard confirmPin == tempNewPin else {
                                    errorMessage = "New PINs do not match. Try again."
                                    tempNewPin = ""
                                    step = 2
                                    return
                                }
                                
                                executePinChange(target: target, oldPin: tempOldPin, newPin: confirmPin)
                            }
                        }
                    }
                } else {
                    // Target Selection Screen
                    VStack(spacing: 20) {
                        GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.rotation")
                                        .font(.system(size: 24))
                                        .foregroundColor(VaultTheme.secondaryViolet)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Change Vault PIN")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(VaultTheme.textPrimary)
                                        
                                        Text("Update PIN credentials without re-encrypting vault data.")
                                            .font(.system(size: 13))
                                            .foregroundColor(VaultTheme.textSecondary)
                                    }
                                }
                                
                                Button(action: { selectTarget(.primary) }) {
                                    HStack {
                                        Image(systemName: "shield.fill")
                                            .foregroundColor(VaultTheme.accentViolet)
                                        Text("Change Primary PIN")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(VaultTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(VaultTheme.textMuted)
                                    }
                                    .padding()
                                    .background(VaultTheme.glassSurface)
                                    .cornerRadius(VaultTheme.cornerRadiusMedium)
                                }
                                
                                Button(action: { selectTarget(.secondary) }) {
                                    HStack {
                                        Image(systemName: "eye.slash.fill")
                                            .foregroundColor(VaultTheme.secondaryViolet)
                                        Text("Change Secondary PIN")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(VaultTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(VaultTheme.textMuted)
                                    }
                                    .padding()
                                    .background(VaultTheme.glassSurface)
                                    .cornerRadius(VaultTheme.cornerRadiusMedium)
                                }
                            }
                            .padding(20)
                        }
                        .padding(.horizontal, 24)
                        
                        if let success = successMessage {
                            Text(success)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.green.opacity(0.9))
                                .padding(.horizontal, 24)
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.85))
                                .padding(.horizontal, 24)
                        }
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func selectTarget(_ target: ChangePinTarget) {
        selectedTarget = target
        step = 1
        errorMessage = nil
        successMessage = nil
    }
    
    private func handleBack() {
        if selectedTarget != nil {
            clearSensitiveState()
            selectedTarget = nil
            step = 1
            errorMessage = nil
        } else {
            dismissAndClear()
        }
    }
    
    private func dismissAndClear() {
        clearSensitiveState()
        onDismiss()
    }
    
    private func clearSensitiveState() {
        tempOldPin = ""
        tempNewPin = ""
    }
    
    private func executePinChange(target: ChangePinTarget, oldPin: String, newPin: String) {
        do {
            try vaultManager.changePin(for: target.vaultType, oldPin: oldPin, newPin: newPin)
            clearSensitiveState()
            let msg = "\(target.rawValue) changed successfully."
            selectedTarget = nil
            step = 1
            errorMessage = nil
            successMessage = msg
        } catch {
            clearSensitiveState()
            errorMessage = "Incorrect current PIN or invalid PIN format."
            step = 1
        }
    }
}

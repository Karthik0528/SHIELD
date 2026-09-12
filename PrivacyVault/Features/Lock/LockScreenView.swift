import SwiftUI

public struct LockScreenView: View {
    @ObservedObject private var viewModel: LockScreenViewModel
    @State private var pin: String = ""
    private let maxPinLength = 6
    
    public init(vaultManager: VaultManager) {
        self._viewModel = ObservedObject(wrappedValue: LockScreenViewModel(vaultManager: vaultManager))
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Header & Icon
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: VaultTheme.glowPurple, radius: 16)
                    
                    Text("Privacy Vault")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Enter your PIN")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(VaultTheme.textSecondary)
                }
                
                // PIN Dots Display
                SecurePinDots(count: pin.count, maxCount: maxPinLength)
                    .padding(.vertical, 8)
                
                // Error Message Display
                if let errorMsg = viewModel.errorMessage {
                    Text(errorMsg)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.85))
                        .transition(.opacity)
                } else {
                    Spacer().frame(height: 20)
                }
                
                // Keypad Matrix
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(spacing: 16) {
                        ForEach(0..<3) { row in
                            HStack(spacing: 24) {
                                ForEach(1...3, id: \.self) { col in
                                    let number = row * 3 + col
                                    keypadButton(label: "\(number)") {
                                        appendDigit("\(number)")
                                    }
                                }
                            }
                        }
                        
                        HStack(spacing: 24) {
                            Spacer().frame(width: 64, height: 64)
                            
                            keypadButton(label: "0") {
                                appendDigit("0")
                            }
                            
                            Button(action: deleteDigit) {
                                Image(systemName: "delete.left.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(VaultTheme.textSecondary)
                                    .frame(width: 64, height: 64)
                                    .background(VaultTheme.glassSurface)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
    }
    
    private func keypadButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(VaultTheme.textPrimary)
                .frame(width: 64, height: 64)
                .background(VaultTheme.glassSurface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                )
        }
    }
    
    private func appendDigit(_ digit: String) {
        guard pin.count < maxPinLength else { return }
        pin.append(digit)
        if pin.count == maxPinLength {
            let attempt = pin
            Task {
                await viewModel.unlock(with: attempt)
                if viewModel.errorMessage != nil {
                    pin = ""
                }
            }
        }
    }
    
    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
        }
    }
}

public final class LockScreenViewModel: ObservableObject {
    @Published public var errorMessage: String? = nil
    private let vaultManager: VaultManager
    
    public init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
    }
    
    @MainActor
    public func unlock(with pin: String) async {
        errorMessage = nil
        let result = await vaultManager.unlock(with: pin)
        switch result {
        case .success:
            errorMessage = nil
        case .failure:
            // Generic error message without revealing vault identity
            errorMessage = "Incorrect PIN."
        }
    }
}

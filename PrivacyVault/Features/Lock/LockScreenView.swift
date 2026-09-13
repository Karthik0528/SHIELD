import SwiftUI

public struct LockScreenView: View {
    @ObservedObject private var viewModel: LockScreenViewModel
    @State private var pin: String = ""
    @State private var isRecoverySheetPresented: Bool = false
    @State private var isSignaling: Bool = false
    private let maxPinLength = VaultSettings.standardPinLength
    
    public init(vaultManager: VaultManager) {
        self.viewModel = LockScreenViewModel(vaultManager: vaultManager)
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Mid-Top Center Camouflaged Shield-Lock Emblem
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: viewModel.failedAttempts >= 5 ? VaultTheme.glowPurple : Color.black.opacity(0.2), radius: viewModel.failedAttempts >= 5 ? 16 : 6)
                        .scaleEffect(isSignaling ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: isSignaling)
                        .allowsHitTesting(viewModel.failedAttempts >= 5)
                        .onLongPressGesture(minimumDuration: 3.0) {
                            if viewModel.failedAttempts >= 5 {
                                isRecoverySheetPresented = true
                            }
                        }
                    
                    Text("SHIELD")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text("Enter your PIN")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(VaultTheme.textSecondary)
                }
                
                // PIN Dots Display
                SecurePinDots(count: pin.count, maxCount: maxPinLength)
                    .padding(.vertical, 8)
                
                // Error Message Display (Generic "Incorrect PIN", no attempt counts or recovery text)
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
        .sheet(isPresented: $isRecoverySheetPresented) {
            RecoveryKeyView(vaultManager: viewModel.vaultManager) {
                isRecoverySheetPresented = false
            }
        }
        .onChange(of: viewModel.failedAttempts) { attempts in
            if attempts == 5 {
                isSignaling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    isSignaling = false
                }
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
            NSLog("[SHIELD_LOG] 4-digit input completed, unlock attempt started")
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
    @Published public var failedAttempts: Int = 0
    public let vaultManager: VaultManager
    
    public init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        self.failedAttempts = vaultManager.authenticationManager.failedAttempts
    }
    
    @MainActor
    public func unlock(with pin: String) async {
        errorMessage = nil
        let result = await vaultManager.unlock(with: pin)
        failedAttempts = vaultManager.authenticationManager.failedAttempts
        switch result {
        case .success:
            errorMessage = nil
        case .failure:
            // Generic error message without revealing vault identity or attempt counts
            errorMessage = "Incorrect PIN."
        }
    }
}

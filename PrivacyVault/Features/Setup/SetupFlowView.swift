import SwiftUI

public enum SetupStep {
    case welcome
    case createMainPin
    case confirmMainPin
    case createDecoyPin
    case confirmDecoyPin
    case complete
}

public struct SetupFlowView: View {
    @ObservedObject private var viewModel: SetupFlowViewModel
    
    public init(vaultManager: VaultManager, onSetupComplete: @escaping () -> Void) {
        self._viewModel = ObservedObject(wrappedValue: SetupFlowViewModel(vaultManager: vaultManager, onSetupComplete: onSetupComplete))
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            switch viewModel.currentStep {
            case .welcome:
                WelcomeSetupView {
                    viewModel.advanceToCreateMainPin()
                }
                
            case .createMainPin:
                PinInputView(
                    title: "Create Primary PIN",
                    subtitle: "Choose a 4-digit PIN for your primary vault.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleCreateMainPin(pin)
                }
                
            case .confirmMainPin:
                PinInputView(
                    title: "Confirm Primary PIN",
                    subtitle: "Re-enter your 4-digit Primary PIN.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleConfirmMainPin(pin)
                }
                
            case .createDecoyPin:
                PinInputView(
                    title: "Create Secondary PIN",
                    subtitle: "Choose a different 4-digit PIN for your secondary vault.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleCreateDecoyPin(pin)
                }
                
            case .confirmDecoyPin:
                PinInputView(
                    title: "Confirm Secondary PIN",
                    subtitle: "Re-enter your 4-digit Secondary PIN.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleConfirmDecoyPin(pin)
                }
                
            case .complete:
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: VaultTheme.glowPurple, radius: 16)
                    
                    VStack(spacing: 8) {
                        Text("Setup Complete")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(VaultTheme.textPrimary)
                        
                        Text("Your vault environment is initialized. Enter either PIN at unlock to open its corresponding vault.")
                            .font(.system(size: 15))
                            .foregroundColor(VaultTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                    
                    PrimaryGradientButton(title: "Proceed to Vault", systemImage: "arrow.right") {
                        viewModel.finishSetup()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

public final class SetupFlowViewModel: ObservableObject {
    @Published public var currentStep: SetupStep = .welcome
    @Published public var errorMessage: String? = nil
    
    private var tempMainPin: String = ""
    private var tempMainPinConfirmation: String = ""
    private var tempDecoyPin: String = ""
    
    private let vaultManager: VaultManager
    private let onSetupComplete: () -> Void
    
    public init(vaultManager: VaultManager, onSetupComplete: @escaping () -> Void) {
        self.vaultManager = vaultManager
        self.onSetupComplete = onSetupComplete
    }
    
    public func advanceToCreateMainPin() {
        errorMessage = nil
        currentStep = .createMainPin
    }
    
    public func handleCreateMainPin(_ pin: String) {
        guard pin.count >= 4 else {
            errorMessage = "PIN must be at least 4 digits."
            return
        }
        tempMainPin = pin
        errorMessage = nil
        currentStep = .confirmMainPin
    }
    
    public func handleConfirmMainPin(_ pin: String) {
        guard pin == tempMainPin else {
            errorMessage = "PINs do not match. Try again."
            tempMainPin = ""
            currentStep = .createMainPin
            return
        }
        tempMainPinConfirmation = pin
        errorMessage = nil
        currentStep = .createDecoyPin
    }
    
    public func handleCreateDecoyPin(_ pin: String) {
        guard pin.count >= 4 else {
            errorMessage = "PIN must be at least 4 digits."
            return
        }
        guard pin != tempMainPinConfirmation else {
            errorMessage = "Secondary PIN must be different from Primary PIN."
            return
        }
        tempDecoyPin = pin
        errorMessage = nil
        currentStep = .confirmDecoyPin
    }
    
    public func handleConfirmDecoyPin(_ pin: String) {
        guard pin == tempDecoyPin else {
            errorMessage = "PINs do not match. Try again."
            tempDecoyPin = ""
            currentStep = .createDecoyPin
            return
        }
        
        do {
            try vaultManager.authenticationManager.setupDualVaults(
                mainPin: tempMainPinConfirmation,
                decoyPin: pin
            )
            
            // Clear temporary PIN strings from memory
            tempMainPin = ""
            tempMainPinConfirmation = ""
            tempDecoyPin = ""
            
            errorMessage = nil
            currentStep = .complete
        } catch {
            errorMessage = "Setup failed. Please restart configuration."
            tempMainPin = ""
            tempMainPinConfirmation = ""
            tempDecoyPin = ""
            currentStep = .createMainPin
        }
    }
    
    public func finishSetup() {
        onSetupComplete()
    }
}

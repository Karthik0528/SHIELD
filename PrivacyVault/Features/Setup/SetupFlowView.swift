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
        VStack {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeSetupView {
                    viewModel.advanceToCreateMainPin()
                }
                
            case .createMainPin:
                PinInputView(
                    title: "Create Main PIN",
                    subtitle: "Choose a 4-digit PIN for your primary vault.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleCreateMainPin(pin)
                }
                
            case .confirmMainPin:
                PinInputView(
                    title: "Confirm Main PIN",
                    subtitle: "Re-enter your 4-digit Main PIN.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleConfirmMainPin(pin)
                }
                
            case .createDecoyPin:
                PinInputView(
                    title: "Create Decoy PIN",
                    subtitle: "Choose a different 4-digit PIN for your decoy vault.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleCreateDecoyPin(pin)
                }
                
            case .confirmDecoyPin:
                PinInputView(
                    title: "Confirm Decoy PIN",
                    subtitle: "Re-enter your 4-digit Decoy PIN.",
                    errorMessage: viewModel.errorMessage
                ) { pin in
                    viewModel.handleConfirmDecoyPin(pin)
                }
                
            case .complete:
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.green)
                    
                    Text("Setup Complete")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Both Main and Decoy vaults have been initialized. You can now unlock either vault using its respective PIN.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    Button(action: viewModel.finishSetup) {
                        Text("Proceed to Vault")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
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
            errorMessage = "Decoy PIN must be different from Main PIN."
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

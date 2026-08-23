import SwiftUI

public struct LockScreenView: View {
    @ObservedObject private var viewModel: LockScreenViewModel
    
    public init(vaultManager: VaultManager) {
        self._viewModel = ObservedObject(wrappedValue: LockScreenViewModel(vaultManager: vaultManager))
    }
    
    public var body: some View {
        PinInputView(
            title: "PrivacyVault",
            subtitle: "Enter PIN to unlock vault.",
            errorMessage: viewModel.errorMessage
        ) { pin in
            Task {
                await viewModel.unlock(with: pin)
            }
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

#Preview {
    LockScreenView(vaultManager: VaultManager())
}

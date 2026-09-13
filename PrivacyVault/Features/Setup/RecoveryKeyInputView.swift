import SwiftUI

/// Secure text input component for creating or confirming a flexible Recovery Key during setup.
public struct RecoveryKeyInputView: View {
    public let title: String
    public let subtitle: String
    public let errorMessage: String?
    public let buttonTitle: String
    public let onComplete: (String) -> Void
    
    @State private var textInput: String = ""
    @FocusState private var isFocused: Bool
    
    public init(
        title: String,
        subtitle: String,
        errorMessage: String? = nil,
        buttonTitle: String = "Continue",
        onComplete: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.buttonTitle = buttonTitle
        self.onComplete = onComplete
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "key.viewfinder")
                        .font(.system(size: 52))
                        .foregroundStyle(VaultTheme.primaryGradient)
                        .shadow(color: VaultTheme.glowPurple, radius: 12)
                    
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(VaultTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                GlassCard(cornerRadius: VaultTheme.cornerRadiusLarge) {
                    VStack(spacing: 16) {
                        SecureField("Enter Recovery Key", text: $textInput)
                            .focused($isFocused)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(VaultTheme.textPrimary)
                            .padding()
                            .background(VaultTheme.glassSurface)
                            .cornerRadius(VaultTheme.cornerRadiusMedium)
                            .overlay(
                                RoundedRectangle(cornerRadius: VaultTheme.cornerRadiusMedium)
                                    .stroke(VaultTheme.subtleBorder, lineWidth: 1)
                            )
                            .submitLabel(.done)
                            .onSubmit {
                                submit()
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
                
                PrimaryGradientButton(title: buttonTitle, systemImage: "arrow.right") {
                    submit()
                }
                .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func submit() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value = textInput
        textInput = ""
        onComplete(value)
    }
}

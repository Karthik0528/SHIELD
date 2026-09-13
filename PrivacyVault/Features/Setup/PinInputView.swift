import SwiftUI

public struct PinInputView: View {
    public let title: String
    public let subtitle: String
    public let errorMessage: String?
    public let onComplete: (String) -> Void
    
    @State private var pin: String = ""
    private let targetLength: Int = VaultSettings.standardPinLength
    
    public init(
        title: String,
        subtitle: String,
        errorMessage: String? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.onComplete = onComplete
    }
    
    public var body: some View {
        ZStack {
            VaultBackground()
            
            VStack(spacing: 32) {
                Spacer()
                
                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(VaultTheme.textPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(VaultTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                SecurePinDots(count: pin.count, maxCount: targetLength)
                    .padding(.vertical, 8)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.85))
                        .transition(.opacity)
                } else {
                    Spacer().frame(height: 20)
                }
                
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
        if pin.count < targetLength {
            pin.append(digit)
            if pin.count == targetLength {
                let submittedPin = pin
                pin = ""
                onComplete(submittedPin)
            }
        }
    }
    
    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
        }
    }
}

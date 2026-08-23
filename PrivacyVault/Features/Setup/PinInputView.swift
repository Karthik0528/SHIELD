import Foundation
import SwiftUI

public struct PinInputView: View {
    public let title: String
    public let subtitle: String
    public let errorMessage: String?
    public let onComplete: (String) -> Void
    
    @State private var pin: String = ""
    private let targetLength: Int = 4
    
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
        VStack(spacing: 24) {
            Spacer()
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // PIN Indicators
            HStack(spacing: 16) {
                ForEach(0..<targetLength, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 16)
            
            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Keypad
            VStack(spacing: 16) {
                ForEach(0..<3) { row in
                    HStack(spacing: 24) {
                        ForEach(1...3, id: \.self) { col in
                            let number = row * 3 + col
                            KeypadButton(text: "\(number)") {
                                appendDigit("\(number)")
                            }
                        }
                    }
                }
                
                HStack(spacing: 24) {
                    Spacer().frame(width: 72, height: 72)
                    
                    KeypadButton(text: "0") {
                        appendDigit("0")
                    }
                    
                    Button(action: deleteDigit) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 72, height: 72)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .onChange(of: pin) { newValue in
            if newValue.count == targetLength {
                let submittedPin = pin
                pin = ""
                onComplete(submittedPin)
            }
        }
    }
    
    private func appendDigit(_ digit: String) {
        if pin.count < targetLength {
            pin.append(digit)
        }
    }
    
    private func deleteDigit() {
        if !pin.isEmpty {
            pin.removeLast()
        }
    }
}

private struct KeypadButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 72, height: 72)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
        }
    }
}

#Preview {
    PinInputView(
        title: "Create Main PIN",
        subtitle: "Enter a 4-digit PIN for your primary vault.",
        onComplete: { _ in }
    )
}

import SwiftUI

/// Explicit text/background pairing; brand color must not tint ordinary control labels.
struct RavenPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? RavenBrand.primaryActionText : Color.secondary)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(isEnabled ? RavenBrand.headphoneAmber : Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isFocused ? Color.primary : Color.secondary, lineWidth: isFocused ? 3 : 1))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(.black, lineWidth: 3)
                    RoundedRectangle(cornerRadius: 11).stroke(.white, lineWidth: 1).padding(-2)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

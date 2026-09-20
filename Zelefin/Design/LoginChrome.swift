import SwiftUI

/// Shared sign-in canvas colors. Plus uses the same black field and cyan action.
enum LoginPalette {
    static let cyan = AccentPreferences.cyan.color
    static let cobalt = Color(red: 0.0, green: 0.22, blue: 0.98)
    static let canvas = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let captionText = Color.white.opacity(0.55)
    static let iconTint = Color.white.opacity(0.55)
    static let fieldValue = Color.white
    static let divider = Color.white.opacity(0.12)
    static let actionLabel = Color.black
    static let success = Color(red: 0.22, green: 0.78, blue: 0.42)
    static let failure = Color(red: 1, green: 0.38, blue: 0.38)
}

struct LoginCanvasGlow: View, Equatable {
    var isRegularWidth: Bool

    var body: some View {
        GeometryReader { geo in
            let endRadius = isRegularWidth
                ? hypot(geo.size.width / 2, geo.size.height)
                : max(geo.size.width * 0.72, 220)

            RadialGradient(
                colors: [
                    LoginPalette.cyan.opacity(0.28),
                    LoginPalette.cobalt.opacity(0.16),
                    LoginPalette.canvas
                ],
                center: .top,
                startRadius: 12,
                endRadius: endRadius
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LoginActionButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(LoginPalette.actionLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor)
            )
    }
}

struct LoginSecondaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
            )
    }
}

struct LoginCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LoginPalette.divider, lineWidth: 1)
            )
    }
}

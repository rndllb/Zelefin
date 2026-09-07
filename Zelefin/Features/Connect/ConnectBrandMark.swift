import SwiftUI

/// A temporary brand plate used until a custom Zelefin mark ships.
struct ConnectBrandMark: View {
    var size: CGFloat = 88

    var body: some View {
        let cornerRadius = size * 0.22

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.12))

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.white.opacity(0.22), radius: 10, y: 5)
        .accessibilityLabel("Zelefin")
    }
}

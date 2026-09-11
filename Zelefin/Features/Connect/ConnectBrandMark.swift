import SwiftUI

/// The isometric Z from the app icon, shown on the sign-in canvas.
struct ConnectBrandMark: View {
    var size: CGFloat = 168

    var body: some View {
        Image("ZelefinMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

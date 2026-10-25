import SwiftUI

/// The isometric Z from the app icon, shown on the sign-in canvas.
struct ConnectBrandMark: View {
    var size: CGFloat = 168

    var body: some View {
        Image("ZelefinMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Session restore and other full-screen waits. Matches the launch mark on black.
struct ZelefinLoadingView: View {
    var message: String? = nil
    var markSize: CGFloat = 168

    var body: some View {
        ZStack {
            LoginPalette.canvas.ignoresSafeArea()
            LoginCanvasGlow(isRegularWidth: false)
            VStack(spacing: 20) {
                ConnectBrandMark(size: markSize)
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LoginPalette.secondaryText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Loading")
    }
}

/// Which kind of server the sign-in form is for. Silo uses its own sign-in and household
/// profiles; everything after that runs on its Jellyfin-compatible API. Emby runs on Emby's own API.
enum SignInServerType: String, CaseIterable, Sendable {
    case jellyfin
    case silo
    case emby

    var title: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .silo: "Silo"
        case .emby: "Emby"
        }
    }

    fileprivate var logoName: String {
        switch self {
        case .jellyfin: "JellyfinLogo"
        case .silo: "SiloLogo"
        case .emby: "EmbyLogo"
        }
    }

    fileprivate func logoPadding(tileSize: CGFloat) -> CGFloat {
        switch self {
        case .jellyfin: tileSize * 0.22
        case .silo: tileSize * 0.18
        case .emby: tileSize * 0.24
        }
    }
}

/// Rounded-square Jellyfin / Silo / Emby marks under the Zelefin logo.
struct ConnectBackendPicker: View {
    @Binding var selection: SignInServerType
    var tileSize: CGFloat = 86

    var body: some View {
        HStack(spacing: 18) {
            tile(.jellyfin)
            tile(.silo)
            tile(.emby)
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ backend: SignInServerType) -> some View {
        let selected = selection == backend
        return Button {
            selection = backend
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.16 : 0.08))
                    RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0.9 : 0.22), lineWidth: selected ? 1.5 : 1)
                    Image(backend.logoName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .padding(backend.logoPadding(tileSize: tileSize))
                        .foregroundStyle(Color.white.opacity(backend == .silo ? 1 : 0.72))
                }
                .frame(width: tileSize, height: tileSize)

                Text(backend.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(selected ? LoginPalette.primaryText : LoginPalette.captionText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(backend.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Use this server type to sign in")
    }
}

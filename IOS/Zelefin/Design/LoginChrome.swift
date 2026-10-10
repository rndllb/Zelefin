import SwiftUI
import UIKit

/// Shared sign-in canvas colors.
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

enum SettingsChrome {
    static var cardInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: 4, bottom: 10, trailing: 4)
    }

    static var heroInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: 4, bottom: 20, trailing: 4)
    }
}

extension View {
    func settingsLoginCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(LoginCardBackground())
    }

    func settingsCardRow() -> some View {
        self
    }

    func settingsHeroRow() -> some View {
        self
            .listRowBackground(Color.clear)
    }
}

struct SettingsFieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        EmptyView()
    }
}

struct SettingsPrimaryButton: View {
    let title: String
    var isBusy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                        .tint(LoginPalette.actionLabel)
                } else {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                }
                Spacer(minLength: 0)
            }
            .modifier(LoginActionButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isBusy)
        .opacity(!enabled || isBusy ? 0.42 : 1)
        .accessibilityLabel(title)
    }
}

struct SettingsSecondaryButton: View {
    let title: String
    var role: ButtonRole?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Spacer(minLength: 0)
                Text(title)
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                Spacer(minLength: 0)
            }
            .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }
}

struct SettingsStatusText: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isError ? LoginPalette.failure : LoginPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsChip: View {
    var icon: String?
    let leading: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(leading)
                .font(.caption.weight(.bold))
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .zelefinLiquidGlassCapsule(interactive: false)
    }
}

struct SettingsCameraBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 32, height: 32)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

struct SettingsHeroGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 52, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 132, height: 132)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
            .padding(6)
            .zelefinLiquidGlassCircle(interactive: false)
            .frame(width: 144, height: 144)
            .accessibilityHidden(true)
    }
}

struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsFieldLabel(title: label)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsLabeledField<Content: View>: View {
    let label: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsFieldLabel(title: label)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LoginPalette.iconTint)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                content()
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.fieldValue)
            }
        }
    }
}

struct SettingsStatusValue: View {
    let text: String
    var isPositive = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(isPositive ? LoginPalette.success : LoginPalette.captionText)
    }
}

struct SettingsStackedRow: View {
    let title: String
    var subtitle: String = ""
    var caption: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.primaryText)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(LoginPalette.secondaryText)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(LoginPalette.captionText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, subtitle, caption].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

struct SettingsNavRow: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LoginPalette.secondaryText)
                }
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

struct SettingsPersonRow: View {
    let name: String
    let subtitle: String
    var avatarURL: URL?
    var localImage: UIImage? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            UserAvatarView(url: avatarURL, localImage: localImage, diameter: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LoginPalette.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                SettingsChevron()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.isEmpty ? name : "\(name), \(subtitle)")
    }
}

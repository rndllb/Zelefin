import SwiftUI
import UIKit

/// Full-screen household pick. One login, several watchers — choose who is using this device.
struct SiloWhoIsWatchingView: View {
    var profiles: [SiloProfile]
    var currentID: String? = nil
    var footerTitle: String? = nil
    var isBusy: Bool = false
    var errorMessage: String? = nil
    /// A heads-up that does not stop sign-in, such as an address that only works at home.
    var notice: String? = nil
    var onSelect: (SiloProfile, String?) async -> Void
    var onFooter: (() -> Void)? = nil

    @State private var selectedID: String?
    @State private var pin = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            ZStack {
                LoginPalette.canvas
                LoginCanvasGlow(isRegularWidth: horizontalSizeClass == .regular)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Text("Who's watching?")
                    .font(.system(size: horizontalSizeClass == .regular ? 40 : 32, weight: .semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)

                if let notice, !notice.isEmpty {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .padding(.horizontal, 28)
                }

                if profiles.isEmpty {
                    Text("This account has no household profiles yet.")
                        .font(.subheadline)
                        .foregroundStyle(LoginPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.horizontal, 32)
                } else {
                    profileGrid
                        .padding(.top, 36)
                }

                if let selected, selected.hasPin {
                    pinCard(for: selected)
                        .padding(.top, 28)
                        .padding(.horizontal, 26)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(LoginPalette.failure)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 26)
                }

                Spacer(minLength: 16)

                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .padding(.bottom, 18)
                }

                if let footerTitle, onFooter != nil {
                    Button(footerTitle) {
                        onFooter?()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LoginPalette.secondaryText)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .padding(.bottom, 36)
                    .accessibilityLabel(footerTitle)
                }
            }
            .animation(.easeOut(duration: 0.22), value: selectedID)
        }
    }

    private var selected: SiloProfile? {
        profiles.first(where: { $0.id == selectedID })
    }

    private var profileGrid: some View {
        CenteredProfileWrap(spacing: 22, lineSpacing: 22) {
            ForEach(profiles) { profile in
                Button {
                    choose(profile)
                } label: {
                    HouseholdProfileTile(
                        profile: profile,
                        isCurrent: profile.id == currentID,
                        isSelected: profile.id == selectedID
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(accessibilityLabel(for: profile))
                .accessibilityAddTraits(profile.id == currentID ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    private func pinCard(for profile: SiloProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PIN for \(profile.name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoginPalette.captionText)
                .tracking(0.6)

            SecureField("PIN", text: $pin)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            Button {
                Task { await onSelect(profile, pin) }
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text("Continue")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                    Spacer(minLength: 0)
                }
                .modifier(LoginActionButtonStyle())
            }
            .buttonStyle(.plain)
            .disabled(pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            .opacity(pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy ? 0.42 : 1)
        }
        .padding(18)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .modifier(LoginCardBackground())
    }

    private func choose(_ profile: SiloProfile) {
        selectedID = profile.id
        if profile.hasPin {
            pin = ""
            return
        }
        Task { await onSelect(profile, nil) }
    }

    private func accessibilityLabel(for profile: SiloProfile) -> String {
        var parts = [profile.name]
        if profile.isChild { parts.append("Kids") }
        if profile.hasPin { parts.append("PIN required") }
        if profile.id == currentID { parts.append("Current") }
        return parts.joined(separator: ", ")
    }
}

/// Packs profile tiles into rows and centers each row, instead of a leading grid.
private struct CenteredProfileWrap: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(into: CGFloat.zero) { $0 += $1.height }
            + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        let width = min(proposal.width ?? .infinity, rows.map(\.width).max() ?? 0)
        return CGSize(width: width.isFinite ? width : 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.midX - row.width / 2
            for size in row.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var sizes: [CGSize]
        var width: CGFloat
        var height: CGFloat
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var result: [Row] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let next = sizes.isEmpty ? size.width : width + spacing + size.width
            if !sizes.isEmpty, next > maxWidth {
                result.append(Row(sizes: sizes, width: width, height: height))
                sizes = [size]
                width = size.width
                height = size.height
            } else {
                sizes.append(size)
                width = next
                height = max(height, size.height)
            }
        }
        if !sizes.isEmpty {
            result.append(Row(sizes: sizes, width: width, height: height))
        }
        return result
    }
}

struct HouseholdProfileTile: View {
    var profile: SiloProfile
    var isCurrent: Bool
    var isSelected: Bool
    var size: CGFloat = 104

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                HouseholdProfileAvatar(profile: profile, size: size)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected || isCurrent ? Color.white : Color.clear,
                                lineWidth: 3
                            )
                    }

                if profile.hasPin {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)

            VStack(spacing: 2) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if profile.isChild {
                    Text("Kids")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LoginPalette.captionText)
                }
            }
            .frame(width: size + 8)
        }
        .frame(minWidth: 44, minHeight: 44)
    }
}

struct HouseholdProfileAvatar: View {
    var profile: SiloProfile
    var size: CGFloat
    @State private var remoteImage: UIImage?

    var body: some View {
        Group {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(swatch)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: profile.avatarURL?.absoluteString) {
            await load()
        }
    }

    private var initials: String {
        let parts = profile.name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        let value = letters.joined().uppercased()
        return value.isEmpty ? "•" : value
    }

    private var swatch: Color {
        let swatches: [Color] = [
            Color(white: 0.22),
            Color(white: 0.30),
            Color(white: 0.38),
            Color(white: 0.46),
            Color(white: 0.28),
            Color(white: 0.34)
        ]
        let index = abs(profile.id.hashValue) % swatches.count
        return swatches[index]
    }

    private func load() async {
        remoteImage = nil
        guard let url = profile.avatarURL else { return }
        if let loaded = await ArtworkCache.shared.load(from: url, persist: false) {
            guard !Task.isCancelled else { return }
            remoteImage = loaded
        }
    }
}

import SwiftUI

/// Shared zoom between the mini player artwork and the full-screen player, like Apple Music's
/// Now Playing. `RootView` owns the namespace; the accessory marks the source.
enum NowPlayingTransition {
    static let sourceID = "now-playing-artwork"
    static let artworkCornerRadius: CGFloat = 6
}

extension EnvironmentValues {
    @Entry var nowPlayingTransition: Namespace.ID? = nil
    /// Set inside sheets: the root player cannot present over an open sheet.
    @Entry var playsInLocalCover = false
}

extension View {
    /// The mini player (and so the zoom source) only exists on iOS 26; earlier systems keep the
    /// standard full-screen slide.
    @ViewBuilder
    func nowPlayingZoom(in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            navigationTransition(.zoom(sourceID: NowPlayingTransition.sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Hands a screen's `playingItem` to the root player instead of presenting a local one.
    func presentsPlayerFromRoot(_ item: Binding<MediaItem?>, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(RootPlayerRouting(item: item, onDismiss: onDismiss))
    }
}

private struct RootPlayerRouting: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(\.playsInLocalCover) private var playsInLocalCover
    @Binding var item: MediaItem?
    var onDismiss: (() -> Void)?
    @State private var awaitingDismiss = false

    func body(content: Content) -> some View {
        if playsInLocalCover {
            content.fullScreenCover(item: $item, onDismiss: onDismiss) { item in
                PlayerView(item: item)
            }
        } else {
            routed(content)
        }
    }

    private func routed(_ content: Content) -> some View {
        content
            .onChange(of: item) { _, next in
                guard let next else { return }
                item = nil
                awaitingDismiss = true
                session.presentPlayer(next)
            }
            .onChange(of: session.pendingPlayerItem == nil) { _, closed in
                guard closed, awaitingDismiss else { return }
                awaitingDismiss = false
                onDismiss?()
            }
    }
}

/// Now Playing chip that lives in the system tab-bar accessory.
/// Scroll-down / scroll-up motion is owned by `tabBarMinimizeBehavior` on `MainTabView`.
struct MiniPlayerView: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            MiniPlayerAccessory()
        }
    }
}

@available(iOS 26.0, *)
private struct MiniPlayerAccessory: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.nowPlayingTransition) private var transition

    var body: some View {
        if let item = session.nowPlayingItem {
            Group {
                if placement == .inline {
                    compact(item)
                } else {
                    expanded(item)
                }
            }
        }
    }

    private func expanded(_ item: MediaItem) -> some View {
        HStack(spacing: 10) {
            artwork(item, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.continueWatchingTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = subtitle(for: item) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            transportButton(systemImage: "play.fill", label: "Play") {
                session.presentNowPlaying()
            }
            transportButton(systemImage: "forward.fill", label: "Next") {
                session.presentNowPlaying()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            session.presentNowPlaying()
        }
        .contextMenu {
            Button("Play") { session.presentNowPlaying() }
            Button("Stop", role: .destructive) { session.clearNowPlaying() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityAddTraits(.isButton)
    }

    private func compact(_ item: MediaItem) -> some View {
        HStack(spacing: 8) {
            artwork(item, size: 26)
            Text(item.continueWatchingTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            transportButton(systemImage: "play.fill", label: "Play") {
                session.presentNowPlaying()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            session.presentNowPlaying()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func artwork(_ item: MediaItem, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: NowPlayingTransition.artworkCornerRadius, style: .continuous)
        let image = PosterImage(
            url: session.library?.primaryURL(for: item, maxHeight: 80),
            aspectRatio: 1,
            contentMode: .fill
        )
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
        if let transition {
            image.matchedTransitionSource(id: NowPlayingTransition.sourceID, in: transition) { source in
                source.clipShape(shape)
            }
        } else {
            image
        }
    }

    private func transportButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func subtitle(for item: MediaItem) -> String? {
        if let episode = item.episodeLabel, !episode.isEmpty {
            return episode
        }
        return item.recentlyWatchedCaption
    }

    private func accessibilityLabel(for item: MediaItem) -> String {
        if let subtitle = subtitle(for: item) {
            return "Now Playing, \(item.continueWatchingTitle), \(subtitle)"
        }
        return "Now Playing, \(item.continueWatchingTitle)"
    }
}

/// Applies the system mini-player accessory and dock collapse on scroll.
struct MiniPlayerDockChrome: ViewModifier {
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: isEnabled) {
                    MiniPlayerView()
                }
        } else if #available(iOS 26.0, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if isEnabled {
                        MiniPlayerView()
                    }
                }
        } else {
            content
        }
    }
}

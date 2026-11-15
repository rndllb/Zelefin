import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Fallback when an activity payload has no accent hex (older in-flight activities).
private let defaultAccent = Color(red: 153 / 255, green: 150 / 255, blue: 209 / 255)

/// A poster thumbnail, or the status glyph when the art hasn't been written yet.
private struct ActivityPoster: View {
    let attributes: ZelefinActivityAttributes
    let state: ZelefinActivityAttributes.ContentState
    var size: CGFloat

    var body: some View {
        let width = size
        let height = size * 1.5
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.12))
            if let data = attributes.posterThumbnail, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Image(systemName: statusSymbol(attributes.kind, state))
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(statusColor(attributes.kind, state))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Live Activities for downloads, Now Playing, SyncPlay, Live TV, requests, catalog, and remote sessions.
struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZelefinActivityAttributes.self) { context in
            ZelefinLockScreenActivityView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingExpanded(context.attributes.kind, context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 10) {
                        ActivityPoster(attributes: context.attributes, state: context.state, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if !context.attributes.subtitle.isEmpty {
                                Text(context.attributes.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if showsProgress(context.attributes.kind, context.state) {
                            ProgressView(value: context.state.clampedFraction)
                                .tint(statusColor(context.attributes.kind, context.state))
                        }
                        HStack(spacing: 6) {
                            if let badge = context.state.badgeLabel, !badge.isEmpty {
                                Text(badge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor(context.attributes.kind, context.state), in: Capsule())
                            }
                            Text(context.state.statusLine)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: statusSymbol(context.attributes.kind, context.state))
                    .foregroundStyle(statusColor(context.attributes.kind, context.state))
            } compactTrailing: {
                compactTrailing(context.attributes.kind, context.state)
            } minimal: {
                Image(systemName: statusSymbol(context.attributes.kind, context.state))
                    .foregroundStyle(statusColor(context.attributes.kind, context.state))
            }
        }
    }
}

@ViewBuilder
private func trailingExpanded(
    _ kind: ZelefinActivityKind,
    _ state: ZelefinActivityAttributes.ContentState
) -> some View {
    if let percent = state.percentText, showsProgress(kind, state) {
        Text(percent)
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
    } else if state.isPaused {
        Image(systemName: "pause.fill")
            .foregroundStyle(.white)
    }
}

@ViewBuilder
private func compactTrailing(
    _ kind: ZelefinActivityKind,
    _ state: ZelefinActivityAttributes.ContentState
) -> some View {
    if let percent = state.percentText, showsProgress(kind, state) {
        Text(percent)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
    } else if state.isPaused {
        Image(systemName: "pause.fill")
            .font(.caption2)
            .foregroundStyle(.white)
    } else if kind == .liveTV || kind == .playback || kind == .syncPlay {
        Image(systemName: "play.fill")
            .font(.caption2)
            .foregroundStyle(.white)
    } else {
        ProgressView().tint(accentColor(state))
    }
}

private func showsProgress(_ kind: ZelefinActivityKind, _ state: ZelefinActivityAttributes.ContentState) -> Bool {
    if state.fraction == nil { return false }
    switch kind {
    case .download, .catalog, .playback, .liveTV, .request:
        return true
    case .syncPlay, .remoteSession:
        return false
    }
}

private func statusSymbol(
    _ kind: ZelefinActivityKind,
    _ state: ZelefinActivityAttributes.ContentState
) -> String {
    if state.isFailed { return "exclamationmark.triangle.fill" }
    if state.isFinished { return "checkmark.circle.fill" }
    if state.isPaused { return "pause.circle.fill" }
    switch kind {
    case .download: return "arrow.down.circle"
    case .playback: return "play.circle.fill"
    case .syncPlay: return "person.2.circle.fill"
    case .liveTV: return "dot.radiowaves.left.and.right"
    case .request: return "clock.badge.checkmark"
    case .catalog: return "square.stack.3d.up.fill"
    case .remoteSession: return "tv.and.mediabox"
    }
}

private func statusColor(
    _ kind: ZelefinActivityKind,
    _ state: ZelefinActivityAttributes.ContentState
) -> Color {
    if state.isFailed { return .orange }
    if state.isFinished { return .green }
    return accentColor(state)
}

private func accentColor(_ state: ZelefinActivityAttributes.ContentState) -> Color {
    color(fromHex: state.accentHex) ?? defaultAccent
}

private func color(fromHex hex: String) -> Color? {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
    var rgb: UInt64 = 0
    guard Scanner(string: value).scanHexInt64(&rgb) else { return nil }
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}

struct ZelefinLockScreenActivityView: View {
    let attributes: ZelefinActivityAttributes
    let state: ZelefinActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ActivityPoster(attributes: attributes, state: state, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !attributes.subtitle.isEmpty {
                        Text(attributes.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if let percent = state.percentText, showsProgress(attributes.kind, state) {
                        Text(percent)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                if showsProgress(attributes.kind, state) {
                    ProgressView(value: state.clampedFraction)
                        .tint(statusColor(attributes.kind, state))
                }
                HStack(spacing: 6) {
                    if let badge = state.badgeLabel, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(attributes.kind, state), in: Capsule())
                    }
                    Text(state.statusLine)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
    }
}

/// Back-compat name used by older previews / docs.
typealias DownloadLockScreenView = ZelefinLockScreenActivityView

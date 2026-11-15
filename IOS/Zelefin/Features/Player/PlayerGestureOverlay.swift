import SwiftUI
import UIKit

/// Full-screen MPV touch layer: single tap toggles chrome, double-tap skips, edge pans adjust brightness/volume.
struct PlayerGestureOverlay: View {
    var model: PlayerModel
    var controlsVisible: Bool
    var onToggleControls: () -> Void
    /// When true, vertical pans that begin in the bottom chrome band are ignored.
    var bottomChromeHeight: CGFloat

    @State private var skipFlash: SkipFlash?
    @State private var hud: GestureHUD?
    @State private var panStartVolume: Float = 1
    @State private var panStartBrightness: CGFloat = 0.5
    @State private var activePan: PanKind?
    @State private var skipFlashTask: Task<Void, Never>?
    @State private var hudTask: Task<Void, Never>?

    private enum PanKind {
        case brightness
        case volume
    }

    private struct SkipFlash: Equatable {
        enum Side { case backward, forward }
        var side: Side
        var seconds: Int
        var token: UUID = UUID()
    }

    private struct GestureHUD: Equatable {
        enum Kind { case brightness, volume }
        var kind: Kind
        var value: Double
        var token: UUID = UUID()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            flashSkip(side: .backward)
                        }
                        .onTapGesture(count: 1) {
                            onToggleControls()
                        }
                        .simultaneousGesture(edgePan(kind: .brightness, height: geo.size.height))

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            flashSkip(side: .forward)
                        }
                        .onTapGesture(count: 1) {
                            onToggleControls()
                        }
                        .simultaneousGesture(edgePan(kind: .volume, height: geo.size.height))
                }

                if let skipFlash {
                    skipFlashOverlay(skipFlash, in: geo.size)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let hud {
                    sideHUD(hud, in: geo.size)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    private func edgePan(kind: PanKind, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                #if targetEnvironment(macCatalyst)
                if kind == .brightness { return }
                #endif
                if controlsVisible, value.startLocation.y > height - bottomChromeHeight {
                    return
                }
                // Prefer vertical pans; ignore mostly-horizontal scrub attempts.
                if abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                    return
                }
                if activePan == nil {
                    activePan = kind
                    panStartVolume = model.volume
                    #if !targetEnvironment(macCatalyst)
                    panStartBrightness = UIScreen.main.brightness
                    #endif
                }
                guard activePan == kind else { return }
                let delta = -value.translation.height / max(height, 1)
                switch kind {
                case .brightness:
                    #if !targetEnvironment(macCatalyst)
                    let next = min(1, max(0, panStartBrightness + delta))
                    UIScreen.main.brightness = next
                    showHUD(.init(kind: .brightness, value: Double(next)))
                    #endif
                case .volume:
                    let next = min(1, max(0, panStartVolume + Float(delta)))
                    model.setVolumeLevel(next)
                    showHUD(.init(kind: .volume, value: Double(next)))
                }
            }
            .onEnded { _ in
                activePan = nil
            }
    }

    private func flashSkip(side: SkipFlash.Side) {
        let seconds: Int
        switch side {
        case .backward:
            seconds = Int(PlaybackPreferences.skipBackward.rounded())
            model.skip(by: -PlaybackPreferences.skipBackward)
        case .forward:
            seconds = Int(PlaybackPreferences.skipForward.rounded())
            model.skip(by: PlaybackPreferences.skipForward)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let flash = SkipFlash(side: side, seconds: seconds)
        withAnimation(.easeOut(duration: 0.12)) {
            skipFlash = flash
        }
        skipFlashTask?.cancel()
        skipFlashTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                if skipFlash?.token == flash.token {
                    skipFlash = nil
                }
            }
        }
    }

    private func showHUD(_ next: GestureHUD) {
        withAnimation(.easeOut(duration: 0.1)) {
            hud = next
        }
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                if hud?.token == next.token {
                    hud = nil
                }
            }
        }
    }

    /// Side skip cue: `+N` / `-N` with a chevron — no wash circle.
    @ViewBuilder
    private func skipFlashOverlay(_ flash: SkipFlash, in size: CGSize) -> some View {
        let isForward = flash.side == .forward
        let label = isForward ? "+\(flash.seconds)" : "-\(flash.seconds)"
        let edgeInset = max(48, size.width * 0.12)

        HStack(spacing: 6) {
            if !isForward {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
            }
            Text(label)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if isForward {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isForward ? .trailing : .leading)
        .padding(.horizontal, edgeInset)
    }

    private func sideHUD(_ hud: GestureHUD, in size: CGSize) -> some View {
        let edgeInset = max(28, size.width * 0.05)
        return HStack {
            if hud.kind == .brightness {
                gestureHUD(hud)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                gestureHUD(hud)
            }
        }
        .padding(.horizontal, edgeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: controlsVisible ? -28 : 0)
    }

    /// Borderless vertical icon + fill bar (no chrome plate).
    private func gestureHUD(_ hud: GestureHUD) -> some View {
        let volumeIcon: String = {
            if hud.value <= 0.001 { return "speaker.slash.fill" }
            if hud.value < 0.34 { return "speaker.wave.1.fill" }
            if hud.value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }()
        return VStack(spacing: 12) {
            Image(systemName: hud.kind == .brightness ? "sun.max.fill" : volumeIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .frame(height: 28)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                Capsule()
                    .fill(Color.white)
                    .frame(height: 120 * hud.value)
            }
            .frame(width: 4, height: 120)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }
}

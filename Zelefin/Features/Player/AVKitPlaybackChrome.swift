import AVKit
import SwiftUI
import UIKit

/// Fullscreen chrome that follows AVPlayerViewController: xmark, AirPlay, PiP, ellipsis,
/// skip ±10, play/pause, elapsed / scrubber / remaining, auto-hide while playing.
struct AVKitPlaybackChrome: View {
    var model: PlayerModel
    let title: String
    var onClose: () -> Void

    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var hideGeneration = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleControls)

            dimming

            if controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    centerTransport
                    Spacer()
                    AVKitTimelineChrome(
                        model: model,
                        isScrubbing: $isScrubbing,
                        scrubTime: $scrubTime,
                        onSeekEnded: { time in
                            model.seek(to: time)
                            revealControls()
                        }
                    )
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.opacity)
            }

            if let title = model.skipPrompt?.title {
                skipIntro(title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, horizontalPadding)
                    .padding(.bottom, controlsVisible ? 88 : 28)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .task(id: hideTaskID) {
            await hideControlsIfPlaying()
        }
        .onChange(of: model.isPaused) { _, paused in
            if paused {
                revealControls()
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            model.togglePlayPause()
            revealControls()
        }
        #endif
    }

    private var hideTaskID: String {
        "\(hideGeneration)-\(controlsVisible)-\(model.isPaused)-\(isScrubbing)"
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        48
        #else
        horizontalSizeClass == .regular ? 28 : 16
        #endif
    }

    @ViewBuilder
    private var dimming: some View {
        LinearGradient(
            colors: [Color.black.opacity(controlsVisible ? 0.28 : 0), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 140)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)

        LinearGradient(
            colors: [.clear, Color.black.opacity(controlsVisible ? 0.32 : 0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 180)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            iconButton("xmark", label: "Close", size: 17) {
                onClose()
            }
            Spacer(minLength: 8)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 1)
            Spacer(minLength: 8)
            HStack(spacing: 16) {
                AirPlayRouteButton()
                    .frame(width: 44, height: 44)
                    .avkitGlassCircle()
                    .accessibilityLabel("AirPlay")
                if model.canUsePictureInPicture {
                    iconButton("pip.enter", label: "Picture in Picture", size: 18) {
                        model.togglePictureInPicture()
                    }
                }
                iconButton(
                    model.fillsScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: model.fillsScreen ? "Fit to screen" : "Fill screen",
                    size: 16
                ) {
                    model.toggleFillScreen()
                    revealControls()
                }
                AVKitPlaybackSettingsMenu(model: model)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 4)
    }

    private var centerTransport: some View {
        HStack(spacing: skipSpacing) {
            iconButton("gobackward.10", label: "Skip back 10 seconds", size: skipSymbolSize, hit: skipHitSize) {
                skip(by: -AVKitPlaybackSpeed.skipInterval)
            }
            Button {
                model.togglePlayPause()
                revealControls()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: playSymbolSize, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: playHitSize, height: playHitSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .avkitGlassCircle()
            .accessibilityLabel(model.isPaused ? "Play" : "Pause")
            iconButton("goforward.10", label: "Skip forward 10 seconds", size: skipSymbolSize, hit: skipHitSize) {
                skip(by: AVKitPlaybackSpeed.skipInterval)
            }
        }
    }

    private var skipSpacing: CGFloat {
        #if os(tvOS)
        72
        #else
        horizontalSizeClass == .regular ? 64 : 44
        #endif
    }

    private var skipSymbolSize: CGFloat {
        #if os(tvOS)
        32
        #else
        26
        #endif
    }

    private var skipHitSize: CGFloat {
        #if os(tvOS)
        72
        #else
        56
        #endif
    }

    private var playSymbolSize: CGFloat {
        #if os(tvOS)
        40
        #else
        28
        #endif
    }

    private var playHitSize: CGFloat {
        #if os(tvOS)
        88
        #else
        72
        #endif
    }

    private func skipIntro(_ title: String) -> some View {
        Button(title) {
            model.skipCurrentSegment()
            revealControls()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .avkitGlassCapsule()
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        size: CGFloat,
        hit: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: hit, height: hit)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .avkitGlassCircle()
        .accessibilityLabel(label)
    }

    private func skip(by interval: TimeInterval) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        model.skip(by: interval)
        revealControls()
    }

    private func toggleControls() {
        if controlsVisible {
            controlsVisible = false
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        controlsVisible = true
        hideGeneration += 1
    }

    private func hideControlsIfPlaying() async {
        guard controlsVisible, !model.isPaused, !isScrubbing else { return }
        do {
            try await Task.sleep(for: .seconds(5))
        } catch {
            return
        }
        guard !Task.isCancelled, !model.isPaused, !isScrubbing else { return }
        controlsVisible = false
    }
}

/// Isolated from the clock so the settings menu isn't rebuilt (and scrolled back) every tick.
private struct AVKitPlaybackSettingsMenu: View {
    var model: PlayerModel

    var body: some View {
        Menu {
            Section("Playback Speed") {
                ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
                    Button {
                        model.setPlaybackRate(rate)
                    } label: {
                        if abs(model.playbackRate - rate) < 0.01 {
                            Label(speedTitle(rate), systemImage: "checkmark")
                        } else {
                            Text(speedTitle(rate))
                        }
                    }
                }
            }
            if !model.audioOptions.isEmpty {
                Section("Audio") {
                    ForEach(model.audioOptions) { track in
                        Button {
                            model.selectAudio(id: track.id)
                        } label: {
                            if model.selectedAudioID == track.id {
                                Label(track.title, systemImage: "checkmark")
                            } else {
                                Text(track.title)
                            }
                        }
                    }
                }
            }
            Section("Subtitles") {
                Button {
                    model.selectSubtitle(id: nil)
                } label: {
                    if model.selectedSubtitleID == nil {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                ForEach(model.subtitleOptions) { track in
                    Button {
                        model.selectSubtitle(id: track.id)
                    } label: {
                        if model.selectedSubtitleID == track.id {
                            Label(track.title, systemImage: "checkmark")
                        } else {
                            Text(track.title)
                        }
                    }
                }
            }
            Section("Picture") {
                Button {
                    model.toggleFillScreen()
                } label: {
                    if model.fillsScreen {
                        Label("Fill screen", systemImage: "checkmark")
                    } else {
                        Text("Fill screen")
                    }
                }
            }
            Section("Stats") {
                Button {
                    model.togglePlaybackStats()
                } label: {
                    if model.showsPlaybackStats {
                        Label("Stats", systemImage: "checkmark")
                    } else {
                        Text("Stats")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .avkitGlassCircle()
        .accessibilityLabel("More")
    }

    private func speedTitle(_ rate: Float) -> String {
        if abs(rate - 1) < 0.01 { return "1x" }
        if rate == rate.rounded() {
            return "\(Int(rate))x"
        }
        return String(format: "%gx", rate)
    }
}

private struct AVKitTimelineChrome: View {
    var model: PlayerModel
    @Binding var isScrubbing: Bool
    @Binding var scrubTime: TimeInterval
    var onSeekEnded: (TimeInterval) -> Void

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubTime : model.currentTime
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(PlaybackTimeFormatting.elapsed(displayedTime))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 48, alignment: .leading)
            AVKitScrubber(
                value: displayedTime,
                duration: max(model.duration, 0.001),
                onEditingChanged: { editing, time in
                    isScrubbing = editing
                    scrubTime = time
                    if !editing {
                        onSeekEnded(time)
                    }
                }
            )
            .frame(height: 28)
            Text(PlaybackTimeFormatting.remaining(displayedTime, duration: model.duration))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .avkitGlassBar()
        .padding(.bottom, 8)
    }
}

/// Capsule timeline matching AVKit: thin until dragged, then a thicker white fill.
private struct AVKitScrubber: View {
    var value: TimeInterval
    var duration: TimeInterval
    var onEditingChanged: (_ editing: Bool, _ time: TimeInterval) -> Void

    @State private var dragTime: TimeInterval?
    @GestureState private var isDragging = false

    private var shown: TimeInterval {
        dragTime ?? value
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(1, max(0, shown / duration))
            let knobX = progress * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.32))
                    .frame(height: isDragging ? 8 : 5)
                Capsule()
                    .fill(.white)
                    .frame(width: max(4, knobX), height: isDragging ? 8 : 5)
                if isDragging {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: knobX - 8)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            #if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { gesture in
                        let fraction = min(1, max(0, gesture.location.x / width))
                        let time = fraction * duration
                        dragTime = time
                        onEditingChanged(true, time)
                    }
                    .onEnded { gesture in
                        let fraction = min(1, max(0, gesture.location.x / width))
                        let time = fraction * duration
                        dragTime = nil
                        onEditingChanged(false, time)
                    }
            )
            #endif
            .animation(.easeInOut(duration: 0.12), value: isDragging)
            .accessibilityLabel("Timeline")
            .accessibilityValue(PlaybackTimeFormatting.elapsed(shown))
        }
    }
}

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = true
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.backgroundColor = .clear
        picker.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            picker.widthAnchor.constraint(equalToConstant: 24),
            picker.heightAnchor.constraint(equalToConstant: 24)
        ])
        return host
    }

    func updateUIView(_: UIView, context _: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView _: UIView, context _: Context) -> CGSize {
        CGSize(width: 44, height: 44)
    }
}

private extension View {
    /// Clear glass over video, matching AVPlayerViewController on iOS 26.
    @ViewBuilder
    func avkitGlassCircle() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            self.glassEffect(.clear.interactive(), in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    func avkitGlassCapsule() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            self.glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
        } else {
            avkitMaterialCapsule()
        }
    }

    /// Timeline is dragged, not pressed — skip the interactive press bounce.
    @ViewBuilder
    func avkitGlassBar() -> some View {
        if #available(iOS 26, tvOS 26, *) {
            self.glassEffect(.clear, in: Capsule(style: .continuous))
        } else {
            avkitMaterialCapsule()
        }
    }

    private func avkitMaterialCapsule() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
    }
}

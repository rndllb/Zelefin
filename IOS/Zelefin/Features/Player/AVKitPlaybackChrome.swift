import AVKit
import SwiftUI
import UIKit

/// Fullscreen chrome that follows AVPlayerViewController: xmark, AirPlay, PiP, ellipsis,
/// skip, play/pause, elapsed / scrubber / remaining, auto-hide while playing.
struct AVKitPlaybackChrome: View {
    var model: PlayerModel
    let title: String
    var quality: PlaybackQuality
    var canAddSubtitles: Bool
    var onClose: () -> Void
    var onQualityChange: (PlaybackQuality) -> Void
    var onAddSubtitles: () -> Void
    var onAudioChange: (Int) -> Void
    var onSubtitleChange: (Int?) -> Void
    var onSkipCinema: (() -> Void)? = nil

    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var hideGeneration = 0
    @State private var settingsOpen = false
    @State private var settingsPage: AVKitPlaybackSettingsPage = .root
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
                    Spacer(minLength: 12)
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
                .padding(.bottom, 2)
                .transition(.opacity)
            }

            if let onSkipCinema {
                skipIntro("Skip", action: onSkipCinema)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, horizontalPadding)
                    .padding(.bottom, controlsVisible ? 64 : 10)
            } else if let title = model.skipPrompt?.title {
                skipIntro(title, action: {
                    model.skipCurrentSegment()
                    revealControls()
                })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, horizontalPadding)
                    .padding(.bottom, controlsVisible ? 64 : 10)
            }

            if settingsOpen {
                settingsScrim
                AVKitPlaybackSettingsPanel(
                    model: model,
                    page: $settingsPage,
                    quality: quality,
                    canAddSubtitles: canAddSubtitles,
                    onClose: closeSettings,
                    onQualityChange: { value in
                        onQualityChange(value)
                    },
                    onAddSubtitles: {
                        closeSettings()
                        onAddSubtitles()
                    },
                    onAudioChange: onAudioChange,
                    onSubtitleChange: onSubtitleChange
                )
                .padding(.trailing, horizontalPadding)
                .padding(.top, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
    }

    private var hideTaskID: String {
        "\(hideGeneration)-\(controlsVisible)-\(model.isPaused)-\(isScrubbing)-\(settingsOpen)"
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 16
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
                AVKitPlaybackSettingsMenuButton(isOpen: settingsOpen, action: toggleSettings)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 4)
    }

    private var centerTransport: some View {
        HStack(spacing: skipSpacing) {
            iconButton(
                PlaybackSkipInterval.resolved(Int(PlaybackPreferences.skipBackward)).backwardSymbol,
                label: "Skip back \(Int(PlaybackPreferences.skipBackward)) seconds",
                size: skipSymbolSize,
                hit: skipHitSize
            ) {
                skip(by: -PlaybackPreferences.skipBackward)
            }
            Button {
                model.togglePlayPause()
                revealControls()
            } label: {
                ZStack {
                    if model.isBuffering {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: playSymbolSize, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: playHitSize, height: playHitSize)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .avkitGlassCircle()
            .accessibilityLabel(model.isBuffering ? "Loading" : (model.isPaused ? "Play" : "Pause"))
            iconButton(
                PlaybackSkipInterval.resolved(Int(PlaybackPreferences.skipForward)).forwardSymbol,
                label: "Skip forward \(Int(PlaybackPreferences.skipForward)) seconds",
                size: skipSymbolSize,
                hit: skipHitSize
            ) {
                skip(by: PlaybackPreferences.skipForward)
            }
        }
    }

    private var skipSpacing: CGFloat {
        horizontalSizeClass == .regular ? 64 : 44
    }

    private var skipSymbolSize: CGFloat {
        26
    }

    private var skipHitSize: CGFloat {
        56
    }

    private var playSymbolSize: CGFloat {
        28
    }

    private var playHitSize: CGFloat {
        72
    }

    private func skipIntro(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
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

    private var settingsScrim: some View {
        Color.black.opacity(0.28)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: closeSettings)
    }

    private func skip(by interval: TimeInterval) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.skip(by: interval)
        revealControls()
    }

    private func toggleControls() {
        if settingsOpen {
            closeSettings()
            return
        }
        if controlsVisible {
            controlsVisible = false
        } else {
            revealControls()
        }
    }

    private func toggleSettings() {
        if settingsOpen {
            closeSettings()
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        settingsPage = .root
        settingsOpen = true
        revealControls()
    }

    private func closeSettings() {
        settingsOpen = false
        settingsPage = .root
        revealControls()
    }

    private func revealControls() {
        controlsVisible = true
        hideGeneration += 1
    }

    private func hideControlsIfPlaying() async {
        guard PlaybackChromeIdlePolicy.shouldHide(
            controlsVisible: controlsVisible,
            isPaused: model.isPaused,
            isScrubbing: isScrubbing,
            settingsOpen: settingsOpen
        ) else { return }
        do {
            try await Task.sleep(for: .seconds(5))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        guard PlaybackChromeIdlePolicy.shouldHide(
            controlsVisible: controlsVisible,
            isPaused: model.isPaused,
            isScrubbing: isScrubbing,
            settingsOpen: settingsOpen
        ) else { return }
        controlsVisible = false
    }
}

/// Isolated from the clock so the settings panel isn't rebuilt (and scrolled back) every tick.
private enum AVKitPlaybackSettingsPage: Equatable {
    case root
    case quality
    case speed
    case audio
    case subtitles
    case chapters
    case sleepTimer
}

private struct AVKitPlaybackSettingsMenuButton: View {
    var isOpen: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .avkitGlassCircle()
        .accessibilityLabel("More")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

private struct AVKitPlaybackSettingsPanel: View {
    var model: PlayerModel
    @Binding var page: AVKitPlaybackSettingsPage
    var quality: PlaybackQuality
    var canAddSubtitles: Bool
    var onClose: () -> Void
    var onQualityChange: (PlaybackQuality) -> Void
    var onAddSubtitles: () -> Void
    var onAudioChange: ((Int) -> Void)? = nil
    var onSubtitleChange: ((Int?) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            ScrollView {
                VStack(spacing: 0) {
                    switch page {
                    case .root: rootRows
                    case .quality: qualityRows
                    case .speed: speedRows
                    case .audio: audioRows
                    case .subtitles: subtitleRows
                    case .chapters: chapterRows
                    case .sleepTimer: sleepTimerRows
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 420)
        .foregroundStyle(.white)
        .avkitSettingsCard()
        .accessibilityLabel("Playback settings")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if page != .root {
                Button(action: { page = .root }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch page {
        case .root: "More"
        case .quality: "Quality"
        case .speed: "Playback Speed"
        case .audio: "Select Audio"
        case .subtitles: "Select Subtitles"
        case .chapters: "Chapters"
        case .sleepTimer: "Sleep Timer"
        }
    }

    @ViewBuilder
    private var rootRows: some View {
        settingsRow(
            title: "Quality",
            value: quality.title,
            systemImage: "slider.horizontal.3"
        ) {
            page = .quality
        }
        settingsRow(
            title: "Playback Speed",
            value: AVKitPlaybackSpeed.title(model.playbackRate),
            systemImage: "gauge.with.needle"
        ) {
            page = .speed
        }
        settingsRow(
            title: "Select Audio",
            value: selectedAudioTitle,
            systemImage: "waveform"
        ) {
            page = .audio
        }
        settingsRow(
            title: "Select Subtitles",
            value: selectedSubtitleTitle,
            systemImage: "captions.bubble"
        ) {
            page = .subtitles
        }
        if !model.plan.chapters.isEmpty {
            settingsRow(
                title: "Chapters",
                value: "\(model.plan.chapters.count)",
                systemImage: "list.bullet"
            ) {
                page = .chapters
            }
        }
        if !model.plan.isLive {
            settingsRow(
                title: "Sleep Timer",
                value: sleepTimerValue,
                systemImage: "moon.zzz"
            ) {
                page = .sleepTimer
            }
        }
        if canAddSubtitles {
            Button(action: onAddSubtitles) {
                rowLabel(title: "Add Subtitles", value: nil, systemImage: "plus.bubble", showsChevron: false)
            }
            .buttonStyle(.plain)
        }
        Button {
            model.toggleFillScreen()
        } label: {
            rowLabel(
                title: "Fill screen",
                value: model.fillsScreen ? "On" : "Off",
                systemImage: "arrow.up.left.and.arrow.down.right",
                showsChevron: false,
                selected: model.fillsScreen
            )
        }
        .buttonStyle(.plain)
        Button {
            model.togglePlaybackStats()
        } label: {
            rowLabel(
                title: "Stats",
                value: model.showsPlaybackStats ? "On" : "Off",
                systemImage: "info.circle",
                showsChevron: false,
                selected: model.showsPlaybackStats
            )
        }
        .buttonStyle(.plain)
    }

    private var chapterRows: some View {
        ForEach(model.plan.chapters) { chapter in
            choiceRow(
                "\(PlaybackTimeFormatting.elapsed(chapter.startTime))  \(chapter.name)",
                selected: false
            ) {
                model.seek(to: chapter.startTime)
                onClose()
            }
        }
    }

    private static let sleepTimerOptions: [SleepTimerMode] = [
        .off, .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfEpisode
    ]

    private var sleepTimerRows: some View {
        ForEach(Self.sleepTimerOptions, id: \.self) { option in
            choiceRow(sleepTimerLabel(option), selected: model.sleepTimer == option) {
                model.setSleepTimer(option)
                onClose()
            }
        }
    }

    private var sleepTimerValue: String {
        switch model.sleepTimer {
        case .off:
            return "Off"
        case .endOfEpisode:
            return "End of Episode"
        case .minutes:
            if let remaining = model.sleepTimerRemaining {
                return PlaybackTimeFormatting.elapsed(remaining)
            }
            return "On"
        }
    }

    private func sleepTimerLabel(_ mode: SleepTimerMode) -> String {
        switch mode {
        case .off: return "Off"
        case .endOfEpisode: return "End of Episode"
        case let .minutes(minutes): return "\(minutes) minutes"
        }
    }

    private var qualityRows: some View {
        ForEach(PlaybackQuality.allCases) { option in
            choiceRow(option.title, selected: option == quality) {
                onQualityChange(option)
            }
        }
    }

    private var speedRows: some View {
        ForEach(AVKitPlaybackSpeed.options, id: \.self) { rate in
            choiceRow(AVKitPlaybackSpeed.title(rate), selected: abs(model.playbackRate - rate) < 0.01) {
                model.setPlaybackRate(rate)
            }
        }
    }

    @ViewBuilder
    private var audioRows: some View {
        if model.audioOptions.isEmpty {
            Text("No audio tracks")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else {
            ForEach(model.audioOptions) { track in
                choiceRow(track.title, selected: model.selectedAudioID == track.id) {
                    if let onAudioChange {
                        onAudioChange(track.id)
                    } else {
                        model.selectAudio(id: track.id)
                    }
                }
            }
        }
    }

    private var subtitleRows: some View {
        Group {
            choiceRow("Off", selected: model.selectedSubtitleID == nil) {
                if let onSubtitleChange {
                    onSubtitleChange(nil)
                } else {
                    model.selectSubtitle(id: nil)
                }
            }
            ForEach(model.subtitleOptions) { track in
                choiceRow(track.title, selected: model.selectedSubtitleID == track.id) {
                    if let onSubtitleChange {
                        onSubtitleChange(track.id)
                    } else {
                        model.selectSubtitle(id: track.id)
                    }
                }
            }
            if canAddSubtitles {
                Button(action: onAddSubtitles) {
                    rowLabel(title: "Add Subtitles", value: nil, systemImage: "plus.bubble", showsChevron: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedAudioTitle: String {
        model.audioOptions.first(where: { $0.id == model.selectedAudioID })?.title ?? "Default"
    }

    private var selectedSubtitleTitle: String {
        guard let id = model.selectedSubtitleID else { return "Off" }
        return model.subtitleOptions.first(where: { $0.id == id })?.title ?? "On"
    }

    private func settingsRow(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(title: title, value: value, systemImage: systemImage, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(
        title: String,
        value: String?,
        systemImage: String,
        showsChevron: Bool,
        selected: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 22)
            Text(title)
                .font(.body)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct AVKitTimelineChrome: View {
    var model: PlayerModel
    @Binding var isScrubbing: Bool
    @Binding var scrubTime: TimeInterval
    var onSeekEnded: (TimeInterval) -> Void
    @Environment(SessionStore.self) private var session

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubTime : model.currentTime
    }

    var body: some View {
        VStack(spacing: 8) {
            if isScrubbing,
               let info = model.plan.trickplay,
               let url = session.library?.trickplayTileURL(
                    itemID: model.plan.item.id,
                    info: info,
                    time: displayedTime
               ) {
                TrickplayTilePreview(url: url, info: info, time: displayedTime)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 12) {
                Text(PlaybackTimeFormatting.elapsed(displayedTime))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 48, alignment: .leading)
                AVKitScrubber(
                    value: displayedTime,
                    duration: max(model.duration, 0.001),
                    chapters: model.plan.chapters,
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .avkitGlassBar()
    }
}

private struct TrickplayTilePreview: View {
    let url: URL
    let info: TrickplayInfo
    let time: TimeInterval

    var body: some View {
        let cell = info.cell(at: time)
        let thumbW = CGFloat(max(info.thumbnailWidth, 1))
        let thumbH = CGFloat(max(info.thumbnailHeight, 1))
        let tileW = thumbW * CGFloat(max(info.tileWidth, 1))
        let tileH = thumbH * CGFloat(max(info.tileHeight, 1))
        let previewW: CGFloat = 160
        let previewH = previewW * (thumbH / thumbW)
        AsyncImage(url: url) { image in
            image
                .resizable()
                .interpolation(.low)
                .frame(width: tileW, height: tileH, alignment: .topLeading)
                .offset(x: -CGFloat(cell.column) * thumbW, y: -CGFloat(cell.row) * thumbH)
                .frame(width: thumbW, height: thumbH, alignment: .topLeading)
                .clipped()
                .scaleEffect(previewW / thumbW, anchor: .topLeading)
                .frame(width: previewW, height: previewH, alignment: .topLeading)
                .clipped()
        } placeholder: {
            Color.white.opacity(0.12)
                .frame(width: previewW, height: previewH)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

/// Capsule timeline matching AVKit: thin until dragged, then a thicker white fill.
private struct AVKitScrubber: View {
    var value: TimeInterval
    var duration: TimeInterval
    var chapters: [MediaChapter] = []
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
                ForEach(chapters) { chapter in
                    let x = CGFloat(min(1, max(0, chapter.startTime / duration))) * width
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: 1.5, height: isDragging ? 10 : 7)
                        .offset(x: x)
                        .allowsHitTesting(false)
                }
                if isDragging {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: knobX - 8)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
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
    @ViewBuilder
    func avkitGlassCircle() -> some View {
        if #available(iOS 26, *) {
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
        if #available(iOS 26, *) {
            self.glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
        } else {
            avkitMaterialCapsule()
        }
    }

    /// Timeline is dragged, not pressed — skip the interactive press bounce.
    @ViewBuilder
    func avkitGlassBar() -> some View {
        if #available(iOS 26, *) {
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

    @ViewBuilder
    func avkitSettingsCard() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
        }
    }
}

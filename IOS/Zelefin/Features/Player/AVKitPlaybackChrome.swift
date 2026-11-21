import AVKit
import SwiftUI
import UIKit

/// SharePlay actions for the Watch Together menu.
struct AVKitSharePlayChrome {
    var isActive: Bool
    var title: String
    var onStart: () -> Void
    var onLeave: () -> Void
}

/// AirPlay / Chromecast / SharePlay / SyncPlay — one menu next to PiP.
struct AVKitWatchTogetherChrome {
    var onAirPlay: (() -> Void)? = nil
    var onCast: (() -> Void)? = nil
    var isCastConnected = false
    var castDeviceName: String? = nil
    var isAirPlaying = false
    var sharePlay: AVKitSharePlayChrome? = nil
    var syncPlayTitle: String? = nil
    var syncPlayIsActive = false
    var onSyncPlay: (() -> Void)? = nil

    var hasAnyOption: Bool {
        onAirPlay != nil
            || onCast != nil
            || sharePlay != nil
            || onSyncPlay != nil
    }

    /// Distinct from AirPlay / Cast / SharePlay row icons.
    var menuSymbol: String { "dot.radiowaves.left.and.right" }
}

/// Fullscreen chrome that follows AVPlayerViewController: xmark, PiP, ellipsis,
/// skip, play/pause, elapsed / scrubber / remaining, auto-hide while playing.
struct AVKitPlaybackChrome: View {
    var model: PlayerModel
    let title: String
    var quality: PlaybackQuality
    var canAddSubtitles: Bool
    var onClose: () -> Void
    var onQualityChange: (PlaybackQuality) -> Void
    var versions: [MediaVersion] = []
    var selectedVersionID: String? = nil
    var onVersionChange: (String) -> Void = { _ in }
    var onAddSubtitles: () -> Void
    var onAudioChange: (Int) -> Void
    var onSubtitleChange: (Int?) -> Void
    var onSkipCinema: (() -> Void)? = nil
    /// The next episode, for the N key. Nil when there's nothing after this.
    var onNext: (() -> Void)? = nil
    /// Off while something else (the subtitle search) has the keyboard.
    var keyboardEnabled = true
    var watchTogether: AVKitWatchTogetherChrome? = nil

    @State private var controlsVisible = true
    @State private var keyHint: String?
    @State private var keyHintGeneration = 0
    @State private var lastSubtitleID: Int?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var hideGeneration = 0
    @State private var settingsOpen = false
    @State private var settingsPage: AVKitPlaybackSettingsPage = .root
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geo in
            let panelCeiling = min(420, max(180, geo.size.height - 58 - (controlsVisible ? 88 : 16)))
            ZStack {
                PlayerGestureOverlay(
                    model: model,
                    controlsVisible: controlsVisible,
                    onToggleControls: toggleControls,
                    bottomChromeHeight: controlsVisible ? (120 + controlsBottomPadding) : 0
                )

                // Match Android: gesture skip / seek rebuffer keeps chrome hidden; only a spinner shows.
                if isWaiting && !controlsVisible {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.15)
                        .allowsHitTesting(false)
                }

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
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                            model.setControlsTop(top)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, controlsTopPadding)
                    .padding(.bottom, controlsBottomPadding)
                    .transition(.opacity)
                }

                if let onSkipCinema {
                    skipIntro("Skip", action: onSkipCinema)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, horizontalPadding)
                        .padding(.bottom, controlsVisible ? (64 + controlsBottomPadding) : (10 + controlsBottomPadding))
                } else if let title = model.skipPrompt?.title {
                    skipIntro(title, action: {
                        model.skipCurrentSegment()
                        revealControls()
                    })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, horizontalPadding)
                        .padding(.bottom, controlsVisible ? (64 + controlsBottomPadding) : (10 + controlsBottomPadding))
                }

                if settingsOpen {
                    settingsScrim
                    AVKitPlaybackSettingsPanel(
                        model: model,
                        page: $settingsPage,
                        quality: quality,
                        canAddSubtitles: canAddSubtitles,
                        maxHeight: panelCeiling,
                        onClose: closeSettings,
                        onQualityChange: { value in
                            onQualityChange(value)
                        },
                        versions: versions,
                        selectedVersionID: selectedVersionID,
                        onVersionChange: { id in
                            closeSettings()
                            onVersionChange(id)
                        },
                        onAddSubtitles: {
                            closeSettings()
                            onAddSubtitles()
                        },
                        onAudioChange: onAudioChange,
                        onSubtitleChange: onSubtitleChange
                    )
                    .padding(.trailing, horizontalPadding)
                    .padding(.top, controlsTopPadding + 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if let keyHint {
                    Text(keyHint)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .avkitGlassCapsule()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .background { if keyboardEnabled { keyboardControls } }
        .animation(.easeInOut(duration: 0.2), value: keyHint)
        .task(id: keyHintGeneration) {
            guard keyHint != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            keyHint = nil
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .onChange(of: controlsVisible) { _, visible in
            if !visible { model.setControlsTop(nil) }
        }
        .task(id: hideTaskID) {
            await hideControlsIfPlaying()
        }
        .onChange(of: model.isPaused) { _, paused in
            if paused {
                revealControls()
            }
        }
    }

    private var isWaiting: Bool {
        model.isBuffering || !model.hasFirstFrame
    }

    private var hideTaskID: String {
        "\(hideGeneration)-\(controlsVisible)-\(model.isPaused)-\(isScrubbing)-\(settingsOpen)-\(isWaiting)"
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 16
    }

    /// iPhone gets a home-indicator safe area; Mac Catalyst does not, so lift the scrubber by hand.
    private var controlsBottomPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        MacChromeMetrics.playerBottomInset
        #else
        2
        #endif
    }

    /// Mac traffic lights sit over the top of the window. The header row starts below them.
    private var controlsTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        MacChromeMetrics.playerTopInset
        #else
        8
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            iconButton("xmark", label: AppLanguage.string("common.close", default: "Close"), size: 17) {
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
                if let watchTogether, watchTogether.hasAnyOption {
                    watchTogetherMenu(watchTogether)
                }
                if model.canUsePictureInPicture {
                    iconButton("pip.enter", label: AppLanguage.string("ui.picture_in_picture", default: "Picture in Picture"), size: 18) {
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

    private func watchTogetherMenu(_ routes: AVKitWatchTogetherChrome) -> some View {
        Menu {
            if let onAirPlay = routes.onAirPlay {
                Button {
                    onAirPlay()
                    revealControls()
                } label: {
                    Label(
                        routes.isAirPlaying ? "AirPlay (Connected)" : "AirPlay",
                        systemImage: "airplayvideo"
                    )
                }
            }
            if let onCast = routes.onCast {
                Button {
                    onCast()
                    revealControls()
                } label: {
                    Label(
                        routes.isCastConnected
                            ? "Chromecast (\(routes.castDeviceName ?? "TV"))"
                            : "Chromecast",
                        systemImage: routes.isCastConnected ? "tv.fill" : "tv"
                    )
                }
            }
            if let sharePlay = routes.sharePlay {
                Button {
                    if sharePlay.isActive {
                        sharePlay.onLeave()
                    } else {
                        sharePlay.onStart()
                    }
                    revealControls()
                } label: {
                    Label(
                        sharePlay.title,
                        systemImage: sharePlay.isActive ? "shareplay.slash" : "shareplay"
                    )
                }
            }
            if let onSyncPlay = routes.onSyncPlay, let syncTitle = routes.syncPlayTitle {
                Button {
                    onSyncPlay()
                    revealControls()
                } label: {
                    Label(
                        syncTitle,
                        systemImage: routes.syncPlayIsActive ? "person.2.fill" : "person.2"
                    )
                }
            }
        } label: {
            Image(systemName: routes.menuSymbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tint(.white)
        .foregroundStyle(.white)
        .avkitGlassCircle()
        .accessibilityLabel(AppLanguage.string("player.watch_together", default: "Watch together"))
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
            .accessibilityLabel(model.isBuffering ? AppLanguage.string("common.loading", default: "Loading") : (model.isPaused ? AppLanguage.string("common.play", default: "Play") : AppLanguage.string("common.pause", default: "Pause")))
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

    /// The padding sits inside the button so the whole pill takes the tap. Outside it, only the words
    /// did; a tap on the rest of the pill fell through to the show/hide-controls layer behind it.
    private func skipIntro(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(Capsule())
        }
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
            guard !isWaiting else { return }
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

    // MARK: Keyboard

    /// Mac (and iPad keyboard) controls, laid out like other players': Space or K plays and
    /// pauses, the arrows skip and change volume, the number keys jump through the runtime.
    /// Hidden buttons carry the shortcuts, so they work wherever the player has the window and
    /// iPad lists them when Command is held. The arrows go to [ArrowKeyCommands] instead.
    private var keyboardControls: some View {
        ZStack {
            ArrowKeyCommands(
                onLeft: { skip(by: -PlaybackPreferences.skipBackward) },
                onRight: { skip(by: PlaybackPreferences.skipForward) },
                onUp: { changeVolume(by: 0.1) },
                onDown: { changeVolume(by: -0.1) }
            )
            keyButton(AppLanguage.string("player.play_or_pause", default: "Play or Pause"), .space, action: playPauseFromKeyboard)
            keyButton(AppLanguage.string("player.play_or_pause", default: "Play or Pause"), "k", action: playPauseFromKeyboard)
            keyButton(AppLanguage.string("player.skip_back", default: "Skip Back"), "j") { skip(by: -PlaybackPreferences.skipBackward) }
            keyButton(AppLanguage.string("player.skip_forward", default: "Skip Forward"), "l") { skip(by: PlaybackPreferences.skipForward) }
            keyButton(AppLanguage.string("player.mute", default: "Mute"), "m", action: toggleMute)
            keyButton(AppLanguage.string("player.subtitles", default: "Subtitles"), "c", action: toggleSubtitles)
            keyButton(AppLanguage.string("player.slower", default: "Slower"), "[") { stepSpeed(by: -1) }
            keyButton(AppLanguage.string("player.faster", default: "Faster"), "]") { stepSpeed(by: 1) }
            keyButton(AppLanguage.string("player.fillcreen", default: "Fill or Fit"), "z") {
                model.toggleFillScreen()
                showHint(model.fillsScreen ? "Fill Screen" : "Fit to Screen")
            }
            keyButton(AppLanguage.string("player.playback_info", default: "Playback Info"), "i") { model.togglePlaybackStats() }
            keyButton(AppLanguage.string("player.skip_intro", default: "Skip Intro"), "s", action: skipFromKeyboard)
            keyButton(AppLanguage.string("player.skip_intro", default: "Skip Intro"), .return, action: skipFromKeyboard)
            if let onNext {
                keyButton(AppLanguage.string("player.next_episode", default: "Next Episode"), "n", action: onNext)
            }
            keyButton(AppLanguage.string("common.close", default: "Close"), .escape, action: escapeFromKeyboard)
            ForEach(0 ..< 10, id: \.self) { digit in
                keyButton("Jump to \(digit * 10)%", KeyEquivalent(Character(String(digit)))) {
                    model.seek(toFraction: Double(digit) / 10)
                    revealControls()
                }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func keyButton(
        _ title: String,
        _ key: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: [])
    }

    private func playPauseFromKeyboard() {
        model.togglePlayPause()
        revealControls()
    }

    private func changeVolume(by delta: Float) {
        model.adjustVolume(by: delta)
        showHint(model.isMuted ? "Muted" : "Volume \(Int((model.volume * 100).rounded()))%")
    }

    private func toggleMute() {
        model.setMuted(!model.isMuted)
        showHint(model.isMuted ? "Muted" : "Volume \(Int((model.volume * 100).rounded()))%")
    }

    /// Off, or back to the last track used (the first one if none was).
    private func toggleSubtitles() {
        if let current = model.selectedSubtitleID {
            lastSubtitleID = current
            onSubtitleChange(nil)
            showHint("Subtitles Off")
            return
        }
        let options = model.subtitleOptions
        guard let pick = options.first(where: { $0.id == lastSubtitleID }) ?? options.first else {
            showHint("No Subtitles")
            return
        }
        onSubtitleChange(pick.id)
        showHint(pick.title)
    }

    private func stepSpeed(by step: Int) {
        let options = AVKitPlaybackSpeed.options
        let current = options.firstIndex { abs($0 - model.playbackRate) < 0.01 }
            ?? options.firstIndex { $0 >= model.playbackRate }
            ?? options.count - 1
        let next = options[min(max(current + step, 0), options.count - 1)]
        model.setPlaybackRate(next)
        showHint(AVKitPlaybackSpeed.title(next))
    }

    private func skipFromKeyboard() {
        if let onSkipCinema {
            onSkipCinema()
        } else if model.skipPrompt != nil {
            model.skipCurrentSegment()
            revealControls()
        }
    }

    /// Esc steps back one level: the settings panel first, then the player itself.
    private func escapeFromKeyboard() {
        if settingsOpen {
            closeSettings()
        } else {
            onClose()
        }
    }

    private func showHint(_ text: String) {
        keyHint = text
        keyHintGeneration += 1
    }

    private func hideControlsIfPlaying() async {
        guard PlaybackChromeIdlePolicy.shouldHide(
            controlsVisible: controlsVisible,
            isPaused: model.isPaused,
            isScrubbing: isScrubbing,
            settingsOpen: settingsOpen,
            isBuffering: isWaiting
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
            settingsOpen: settingsOpen,
            isBuffering: isWaiting
        ) else { return }
        controlsVisible = false
    }
}

/// The player's arrow keys. UIKit gives arrows to focus and scrolling before any shortcut, so
/// SwiftUI's `keyboardShortcut` never sees them; a key command that asks for priority does. It
/// works from the first responder, so this view takes it while the player is on screen.
private struct ArrowKeyCommands: UIViewRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void

    func makeUIView(context: Context) -> ArrowKeyView { ArrowKeyView() }

    func updateUIView(_ view: ArrowKeyView, context: Context) {
        view.handlers = [
            UIKeyCommand.inputLeftArrow: onLeft,
            UIKeyCommand.inputRightArrow: onRight,
            UIKeyCommand.inputUpArrow: onUp,
            UIKeyCommand.inputDownArrow: onDown,
        ]
        view.claimKeyboard()
    }

    static func dismantleUIView(_ view: ArrowKeyView, coordinator: ()) {
        if view.isFirstResponder { view.resignFirstResponder() }
    }
}

private final class ArrowKeyView: UIView {
    var handlers: [String: () -> Void] = [:]

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        handlers.keys.map { input in
            let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(arrow(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func arrow(_ command: UIKeyCommand) {
        command.input.flatMap { handlers[$0] }?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimKeyboard()
    }

    /// Taken back after a menu or sheet had it.
    func claimKeyboard() {
        guard window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }
}

/// Isolated from the clock so the settings panel isn't rebuilt (and scrolled back) every tick.
private enum AVKitPlaybackSettingsPage: Equatable {
    case root
    case quality
    case version
    case speed
    case audio
    case subtitles
    case subtitleStyle
    case subtitleSync
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
        .accessibilityLabel(AppLanguage.string("common.more", default: "More"))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

private struct AVKitPlaybackSettingsPanel: View {
    var model: PlayerModel
    @Binding var page: AVKitPlaybackSettingsPage
    var quality: PlaybackQuality
    var canAddSubtitles: Bool
    var maxHeight: CGFloat = 420
    var onClose: () -> Void
    var onQualityChange: (PlaybackQuality) -> Void
    var versions: [MediaVersion] = []
    var selectedVersionID: String? = nil
    var onVersionChange: (String) -> Void = { _ in }
    var onAddSubtitles: () -> Void
    var onAudioChange: ((Int) -> Void)? = nil
    var onSubtitleChange: ((Int?) -> Void)? = nil
    // Read through @AppStorage so a tap re-renders the checkmarks; the static getters are invisible to SwiftUI.
    @AppStorage(SubtitleAppearance.sizeKey) private var sizeRaw = SubtitleAppearance.Size.medium.rawValue
    @AppStorage(SubtitleAppearance.colorKey) private var colorRaw = SubtitleAppearance.TextColor.white.rawValue
    @AppStorage(SubtitleAppearance.backgroundKey) private var backgroundRaw = SubtitleAppearance.Background.dropShadow.rawValue
    @AppStorage(SubtitleAppearance.syncKey) private var syncSeconds = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            ScrollView {
                VStack(spacing: 0) {
                    switch page {
                    case .root: rootRows
                    case .quality: qualityRows
                    case .version: versionRows
                    case .speed: speedRows
                    case .audio: audioRows
                    case .subtitles: subtitleRows
                    case .subtitleStyle: subtitleStyleRows
                    case .subtitleSync: subtitleSyncRows
                    case .chapters: chapterRows
                    case .sleepTimer: sleepTimerRows
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: maxHeight, alignment: .top)
        .foregroundStyle(.white)
        .avkitSettingsCard()
        .accessibilityLabel(AppLanguage.string("player.playback_settings", default: "Playback settings"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if page != .root {
                Button(action: { page = .root }) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.string("common.back", default: "Back"))
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
            .accessibilityLabel(AppLanguage.string("common.close", default: "Close"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch page {
        case .root: AppLanguage.string("common.more", default: "More")
        case .quality: "Quality"
        case .version: "Version"
        case .speed: "Playback Speed"
        case .audio: "Select Audio"
        case .subtitles: "Select Subtitles"
        case .subtitleStyle: "Subtitle Style"
        case .subtitleSync: "Subtitle Sync"
        case .chapters: "Chapters"
        case .sleepTimer: "Sleep Timer"
        }
    }

    @ViewBuilder
    private var rootRows: some View {
        settingsRow(
            title: AppLanguage.string("player.quality", default: "Quality"),
            value: quality.title,
            systemImage: "slider.horizontal.3"
        ) {
            page = .quality
        }
        if versions.count > 1 {
            settingsRow(
                title: AppLanguage.string("settings.version", default: "Version"),
                value: selectedVersion?.title ?? "Default",
                systemImage: "square.stack"
            ) {
                page = .version
            }
        }
        settingsRow(
            title: AppLanguage.string("player.playback_speed", default: "Playback Speed"),
            value: AVKitPlaybackSpeed.title(model.playbackRate),
            systemImage: "gauge.with.needle"
        ) {
            page = .speed
        }
        settingsRow(
            title: AppLanguage.string("player.select_audio", default: "Select Audio"),
            value: selectedAudioTitle,
            systemImage: "waveform"
        ) {
            page = .audio
        }
        settingsRow(
            title: AppLanguage.string("player.select_subtitles", default: "Select Subtitles"),
            value: selectedSubtitleTitle,
            systemImage: "captions.bubble"
        ) {
            page = .subtitles
        }
        settingsRow(
            title: AppLanguage.string("player.subtitle_style", default: "Subtitle Style"),
            value: SubtitleAppearance.size.title,
            systemImage: "textformat.size"
        ) {
            page = .subtitleStyle
        }
        settingsRow(
            title: AppLanguage.string("player.subtitle_sync", default: "Subtitle Sync"),
            value: SubtitleAppearance.syncTitle(),
            systemImage: "clock.arrow.2.circlepath"
        ) {
            page = .subtitleSync
        }
        if !model.plan.chapters.isEmpty {
            settingsRow(
                title: AppLanguage.string("player.chapters", default: "Chapters"),
                value: "\(model.plan.chapters.count)",
                systemImage: "list.bullet"
            ) {
                page = .chapters
            }
        }
        if !model.plan.isLive {
            settingsRow(
                title: AppLanguage.string("player.sleep_timer", default: "Sleep Timer"),
                value: sleepTimerValue,
                systemImage: "moon.zzz"
            ) {
                page = .sleepTimer
            }
        }
        Button {
            model.toggleFillScreen()
        } label: {
            rowLabel(
                title: AppLanguage.string("ui.fill_screen", default: "Fill screen"),
                value: model.fillsScreen ? AppLanguage.string("common.on", default: "On") : AppLanguage.string("player.subtitles_off", default: "Off"),
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
                title: AppLanguage.string("ui.stats", default: "Stats"),
                value: model.showsPlaybackStats ? AppLanguage.string("common.on", default: "On") : AppLanguage.string("player.subtitles_off", default: "Off"),
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

    private var selectedVersion: MediaVersion? {
        versions.first { $0.id == selectedVersionID } ?? versions.first
    }

    private var versionRows: some View {
        ForEach(versions) { version in
            Button {
                onVersionChange(version.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(version.title)
                            .font(.body)
                            .lineLimit(2)
                        if let detail = version.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if version.id == selectedVersion?.id {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(version.id == selectedVersion?.id ? .isSelected : [])
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
            Text(AppLanguage.string("player.no_audio", default: "No audio tracks"))
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
            if canAddSubtitles {
                Button(action: onAddSubtitles) {
                    rowLabel(title: AppLanguage.string("search.add_subtitles", default: "Add Subtitles"), value: nil, systemImage: "plus.bubble", showsChevron: false)
                }
                .buttonStyle(.plain)
            }
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
        }
    }

    @ViewBuilder
    private var subtitleStyleRows: some View {
        menuSection(AppLanguage.string("player.font_size", default: "Font Size"))
        ForEach(SubtitleAppearance.Size.allCases) { option in
            choiceRow(option.title, selected: (SubtitleAppearance.Size(rawValue: sizeRaw) ?? .medium) == option) {
                sizeRaw = option.rawValue
                model.applySubtitleAppearance()
            }
        }
        if model.showsPictureSubtitles {
            Text(AppLanguage.string("player.image_subtitles_note", default: "These subtitles are pictures (PGS or VobSub), so only their size can change."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            textLookRows
        }
    }

    @ViewBuilder
    private var textLookRows: some View {
        menuSection(AppLanguage.string("player.text_color", default: "Text Color"))
        ForEach(SubtitleAppearance.TextColor.allCases) { option in
            choiceRow(option.title, selected: (SubtitleAppearance.TextColor(rawValue: colorRaw) ?? .white) == option) {
                colorRaw = option.rawValue
                model.applySubtitleAppearance()
            }
        }
        menuSection(AppLanguage.string("player.background", default: "Background"))
        ForEach(SubtitleAppearance.Background.allCases) { option in
            choiceRow(option.title, selected: (SubtitleAppearance.Background(rawValue: backgroundRaw) ?? .dropShadow) == option) {
                backgroundRaw = option.rawValue
                model.applySubtitleAppearance()
            }
        }
    }

    private func menuSection(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private var subtitleSyncRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SubtitleAppearance.syncTitle(syncSeconds))
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Button("−0.25") {
                    syncSeconds = SubtitleAppearance.snappedSync(syncSeconds - SubtitleAppearance.syncStep)
                    model.applySubtitleAppearance()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12), in: Capsule())
                Button("+0.25") {
                    syncSeconds = SubtitleAppearance.snappedSync(syncSeconds + SubtitleAppearance.syncStep)
                    model.applySubtitleAppearance()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            Slider(
                value: Binding(
                    get: { syncSeconds },
                    set: {
                        syncSeconds = SubtitleAppearance.snappedSync($0)
                        model.applySubtitleAppearance()
                    }
                ),
                in: SubtitleAppearance.syncRange,
                step: SubtitleAppearance.syncStep
            )
            .tint(.white)
            Button(AppLanguage.string("common.reset", default: "Reset")) {
                syncSeconds = 0
                model.applySubtitleAppearance()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                Image(systemName: "chevron.forward")
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
            } else if isScrubbing, model.plan.trickplay == nil, let url = model.plan.bifPreviewURL {
                BIFFramePreview(url: url, time: displayedTime)
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
                    bufferedAhead: model.bufferedAheadSeconds,
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

/// One frame cut from an Emby BIF. Nothing shows when the server has not generated thumbnails.
private struct BIFFramePreview: View {
    let url: URL
    let time: TimeInterval
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.low)
                    .scaledToFit()
                    .frame(width: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                    }
            }
        }
        .task(id: Int(time)) {
            if let frame = await BIFPreviewStore.shared.image(url: url, at: time) {
                image = frame
            }
        }
        .accessibilityHidden(true)
    }
}

/// Capsule timeline matching AVKit: thin until dragged, then a thicker white fill.
/// A secondary darker fill shows how far media is buffered ahead of the playhead.
private struct AVKitScrubber: View {
    var value: TimeInterval
    var duration: TimeInterval
    var bufferedAhead: TimeInterval = 0
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
            let buffered = min(1, max(progress, (shown + max(0, bufferedAhead)) / duration))
            let trackHeight: CGFloat = isDragging ? 8 : 5
            let knobX = progress * width
            let bufferedWidth = buffered * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: trackHeight)
                // Loaded ahead of (and under) the playhead — slightly darker than the played fill.
                Capsule()
                    .fill(.white.opacity(0.42))
                    .frame(width: max(4, bufferedWidth), height: trackHeight)
                Capsule()
                    .fill(.white)
                    .frame(width: max(4, knobX), height: trackHeight)
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
            .accessibilityLabel(AppLanguage.string("player.timeline", default: "Timeline"))
            .accessibilityValue(PlaybackTimeFormatting.elapsed(shown))
        }
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

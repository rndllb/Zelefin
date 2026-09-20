import JellyfinAPI
import SwiftUI

struct SessionsView: View {
    @Environment(SessionStore.self) private var session

    @State private var sessions: [PlaybackSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var playing: [PlaybackSession] { sessions.filter(\.isPlaying) }
    private var idle: [PlaybackSession] { sessions.filter { !$0.isPlaying } }

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "play.tv",
                    description: Text(errorMessage ?? "No one is connected to this server right now.")
                )
            } else {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    }
                    if !playing.isEmpty {
                        Section("Now Playing") {
                            ForEach(playing) { item in
                                NavigationLink {
                                    SessionDetailView(sessionID: item.id)
                                } label: {
                                    SessionRow(item: item, localDeviceID: session.session?.deviceID)
                                        .settingsLoginCard()
                                }
                                .settingsCardRow()
                            }
                        }
                    }
                    if !idle.isEmpty {
                        Section("Connected") {
                            ForEach(idle) { item in
                                NavigationLink {
                                    SessionDetailView(sessionID: item.id)
                                } label: {
                                    SessionRow(item: item, localDeviceID: session.session?.deviceID)
                                        .settingsLoginCard()
                                }
                                .settingsCardRow()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(showProgress: false) }
            }
        }
        .zelefinSettingsChrome(title: "Sessions")
        .task { await monitor() }
    }

    private func monitor() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await load(showProgress: false)
        }
    }

    private func load(showProgress: Bool = true) async {
        guard let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in to see sessions."
            return
        }
        if showProgress, sessions.isEmpty { isLoading = true }
        do {
            sessions = try await library.playbackSessions()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if sessions.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

private struct SessionRow: View {
    @Environment(SessionStore.self) private var session
    let item: PlaybackSession
    var localDeviceID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            poster
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .lineLimit(2)
                Text(item.userLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LoginPalette.secondaryText)
                    .lineLimit(1)
                Text(deviceCaption)
                    .font(.caption)
                    .foregroundStyle(LoginPalette.captionText)
                    .lineLimit(2)
                if item.isPlaying {
                    HStack(spacing: 8) {
                        Text(item.methodLabel)
                        if item.isPaused { Text("Paused") }
                        Text(item.positionLabel)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LoginPalette.captionText)
                    if item.runtime != nil {
                        ProgressView(value: item.progressFraction)
                            .tint(AccentPreferences.current)
                    }
                }
            }
            SettingsChevron()
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var deviceCaption: String {
        var parts = [item.deviceLabel]
        if item.isThisDevice(localDeviceID) { parts.append("This device") }
        if let type = item.deviceType, !type.isEmpty { parts.append(type) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        [item.userLabel, item.title, item.deviceLabel, item.isPlaying ? item.methodLabel : "Idle"]
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var poster: some View {
        if item.isPlaying {
            PosterImage(
                url: item.nowPlaying.flatMap { session.library?.primaryURL(for: $0) },
                aspectRatio: 2 / 3,
                fill: Color.white.opacity(0.08)
            )
            .frame(width: 52, height: 78)
            .posterCard(cornerRadius: 10)
        } else {
            UserAvatarView(
                url: item.userID.flatMap { session.library?.userAvatarURL(userID: $0, tag: item.userImageTag) },
                diameter: 48
            )
        }
    }
}

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var session
    let sessionID: String

    @State private var item: PlaybackSession?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        Group {
            if let item {
                List {
                    Section {
                        header(item)
                            .settingsHeroRow()
                    }
                    if item.isPlaying {
                        Section("Playback") {
                            playbackCard(item)
                                .settingsCardRow()
                        }
                    }
                    Section("Device") {
                        deviceCard(item)
                            .settingsCardRow()
                    }
                    if let transcoding = item.transcoding {
                        Section("Transcoding") {
                            transcodingCard(transcoding)
                                .settingsCardRow()
                        }
                    }
                    if item.canControl, item.isPlaying {
                        Section("Controls") {
                            SessionControlBar(item: item, isBusy: isBusy, send: send)
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    } else if item.isPlaying {
                        Section {
                            SettingsStatusText(text: "This client does not accept remote control.")
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    }
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                                .settingsLoginCard()
                                .settingsCardRow()
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if errorMessage != nil {
                ContentUnavailableView(
                    "Session Unavailable",
                    systemImage: "play.tv",
                    description: Text(errorMessage ?? "")
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .zelefinSettingsChrome(title: item?.userLabel ?? "Session")
        .task { await monitor() }
    }

    private func header(_ item: PlaybackSession) -> some View {
        VStack(spacing: 18) {
            if item.isPlaying {
                PosterImage(
                    url: item.nowPlaying.flatMap { session.library?.primaryURL(for: $0) },
                    aspectRatio: 2 / 3,
                    fill: Color.white.opacity(0.08)
                )
                .frame(width: 96, height: 144)
                .posterCard(cornerRadius: 16)
            } else {
                UserAvatarView(
                    url: item.userID.flatMap { session.library?.userAvatarURL(userID: $0, tag: item.userImageTag) },
                    diameter: 132
                )
                .padding(6)
                .zelefinLiquidGlassCircle(interactive: false)
                .frame(width: 144, height: 144)
            }

            VStack(spacing: 10) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                SettingsChip(
                    icon: item.isThisDevice(session.session?.deviceID) ? "iphone" : "tv",
                    leading: item.isPlaying ? (item.isPaused ? "Paused" : "Playing") : "Connected",
                    trailing: item.deviceLabel
                )
            }

            if item.isPlaying {
                VStack(spacing: 8) {
                    ProgressView(value: item.progressFraction)
                        .tint(AccentPreferences.current)
                    Text(item.positionLabel)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(LoginPalette.captionText)
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playbackCard(_ item: PlaybackSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInfoRow(label: "Status", value: item.isPaused ? "Paused" : "Playing")
            SettingsCardDivider()
            SettingsInfoRow(label: "Method", value: item.methodLabel)
            SettingsCardDivider()
            SettingsInfoRow(label: "Position", value: item.positionLabel)
            if let volume = item.volumeLevel {
                SettingsCardDivider()
                SettingsInfoRow(label: "Volume", value: item.isMuted ? "Muted (\(volume)%)" : "\(volume)%")
            }
        }
        .settingsLoginCard()
    }

    private func deviceCard(_ item: PlaybackSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsInfoRow(label: "User", value: item.userLabel)
            if !item.client.isEmpty {
                SettingsCardDivider()
                SettingsInfoRow(label: "Client", value: item.client)
            }
            if !item.deviceName.isEmpty {
                SettingsCardDivider()
                SettingsInfoRow(label: "Device", value: item.deviceName)
            }
            if let type = item.deviceType, !type.isEmpty {
                SettingsCardDivider()
                SettingsInfoRow(label: "Type", value: type)
            }
            if let version = item.applicationVersion, !version.isEmpty {
                SettingsCardDivider()
                SettingsInfoRow(label: "Version", value: version)
            }
            if let ip = item.remoteEndPoint, !ip.isEmpty {
                SettingsCardDivider()
                SettingsInfoRow(label: "IP", value: ip)
            }
            if item.isThisDevice(session.session?.deviceID) {
                SettingsCardDivider()
                SettingsInfoRow(label: "Session", value: "This device")
            }
        }
        .settingsLoginCard()
    }

    private func transcodingCard(_ transcoding: TranscodingSummary) -> some View {
        let rows: [(String, String)] = [
            transcoding.codecLine.map { ("Stream", $0) },
            transcoding.resolutionLabel.map { ("Resolution", $0) },
            transcoding.bitrateLabel.map { ("Bitrate", $0) },
            transcoding.reasonsLabel.map { ("Reason", $0) },
            transcoding.completionPercentage.map { ("Complete", String(format: "%.0f%%", $0)) }
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { SettingsCardDivider() }
                SettingsInfoRow(label: row.0, value: row.1)
            }
        }
        .settingsLoginCard()
    }

    private func monitor() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func refresh() async {
        guard let library = session.jellyfinLibrary else { return }
        do {
            let latest = try await library.playbackSessions()
            if let match = latest.first(where: { $0.id == sessionID }) {
                item = match
                errorMessage = nil
            } else if item == nil {
                errorMessage = "This session is no longer active."
            }
        } catch is CancellationError {
            return
        } catch {
            if item == nil { errorMessage = error.localizedDescription }
        }
    }

    private func send(_ action: SessionControlAction) async {
        guard let library = session.jellyfinLibrary, let current = item else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch action {
            case .playstate(let command, let seek):
                try await library.sendPlaystate(sessionID: current.id, command: command, seekPosition: seek)
            case .command(let command):
                try await library.sendSessionCommand(sessionID: current.id, command: command)
            }
            errorMessage = nil
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SessionControlAction {
    case playstate(PlaystateCommand, seek: TimeInterval? = nil)
    case command(GeneralCommandType)
}

private struct SessionControlBar: View {
    let item: PlaybackSession
    var isBusy: Bool
    var send: (SessionControlAction) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                control("backward.end.fill", "Previous") {
                    await send(.playstate(.previousTrack))
                }
                control(item.isPaused ? "play.fill" : "pause.fill", item.isPaused ? "Play" : "Pause") {
                    await send(.playstate(item.isPaused ? .unpause : .pause))
                }
                control("stop.fill", "Stop") {
                    await send(.playstate(.stop))
                }
                control("forward.end.fill", "Next") {
                    await send(.playstate(.nextTrack))
                }
            }
            .frame(maxWidth: .infinity)
            if item.canSeek {
                HStack(spacing: 18) {
                    control("gobackward.10", "Back 10 seconds") {
                        await send(.playstate(.seek, seek: max(0, item.position - 10)))
                    }
                    control("goforward.10", "Forward 10 seconds") {
                        let end = item.runtime ?? (item.position + 10)
                        await send(.playstate(.seek, seek: min(end, item.position + 10)))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if supportsVolume {
                HStack(spacing: 18) {
                    control("speaker.minus.fill", "Volume down") {
                        await send(.command(.volumeDown))
                    }
                    control(item.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", item.isMuted ? "Unmute" : "Mute") {
                        await send(.command(item.isMuted ? .unmute : .mute))
                    }
                    control("speaker.plus.fill", "Volume up") {
                        await send(.command(.volumeUp))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
    }

    private var supportsVolume: Bool {
        let names = item.supportedCommands
        return names.contains(GeneralCommandType.volumeUp.rawValue)
            || names.contains(GeneralCommandType.mute.rawValue)
            || names.contains(GeneralCommandType.toggleMute.rawValue)
    }

    private func control(_ systemImage: String, _ label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LoginPalette.primaryText)
                .frame(width: 48, height: 48)
                .zelefinLiquidGlassCircle()
        }
        .accessibilityLabel(label)
    }
}

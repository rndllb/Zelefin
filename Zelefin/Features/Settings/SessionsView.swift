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
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                    if !playing.isEmpty {
                        Section("Now Playing") {
                            ForEach(playing) { item in
                                NavigationLink {
                                    SessionDetailView(sessionID: item.id)
                                } label: {
                                    SessionRow(item: item, localDeviceID: session.session?.deviceID)
                                }
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
                                }
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
        guard let library = session.library else {
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
        HStack(alignment: .top, spacing: 12) {
            poster
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.userLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text(deviceCaption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
                if item.isPlaying {
                    HStack(spacing: 8) {
                        Text(item.methodLabel)
                        if item.isPaused { Text("Paused") }
                        Text(item.positionLabel)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    if item.runtime != nil {
                        ProgressView(value: item.progressFraction)
                            .tint(.white)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
            .posterCard(cornerRadius: 6)
        } else {
            UserAvatarView(
                url: item.userID.flatMap { session.library?.userAvatarURL(userID: $0, tag: item.userImageTag) },
                diameter: 40
            )
            .padding(.top, 4)
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
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    if item.isPlaying {
                        Section("Playback") {
                            LabeledContent("Status", value: item.isPaused ? "Paused" : "Playing")
                            LabeledContent("Method", value: item.methodLabel)
                            LabeledContent("Position", value: item.positionLabel)
                            if let volume = item.volumeLevel {
                                LabeledContent("Volume", value: item.isMuted ? "Muted (\(volume)%)" : "\(volume)%")
                            }
                        }
                    }
                    Section("Device") {
                        LabeledContent("User", value: item.userLabel)
                        if !item.client.isEmpty {
                            LabeledContent("Client", value: item.client)
                        }
                        if !item.deviceName.isEmpty {
                            LabeledContent("Device", value: item.deviceName)
                        }
                        if let type = item.deviceType, !type.isEmpty {
                            LabeledContent("Type", value: type)
                        }
                        if let version = item.applicationVersion, !version.isEmpty {
                            LabeledContent("Version", value: version)
                        }
                        if let ip = item.remoteEndPoint, !ip.isEmpty {
                            LabeledContent("IP", value: ip)
                        }
                        if item.isThisDevice(session.session?.deviceID) {
                            LabeledContent("Session", value: "This device")
                        }
                    }
                    if let transcoding = item.transcoding {
                        Section("Transcoding") {
                            if let codecs = transcoding.codecLine {
                                LabeledContent("Stream", value: codecs)
                            }
                            if let resolution = transcoding.resolutionLabel {
                                LabeledContent("Resolution", value: resolution)
                            }
                            if let bitrate = transcoding.bitrateLabel {
                                LabeledContent("Bitrate", value: bitrate)
                            }
                            if let reasons = transcoding.reasonsLabel {
                                LabeledContent("Reason", value: reasons)
                            }
                            if let percent = transcoding.completionPercentage {
                                LabeledContent("Complete", value: String(format: "%.0f%%", percent))
                            }
                        }
                    }
                    if item.canControl, item.isPlaying {
                        Section("Controls") {
                            SessionControlBar(item: item, isBusy: isBusy, send: send)
                        }
                    } else if item.isPlaying {
                        Section {
                            Text("This client does not accept remote control.")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
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
        HStack(alignment: .top, spacing: 16) {
            PosterImage(
                url: item.nowPlaying.flatMap { session.library?.primaryURL(for: $0) },
                aspectRatio: 2 / 3,
                fill: Color.white.opacity(0.08)
            )
            .frame(width: 92, height: 138)
            .posterCard()
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(item.deviceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                if item.isPlaying {
                    ProgressView(value: item.progressFraction)
                        .tint(.white)
                    Text(item.positionLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
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
        guard let library = session.library else { return }
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
        guard let library = session.library, let current = item else { return }
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
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

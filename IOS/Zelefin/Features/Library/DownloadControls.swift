import SwiftUI

struct DownloadCoverBadge: View {
    let item: MediaItem
    var padded = true
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    var body: some View {
        let mark = downloads.coverMark(for: item, account: session.session)
        let transfer = downloads.transfer(for: item, account: session.session)
        ZStack {
            if case .downloading = mark, let transfer {
                Color.black.opacity(0.35)
                DownloadProgressMeter(progress: transfer, compact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if case .downloaded = mark {
                downloadedMark
            }
        }
        .allowsHitTesting(false)
    }

    private var downloadedMark: some View {
        Image(systemName: "arrow.down.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.78))
            .font(.system(size: markSize, weight: .semibold))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            .padding(padded ? markPadding : 0)
            .accessibilityLabel("Downloaded")
    }

    private var markSize: CGFloat {
        22
    }

    private var markPadding: CGFloat {
        8
    }
}

struct DownloadProgressMeter: View {
    let progress: DownloadProgress
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            DownloadProgressRing(
                fraction: progress.fraction,
                isDeterminate: progress.isDeterminate,
                size: compact ? 36 : 44
            )
            Text(compact ? compactLabel : progress.sizeLabel)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 12)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Downloading")
        .accessibilityValue(progress.percentLabel ?? progress.sizeLabel)
    }

    private var compactLabel: String {
        progress.percentLabel ?? progress.sizeLabel
    }
}

struct DownloadProgressRing: View {
    var fraction: Double
    var isDeterminate: Bool
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 3.5)
            if isDeterminate {
                Circle()
                    .trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((min(1, max(0, fraction)) * 100).rounded()))")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(size < 40 ? 0.7 : 0.85)
            }
        }
        .frame(width: size, height: size)
    }
}

struct DownloadStatusBanner: View {
    let item: MediaItem
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    var body: some View {
        if let progress = downloads.transfer(for: item, account: session.session) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.bannerTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(progress.sizeLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Button("Cancel") {
                        downloads.cancelTransfer(for: item, account: session.session)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }

                downloadTrack(progress)
            }
            .frame(maxWidth: 300)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(progress.bannerTitle)
            .accessibilityValue(progress.sizeLabel)
            .accessibilityAction(named: "Cancel") {
                downloads.cancelTransfer(for: item, account: session.session)
            }
        }
    }

    @ViewBuilder
    private func downloadTrack(_ progress: DownloadProgress) -> some View {
        if progress.isDeterminate {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, progress.fraction)))))
                }
            }
            .frame(height: 4)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.white)
        }
    }
}

struct DetailDownloadSharePill: View {
    let item: MediaItem
    var seasons: [MediaItem] = []
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?
    @State private var removalPrompt: DownloadRemovalPrompt?
    @State private var showsSeasonPicker = false
    @State private var showsYouTubePicker = false

    var body: some View {
        let state: DownloadControlState = (session.usesSilo && !session.downloadsAvailable)
            ? .unavailable
            : downloads.control(for: item, episodes: episodes, account: session.session)
        let transfer = downloads.transfer(for: item, account: session.session)
        ZelefinGlassPillCluster {
            ZelefinPillIconSegment(
                accessibilityLabel: title(for: state),
                isEnabled: state != .unavailable,
                action: { Task { await run() } }
            ) {
                switch state {
                case .downloading:
                    DownloadProgressRing(
                        fraction: transfer?.fraction ?? 0,
                        isDeterminate: transfer?.isDeterminate ?? false,
                        size: 22
                    )
                default:
                    Image(systemName: symbol(for: state))
                        .font(.system(size: ZelefinPillMetrics.iconPointSize, weight: .semibold))
                        .imageScale(.medium)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                }
            }
            ZelefinGlassPillDivider()
            ZelefinPillIconSegment(
                accessibilityLabel: "Share",
                action: share
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: ZelefinPillMetrics.iconPointSize, weight: .semibold))
                    .imageScale(.medium)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
        }
        .alert("Download", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .downloadRemovalConfirmation($removalPrompt) {
            downloads.removeDownloaded(item: item, episodes: episodes, account: session.session)
        }
        .popover(isPresented: $showsSeasonPicker) {
            ShowDownloadSeasonsMenu(
                choices: SeasonDownloadChoice.options(seasons: seasons, episodes: episodes),
                onCancel: { showsSeasonPicker = false },
                onConfirm: { indexes in
                    showsSeasonPicker = false
                    Task { await download(indexes: indexes) }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
        .popover(isPresented: $showsYouTubePicker) {
            YouTubeDownloadMenu(
                videos: episodes,
                onCancel: { showsYouTubePicker = false },
                onDownload: { picked in
                    showsYouTubePicker = false
                    Task { await enqueue(picked) }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func share() {
        guard let serverURL = session.session?.serverURL else { return }
        let payload = TitleShare.make(
            item: item,
            serverURL: serverURL,
            serverName: session.serverName ?? session.session?.serverName
        )
        TitleSharePresenter.present(payload)
    }

    private func run() async {
        switch downloads.control(for: item, episodes: episodes, account: session.session) {
        case .unavailable:
            return
        case .downloading:
            downloads.pauseTransfer(for: item, account: session.session)
        case .downloaded:
            let target = DownloadEligibility.playableItem(from: item, episodes: episodes) ?? item
            removalPrompt = .make(item: target)
        case .idle:
            await startDownload()
        }
    }

    private func startDownload() async {
        if item.isYouTube && item.kind == .series {
            if episodes.count > 1 {
                showsYouTubePicker = true
                return
            }
            await enqueue(episodes)
            return
        }
        if item.kind == .series {
            let choices = SeasonDownloadChoice.options(seasons: seasons, episodes: episodes)
            if choices.count > 1 {
                showsSeasonPicker = true
                return
            }
            await download(choices.first)
            return
        }
        if item.kind == .season, !episodes.isEmpty {
            await download(SeasonDownloadChoice(title: item.seasonMenuTitle, seasonIndex: item.resolvedSeasonNumber))
            return
        }
        do {
            try await downloads.toggle(
                item: item,
                episodes: episodes,
                library: session.library,
                account: session.session
            )
        } catch {
            guard !DownloadFailure.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ choice: SeasonDownloadChoice?) async {
        let selected = choice.map { SeasonDownloadChoice.episodes(for: $0, in: episodes, seasons: seasons) } ?? episodes
        await enqueue(selected)
    }

    private func download(indexes: Set<Int>) async {
        await enqueue(SeasonDownloadChoice.episodes(in: episodes, seasons: seasons, indexes: indexes))
    }

    private func enqueue(_ targets: [MediaItem]) async {
        guard !targets.isEmpty else { return }
        do {
            try await downloads.downloadMany(items: targets, library: session.library, account: session.session)
        } catch {
            guard !DownloadFailure.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func title(for state: DownloadControlState) -> String {
        DownloadControlCopy.title(for: state)
    }

    private func symbol(for state: DownloadControlState) -> String {
        DownloadControlCopy.symbol(for: state)
    }
}

private struct ShowDownloadSeasonsMenu: View {
    let choices: [SeasonDownloadChoice]
    var onCancel: () -> Void
    var onConfirm: (Set<Int>) -> Void
    @State private var selected: Set<Int> = []

    private var indexes: Set<Int> {
        Set(choices.compactMap(\.seasonIndex))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        selected = selected == indexes ? [] : indexes
                    } label: {
                        seasonRow(title: "Select All", isOn: !indexes.isEmpty && selected == indexes)
                    }
                    .buttonStyle(.plain)
                    ForEach(choices) { choice in
                        if let number = choice.seasonIndex {
                            Button {
                                if selected.contains(number) {
                                    selected.remove(number)
                                } else {
                                    selected.insert(number)
                                }
                            } label: {
                                seasonRow(title: choice.title, isOn: selected.contains(number))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            Button(action: onCancel) {
                menuRow(title: "Cancel", systemImage: "xmark", color: .red)
            }
            .buttonStyle(.plain)
            Button {
                onConfirm(selected)
            } label: {
                menuRow(
                    title: "Download",
                    systemImage: "arrow.down.to.line",
                    color: .white,
                    enabled: !selected.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
        }
        .frame(width: 250)
        .padding(.vertical, 4)
        .preferredColorScheme(.dark)
    }

    private func seasonRow(title: String, isOn: Bool) -> some View {
        menuRow(title: title, systemImage: "checkmark", color: .white, showsLeading: isOn)
    }

    private func menuRow(
        title: String,
        systemImage: String,
        color: Color,
        showsLeading: Bool = true,
        enabled: Bool = true
    ) -> some View {
        let tint = color.opacity(enabled ? 1 : 0.4)
        return HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .opacity(showsLeading ? 1 : 0)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.body)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct YouTubeDownloadMenu: View {
    let videos: [MediaItem]
    var onCancel: () -> Void
    var onDownload: ([MediaItem]) -> Void

    private var unwatched: [MediaItem] {
        videos.filter { !$0.isWatched }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach([5, 10].filter { videos.count > $0 }, id: \.self) { count in
                Button {
                    onDownload(Array(videos.prefix(count)))
                } label: {
                    menuRow(title: "Latest \(count) Videos", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
            }
            if !unwatched.isEmpty, unwatched.count < videos.count {
                Button {
                    onDownload(unwatched)
                } label: {
                    menuRow(title: "Unwatched (\(unwatched.count))", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
            }
            if !videos.isEmpty {
                Button {
                    onDownload(videos)
                } label: {
                    menuRow(
                        title: videos.count == 1 ? "Download Video" : "All \(videos.count) Videos",
                        systemImage: "arrow.down.to.line"
                    )
                }
                .buttonStyle(.plain)
            }
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            Button(action: onCancel) {
                menuRow(title: "Cancel", systemImage: "xmark", color: .red)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 250)
        .padding(.vertical, 4)
        .preferredColorScheme(.dark)
    }

    private func menuRow(title: String, systemImage: String, color: Color = .white) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.body)
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct DownloadActionButton: View {
    let item: MediaItem
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?
    @State private var removalPrompt: DownloadRemovalPrompt?

    var body: some View {
        let state = downloads.control(for: item, episodes: episodes, account: session.session)
        Button {
            Task { await run() }
        } label: {
            Label(DownloadControlCopy.title(for: state), systemImage: DownloadControlCopy.symbol(for: state))
        }
        .disabled(state == .unavailable)
        .accessibilityLabel(DownloadControlCopy.title(for: state))
        .alert("Download", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .downloadRemovalConfirmation($removalPrompt) {
            downloads.removeDownloaded(item: item, episodes: episodes, account: session.session)
        }
    }

    private func run() async {
        switch downloads.control(for: item, episodes: episodes, account: session.session) {
        case .unavailable:
            return
        case .downloading:
            downloads.cancelTransfer(for: item, account: session.session)
        case .downloaded:
            let target = DownloadEligibility.playableItem(from: item, episodes: episodes) ?? item
            removalPrompt = .make(item: target)
        case .idle:
            do {
                try await downloads.toggle(
                    item: item,
                    episodes: episodes,
                    library: session.library,
                    account: session.session
                )
            } catch {
                guard !DownloadFailure.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DownloadRemovalConfirmation: ViewModifier {
    @Binding var prompt: DownloadRemovalPrompt?
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            prompt?.title ?? "Delete Download?",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { _ in
            Button("Delete", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }
}

extension View {
    func downloadRemovalConfirmation(
        _ prompt: Binding<DownloadRemovalPrompt?>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DownloadRemovalConfirmation(prompt: prompt, onConfirm: onConfirm))
    }
}

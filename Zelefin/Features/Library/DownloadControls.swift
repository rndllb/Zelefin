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
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
    @State private var errorMessage: String?
    @State private var removalPrompt: DownloadRemovalPrompt?

    var body: some View {
        let state = downloads.control(for: item, episodes: episodes, account: session.session)
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
            downloads.cancelTransfer(for: item, account: session.session)
        case .downloaded:
            let target = DownloadEligibility.playableItem(from: item, episodes: episodes) ?? item
            removalPrompt = .make(item: target)
        case .idle:
            guard plus.require(.downloads) else { return }
            await startDownload()
        }
    }

    private func startDownload() async {
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

    private func title(for state: DownloadControlState) -> String {
        DownloadControlCopy.title(for: state)
    }

    private func symbol(for state: DownloadControlState) -> String {
        DownloadControlCopy.symbol(for: state)
    }
}

struct DownloadActionButton: View {
    let item: MediaItem
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
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
            guard plus.require(.downloads) else { return }
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

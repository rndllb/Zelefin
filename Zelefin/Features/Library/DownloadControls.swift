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
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

    private var markPadding: CGFloat {
        #if os(tvOS)
        10
        #else
        8
        #endif
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
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session

    var body: some View {
        if let progress = downloads.transfer(for: item, account: session.session) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progress.percentLabel.map { "Downloading \($0)" } ?? "Downloading")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Button("Cancel") {
                        Task {
                            try? await downloads.toggle(
                                item: item,
                                episodes: episodes,
                                library: session.library,
                                account: session.session
                            )
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                }
                if progress.isDeterminate {
                    ProgressView(value: min(1, max(0, progress.fraction)))
                        .tint(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                Text(progress.sizeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: 420)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

struct DownloadActionButton: View {
    let item: MediaItem
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?

    var body: some View {
        let state = downloads.control(for: item, episodes: episodes, account: session.session)
        let transfer = downloads.transfer(for: item, account: session.session)
        Button {
            Task { await run() }
        } label: {
            switch state {
            case .downloading:
                DownloadProgressRing(
                    fraction: transfer?.fraction ?? 0,
                    isDeterminate: transfer?.isDeterminate ?? false,
                    size: 22
                )
            default:
                Label(title(for: state), systemImage: symbol(for: state))
            }
        }
        .disabled(state == .unavailable)
        .accessibilityLabel(title(for: state))
        .alert("Download", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run() async {
        do {
            try await downloads.toggle(
                item: item,
                episodes: episodes,
                library: session.library,
                account: session.session
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func title(for state: DownloadControlState) -> String {
        switch state {
        case .unavailable, .idle:
            "Download"
        case .downloading(let fraction):
            fraction > 0 ? "\(Int((fraction * 100).rounded()))%" : "Downloading"
        case .downloaded:
            "Remove Download"
        }
    }

    private func symbol(for state: DownloadControlState) -> String {
        switch state {
        case .unavailable, .idle:
            "arrow.down.to.line"
        case .downloading:
            "stop.circle"
        case .downloaded:
            "checkmark.circle.fill"
        }
    }
}

struct DownloadHeroButton: View {
    let item: MediaItem
    var episodes: [MediaItem] = []
    @Environment(DownloadStore.self) private var downloads
    @Environment(SessionStore.self) private var session
    @State private var errorMessage: String?

    var body: some View {
        let state = downloads.control(for: item, episodes: episodes, account: session.session)
        let transfer = downloads.transfer(for: item, account: session.session)
        Button {
            Task { await run() }
        } label: {
            Group {
                switch state {
                case .downloading:
                    DownloadProgressRing(
                        fraction: transfer?.fraction ?? 0,
                        isDeterminate: transfer?.isDeterminate ?? false,
                        size: 22
                    )
                case .downloaded:
                    Image(systemName: "checkmark.circle.fill")
                case .unavailable, .idle:
                    Image(systemName: "arrow.down.to.line")
                }
            }
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 45, height: 45)
            .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(state == .unavailable)
        .accessibilityLabel(accessibilityTitle(for: state))
        .alert("Download", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run() async {
        do {
            try await downloads.toggle(
                item: item,
                episodes: episodes,
                library: session.library,
                account: session.session
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accessibilityTitle(for state: DownloadControlState) -> String {
        switch state {
        case .unavailable, .idle:
            "Download"
        case .downloading(let fraction):
            fraction > 0 ? "Downloading \(Int((fraction * 100).rounded())) percent" : "Downloading"
        case .downloaded:
            "Remove Download"
        }
    }
}

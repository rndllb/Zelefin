import SwiftUI
import UIKit

/// Settings → Log: what Zelefin did and what went wrong, newest first, to read here or send on.
struct LogView: View {
    @Environment(SessionStore.self) private var session
    @State private var lines: [LogLine] = []
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var exportURL: URL?
    @State private var confirmsClear = false
    @State private var showsReportIssue = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case problems = "Problems"
        case errors = "Errors"

        var id: String { rawValue }
    }

    /// The newest this many lines; a full log is still in the shared file.
    private static let shownLimit = 3_000

    private var shown: [LogLine] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.filter { line in
            switch filter {
            case .all: break
            case .problems: guard line.level != .info else { return false }
            case .errors: guard line.level == .error else { return false }
            }
            return term.isEmpty || line.text.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        List {
            Section {
                Picker(AppLanguage.string("ui.show", default: "Show"), selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(AppLanguage.string("Zelefin notes what it does and what goes wrong: sign-ins, playback, downloads, and requests that fail. Passwords, tokens, and API keys are never written down. Report a problem to email help@randll.com or open a GitHub issue with the log attached.", default: "Zelefin notes what it does and what goes wrong: sign-ins, playback, downloads, and requests that fail. Passwords, tokens, and API keys are never written down. Report a problem to email help@randll.com or open a GitHub issue with the log attached."))
            }
            .zelefinRowBackground()

            Section {
                Button {
                    showsReportIssue = true
                } label: {
                    Label(AppLanguage.string("ui.report_issue", default: "Report Issue"), systemImage: "exclamationmark.bubble")
                }
            }
            .zelefinRowBackground()

            Section {
                if shown.isEmpty {
                    Text(lines.isEmpty ? AppLanguage.string("ui.nothing_logged_yet", default: "Nothing logged yet.") : "No entries match.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { line in
                        LogLineRow(line: line)
                    }
                }
            }
            .zelefinRowBackground()
        }
        .searchable(text: $search, prompt: "Search the log")
        .zelefinSettingsChrome(title: AppLanguage.string("settings.log", default: "Log"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsReportIssue = true
                } label: {
                    Image(systemName: "exclamationmark.bubble")
                }
                .accessibilityLabel(AppLanguage.string("ui.report_issue", default: "Report Issue"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(AppLanguage.string("ui.report_issue", default: "Report Issue"), systemImage: "exclamationmark.bubble") {
                        showsReportIssue = true
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label(AppLanguage.string("ui.send_log", default: "Send Log"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(AppLanguage.string("ui.copy_log", default: "Copy Log"), systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = ZelefinLog.header(session: session) + "\n\n" + ZelefinLog.shared.contents()
                    }
                    Button(AppLanguage.string("common.refresh", default: "Refresh"), systemImage: "arrow.clockwise", action: reload)
                    Divider()
                    Button(AppLanguage.string("ui.clear_log", default: "Clear Log"), systemImage: "trash", role: .destructive) {
                        confirmsClear = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Log actions")
            }
        }
        .confirmationDialog(AppLanguage.string("ui.clear_the_log", default: "Clear the log?"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(AppLanguage.string("ui.clear_log", default: "Clear Log"), role: .destructive) {
                ZelefinLog.shared.clear()
                ZelefinLog.info("Log", "Cleared the log")
                reload()
            }
        } message: {
            Text(AppLanguage.string("Everything Zelefin has noted so far is removed from this device.", default: "Everything Zelefin has noted so far is removed from this device."))
        }
        .sheet(isPresented: $showsReportIssue) {
            ReportIssueView()
        }
        .task { reload() }
        .refreshable { reload() }
    }

    private func reload() {
        let text = ZelefinLog.shared.contents()
        let parsed = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(Self.shownLimit)
        lines = parsed.enumerated().map { LogLine(index: $0.offset, raw: String($0.element)) }.reversed()
        exportURL = ZelefinLog.shared.exportFile(header: ZelefinLog.header(session: session))
    }
}

struct LogLine: Identifiable, Equatable {
    let id: Int
    let time: String
    let level: ZelefinLog.Level
    let category: String
    let message: String
    let text: String

    /// `2026-11-01 08:41:03.120 WARN [Network] GET host/path → 404`
    init(index: Int, raw: String) {
        id = index
        text = raw
        let parts = raw.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let level = ZelefinLog.Level(rawValue: String(parts[2])) else {
            time = ""
            self.level = .info
            category = ""
            message = raw
            return
        }
        // "11-01 08:41:03": the month and day, then the time to the second.
        time = "\(parts[0].dropFirst(5)) \(parts[1].prefix(8))"
        self.level = level
        let rest = parts[3]
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            category = String(rest[rest.index(after: rest.startIndex) ..< close])
            message = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
        } else {
            category = ""
            message = String(rest)
        }
    }
}

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(line.level.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                if !line.category.isEmpty {
                    Text(line.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(line.time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(line.message)
                .font(.footnote.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch line.level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

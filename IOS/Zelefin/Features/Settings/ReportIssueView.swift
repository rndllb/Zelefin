import SwiftUI
import UIKit

/// Compose a short problem report, then email help@randll.com and/or open a GitHub issue.
struct ReportIssueView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var summary = ""
    @State private var showsMailComposer = false
    @State private var mailFallbackNotice: String?
    @State private var exportURL: URL?

    private static let helpEmail = "help@randll.com"
    private static let githubNewIssueURL = URL(string: "https://github.com/rndllb/Zelefin/issues/new")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppLanguage.string("ui.whats_going_wrong", default: "What’s going wrong?"), text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text(AppLanguage.string("Describe the problem in a sentence or two. The device log and diagnostics are included automatically.", default: "Describe the problem in a sentence or two. The device log and diagnostics are included automatically."))
                }
                .zelefinRowBackground()

                Section {
                    Button {
                        emailSupport()
                    } label: {
                        Label("Email \(Self.helpEmail)", systemImage: "envelope")
                    }
                    .disabled(!canSubmit)

                    Button {
                        openGitHubIssue()
                    } label: {
                        Label(AppLanguage.string("ui.open_github_issue", default: "Open GitHub Issue"), systemImage: "link")
                    }
                    .disabled(!canSubmit)
                } footer: {
                    Text(AppLanguage.string("Email attaches the full log. GitHub opens a prefilled issue; attach the log there if the form is too short, or send it by email.", default: "Email attaches the full log. GitHub opens a prefilled issue; attach the log there if the form is too short, or send it by email."))
                }
                .zelefinRowBackground()

                if let mailFallbackNotice {
                    Section {
                        SettingsStatusText(text: mailFallbackNotice, isError: true)
                    }
                    .zelefinRowBackground()
                }
            }
            .zelefinSettingsChrome(title: AppLanguage.string("ui.report_issue", default: "Report Issue"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.string("common.close", default: "Close")) { dismiss() }
                }
            }
            .task {
                exportURL = ZelefinLog.shared.exportFile(header: ZelefinLog.header(session: session))
            }
            .sheet(isPresented: $showsMailComposer) {
                MailComposeView(
                    subject: mailSubject,
                    recipients: [Self.helpEmail],
                    body: mailBody,
                    attachmentURL: exportURL
                ) { _ in
                    showsMailComposer = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private var canSubmit: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mailSubject: String {
        "Zelefin issue: \(trimmedSummary)"
    }

    private var diagnostics: String {
        ZelefinLog.header(session: session)
    }

    private var mailBody: String {
        """
        \(trimmedSummary)

        ---
        \(diagnostics)
        """
    }

    private var githubBody: String {
        """
        ### Summary
        \(trimmedSummary)

        ### Diagnostics
        ```
        \(diagnostics)
        ```

        ### Steps to reproduce
        1.
        2.

        ### Expected
        -

        ### Actual
        -

        _Attach the Zelefin log from Settings → Log if you can._
        """
    }

    private func emailSupport() {
        mailFallbackNotice = nil
        if MailComposeView.canSendMail {
            showsMailComposer = true
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.helpEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: mailSubject),
            URLQueryItem(name: "body", value: String(mailBody.prefix(1_800))),
        ]
        if let url = components.url {
            openURL(url)
            mailFallbackNotice = "Mail isn’t set up on this device. A draft opened if possible — attach the log from Send Log."
        } else {
            mailFallbackNotice = "Mail isn’t set up on this device. Use Send Log, then email \(Self.helpEmail)."
        }
    }

    private func openGitHubIssue() {
        var components = URLComponents(url: Self.githubNewIssueURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: trimmedSummary),
            URLQueryItem(name: "body", value: String(githubBody.prefix(3_500))),
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}

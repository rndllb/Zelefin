import SwiftUI

/// Inline Quick Connect code entry for the root Settings list.
struct QuickConnectAuthorizeRows: View {
    @Environment(SessionStore.self) private var session
    @State private var code = ""
    @State private var isAuthorizing = false
    @State private var status: String?
    @State private var statusIsError = false

    var body: some View {
        TextField(AppLanguage.string("ui.quick_connect_code", default: "Quick Connect code"), text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(isAuthorizing)
        Button {
            Task { await authorize() }
        } label: {
            HStack {
                Text(isAuthorizing ? "Authorizing…" : "Authorize Quick Connect")
                if isAuthorizing {
                    Spacer(minLength: 8)
                    ProgressView()
                }
            }
        }
        .disabled(!canAuthorize || isAuthorizing)
        if let status {
            SettingsStatusText(text: status, isError: statusIsError)
        }
    }

    private var normalizedCode: String {
        code.filter(\.isNumber)
    }

    private var canAuthorize: Bool {
        normalizedCode.count >= 4
    }

    private func authorize() async {
        isAuthorizing = true
        status = nil
        defer { isAuthorizing = false }
        do {
            try await session.authorizeQuickConnect(code: normalizedCode)
            statusIsError = false
            status = "Authorized. The other device can finish signing in."
            code = ""
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }
}

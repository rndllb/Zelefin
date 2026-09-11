import SwiftUI

/// Sign-in canvas. The isometric Z leads; credentials sit in a single column under it.
struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("zelefin.last-server") private var address = ""
    @AppStorage("zelefin.last-username") private var username = ""
    @State private var password = ""
    @State private var gatewayClientID = AccessGateway.clientID
    @State private var gatewayClientSecret = AccessGateway.clientSecret
    @State private var isConnecting = false
    @State private var isCheckingConnection = false
    @State private var signInError: String?
    @State private var testMessage: String?
    @State private var testDidSucceed = false
    @State private var showsPasswordHelp = false
    @State private var showsAccessGateway = false
    @State private var quickConnectCode: String?
    @State private var isStartingQuickConnect = false
    @State private var quickConnectTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LoginPalette.canvas
                .ignoresSafeArea()

            markGlow

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandBlock
                        .padding(.top, horizontalSizeClass == .regular ? 56 : 28)
                        .padding(.bottom, 32)

                    credentialsCard
                        .padding(.bottom, 22)

                    statusText

                    VStack(spacing: 12) {
                        loginButton
                        testConnectionButton
                    }

                    if isUsingQuickConnect {
                        quickConnectPanel
                            .padding(.top, 22)
                    } else {
                        quickConnectButton
                            .padding(.top, 16)
                    }

                    if ReviewDemo.isEnabled {
                        reviewDemoButton
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26)
                .padding(.bottom, 44)
            }
        }
        .tint(AccentPreferences.current)
        .onDisappear { cancelQuickConnect() }
        .alert("Password help", isPresented: $showsPasswordHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reset your password in the Jellyfin web interface, or ask your server administrator.")
        }
    }

    // MARK: - Chrome

    private var markGlow: some View {
        GeometryReader { geo in
            let isPad = horizontalSizeClass == .regular
            let endRadius = isPad
                ? hypot(geo.size.width / 2, geo.size.height)
                : max(geo.size.width * 0.72, 220)

            RadialGradient(
                colors: [
                    LoginPalette.cyan.opacity(0.28),
                    LoginPalette.cobalt.opacity(0.16),
                    LoginPalette.canvas
                ],
                center: .top,
                startRadius: 12,
                endRadius: endRadius
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            ConnectBrandMark(size: horizontalSizeClass == .regular ? 196 : 168)
            VStack(spacing: 8) {
                Text("Zelefin")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text("Please sign in to continue.")
                    .font(.subheadline)
                    .foregroundStyle(LoginPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zelefin. Please sign in to continue.")
    }

    // MARK: - Fields

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            labeledField(label: "SERVER URL", systemImage: "link") {
                TextField(
                    "",
                    text: $address,
                    prompt: Text("https://jellyfin.example.com")
                        .foregroundStyle(Color.white.opacity(0.55))
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .tint(.white)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Server URL")
            }

            cardDivider

            labeledField(label: "USERNAME", systemImage: "person.fill") {
                TextField("Username", text: $username)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.fieldValue)
                    .tint(AccentPreferences.current)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            cardDivider

            passwordRow

            accessGatewaySection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoginPalette.divider, lineWidth: 1)
        )
        .onChange(of: gatewayClientID) { _, value in
            AccessGateway.clientID = value
        }
        .onChange(of: gatewayClientSecret) { _, value in
            AccessGateway.clientSecret = value
        }
    }

    @ViewBuilder
    private var accessGatewaySection: some View {
        DisclosureGroup("Advanced: access gateway") {
            accessGatewayFields
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(LoginPalette.captionText)
        .tint(AccentPreferences.current)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var accessGatewayFields: some View {
        labeledField(label: "CLIENT ID", systemImage: "key.fill") {
            TextField("Client ID or token ID", text: $gatewayClientID)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .tint(AccentPreferences.current)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        cardDivider

        labeledField(label: "CLIENT SECRET", systemImage: "lock.square.fill") {
            SecureField("Client secret or access token", text: $gatewayClientSecret)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .tint(AccentPreferences.current)
                .textContentType(.password)
        }

        Text("Needed when Jellyfin sits behind Cloudflare Zero Trust or Pangolin.")
            .font(.caption)
            .foregroundStyle(LoginPalette.captionText)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var passwordRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PASSWORD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LoginPalette.captionText)
                    .tracking(0.6)
                Spacer(minLength: 8)
                Button {
                    showsPasswordHelp = true
                } label: {
                    Text("FORGOT")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(AccentPreferences.current)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(LoginPalette.iconTint)
                    .frame(width: 22, alignment: .center)

                SecureField("Password", text: $password)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.fieldValue)
                    .tint(AccentPreferences.current)
                    .textContentType(.password)

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(LoginPalette.divider)
                .frame(height: 1)
        }
        .padding(.vertical, 12)
    }

    private var cardDivider: some View {
        Divider()
            .background(LoginPalette.divider)
            .padding(.leading, 36)
    }

    private func labeledField<Content: View>(
        label: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoginPalette.captionText)
                .tracking(0.6)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(LoginPalette.iconTint)
                    .frame(width: 22, alignment: .center)

                content()
                    .font(.body.weight(.semibold))
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    @ViewBuilder
    private var statusText: some View {
        if let signInError {
            Text(signInError)
                .font(.footnote.weight(.medium))
                .foregroundStyle(LoginPalette.failure)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        } else if let testMessage {
            Text(testMessage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(testDidSucceed ? LoginPalette.success : LoginPalette.failure)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }
    }

    private var loginButton: some View {
        Button {
            Task { await connect() }
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(LoginPalette.actionLabel)
                }
                Text(isConnecting ? "SIGNING IN…" : "LOGIN")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginActionButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isBusy)
        .opacity((!canSubmit || isBusy) ? 0.42 : 1)
        .accessibilityLabel("Log in")
    }

    private var testConnectionButton: some View {
        Button {
            Task { await checkConnection() }
        } label: {
            HStack(spacing: 8) {
                if isCheckingConnection {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isCheckingConnection ? "TESTING…" : "TEST CONNECTION")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(trimmedAddress.isEmpty || isBusy)
        .opacity((trimmedAddress.isEmpty || isBusy) ? 0.42 : 1)
        .accessibilityLabel("Test server connection")
    }

    private var quickConnectButton: some View {
        Button {
            startQuickConnect()
        } label: {
            HStack(spacing: 8) {
                if isStartingQuickConnect, quickConnectCode == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isStartingQuickConnect ? "STARTING…" : "QUICK CONNECT")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(trimmedAddress.isEmpty || isBusy)
        .opacity((trimmedAddress.isEmpty || isBusy && !isUsingQuickConnect) ? 0.42 : 1)
        .accessibilityLabel("Quick Connect")
    }

    private var reviewDemoButton: some View {
        Button {
            session.connectReviewDemo()
        } label: {
            Text("TRY REVIEW DEMO")
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.42 : 1)
        .accessibilityLabel("Try Review Demo")
        .accessibilityHint("Opens a sample library for App Review. No Jellyfin server required.")
    }

    private var quickConnectPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUICK CONNECT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoginPalette.captionText)
                .tracking(0.6)

            if let quickConnectCode {
                Text(quickConnectCode)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LoginPalette.primaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityLabel("Quick Connect code \(quickConnectCode)")
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Text("Open Jellyfin on another signed-in device and enter this code under Quick Connect.")
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Waiting for approval…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(LoginPalette.captionText)
            }

            Button("Cancel") {
                cancelQuickConnect()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AccentPreferences.current)
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoginPalette.divider, lineWidth: 1)
        )
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedAddress.isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isUsingQuickConnect: Bool {
        isStartingQuickConnect || quickConnectCode != nil
    }

    private var isBusy: Bool {
        isConnecting || isCheckingConnection || isUsingQuickConnect
    }

    /// Signs in to the Jellyfin server using the values on this screen.
    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        signInError = nil
        testMessage = nil
        defer { isConnecting = false }

        do {
            try await session.connect(serverAddress: address, username: username, password: password)
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Checks whether the typed address answers as a Jellyfin server.
    private func checkConnection() async {
        guard !isCheckingConnection else { return }
        signInError = nil
        testMessage = nil
        isCheckingConnection = true
        defer { isCheckingConnection = false }

        do {
            let url = try ServerURL.normalize(address)
            let reachability = await ServerProbe().checkReachability(at: url)
            testMessage = reachability.message
            testDidSucceed = reachability.isReachable
        } catch {
            testMessage = error.localizedDescription
            testDidSucceed = false
        }
    }

    /// Starts Quick Connect and waits until another device authorizes the code.
    private func startQuickConnect() {
        guard !isUsingQuickConnect, !trimmedAddress.isEmpty else { return }
        signInError = nil
        testMessage = nil
        isStartingQuickConnect = true
        quickConnectCode = nil

        let serverAddress = address
        quickConnectTask = Task {
            do {
                try await session.connectUsingQuickConnect(serverAddress: serverAddress) { code in
                    quickConnectCode = code
                }
            } catch is CancellationError {
                // Cancelled from this screen.
            } catch {
                if !Task.isCancelled {
                    signInError = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                isStartingQuickConnect = false
                quickConnectCode = nil
            }
        }
    }

    private func cancelQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        isStartingQuickConnect = false
        quickConnectCode = nil
    }
}

private enum LoginPalette {
    static let cyan = AccentPreferences.cyan.color
    static let cobalt = Color(red: 0.0, green: 0.22, blue: 0.98)
    static let canvas = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let captionText = Color.white.opacity(0.55)
    static let iconTint = Color.white.opacity(0.55)
    static let fieldValue = Color.white
    static let divider = Color.white.opacity(0.12)
    static let actionLabel = Color.black
    static let success = Color(red: 0.22, green: 0.78, blue: 0.42)
    static let failure = Color(red: 1, green: 0.38, blue: 0.38)
}

private struct LoginActionButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(LoginPalette.actionLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AccentPreferences.current)
            )
    }
}

private struct LoginSecondaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
            )
    }
}

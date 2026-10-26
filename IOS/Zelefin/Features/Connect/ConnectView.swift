import SwiftUI

/// Sign-in canvas for a Jellyfin server, or a Silo server through its Jellyfin-compatible API.
struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("zelefin.last-server") private var storedAddress = ""
    @AppStorage("zelefin.last-username") private var storedUsername = ""
    @AppStorage("zelefin.last-server-type") private var serverTypeRaw = SignInServerType.jellyfin.rawValue
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: ConnectField?
    @State private var gatewayClientID = AccessGateway.clientID
    @State private var gatewayClientSecret = AccessGateway.clientSecret
    @State private var isSigningIn = false
    @State private var isCheckingConnection = false
    @State private var signInError: String?
    @State private var testMessage: String?
    @State private var testDidSucceed = false
    @State private var showsPasswordHelp = false
    @State private var showsAccessGateway = false
    @State private var quickConnectCode: String?
    @State private var isStartingQuickConnect = false
    @State private var quickConnectTask: Task<Void, Never>?
    @State private var loginDisclaimer: String?
    @State private var splashscreenURL: URL?
    @State private var isPickingProfile = false

    var body: some View {
        ZStack {
            ConnectSignInBackdrop(
                splashURL: session.pendingSiloSignIn == nil ? splashscreenURL : nil,
                isRegularWidth: horizontalSizeClass == .regular
            )
            .equatable()

            if let pending = session.pendingSiloSignIn {
                SiloWhoIsWatchingView(
                    profiles: pending.profiles,
                    footerTitle: "Use a different account",
                    isBusy: isPickingProfile,
                    errorMessage: signInError,
                    notice: pending.addressWarning,
                    onSelect: { profile, pin in
                        await selectProfile(profile, pin: pin)
                    },
                    onFooter: {
                        signInError = nil
                        session.cancelSiloProfilePick()
                    }
                )
            } else {
                signInScroll
            }
        }
        .tint(LoginPalette.periwinkle)
        .onAppear {
            if address.isEmpty { address = storedAddress }
            if username.isEmpty { username = storedUsername }
        }
        .onDisappear {
            persistCredentials()
            cancelQuickConnect()
        }
        .task(id: address) { await loadBranding() }
        .alert("Password help", isPresented: $showsPasswordHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reset your password on the server, or ask the person who runs it.")
        }
    }

    private var signInScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandBlock
                    .padding(.top, horizontalSizeClass == .regular ? 56 : 28)
                    .padding(.bottom, 32)

                credentialsCard
                    .padding(.bottom, 22)

                if let disclaimer = loginDisclaimer, !disclaimer.isEmpty {
                    Text(disclaimer)
                        .font(.footnote)
                        .foregroundStyle(LoginPalette.secondaryText)
                        .padding(.bottom, 18)
                }

                if serverType == .silo {
                    Text("Enter Silo's address and your Silo sign-in, then pick who's watching.")
                        .font(.footnote)
                        .foregroundStyle(LoginPalette.captionText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                }

                statusText

                VStack(spacing: 12) {
                    signInButton
                    testConnectionButton
                }

                if serverType == .jellyfin {
                    if isUsingQuickConnect {
                        quickConnectPanel
                            .padding(.top, 22)
                    } else {
                        quickConnectButton
                            .padding(.top, 16)
                    }
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
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var brandBlock: some View {
        VStack(spacing: 22) {
            VStack(spacing: 14) {
                ConnectBrandMark(size: horizontalSizeClass == .regular ? 196 : 168)
                Text("Zelefin")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Zelefin")

            ConnectBackendPicker(
                selection: serverTypeBinding,
                tileSize: horizontalSizeClass == .regular ? 96 : 86
            )
        }
        .frame(maxWidth: .infinity)
        .onChange(of: serverTypeRaw) { _, _ in
            if serverType != .jellyfin {
                cancelQuickConnect()
            }
            signInError = nil
            testMessage = nil
        }
    }

    private var serverType: SignInServerType {
        SignInServerType(rawValue: serverTypeRaw) ?? .jellyfin
    }

    private var serverTypeBinding: Binding<SignInServerType> {
        Binding(get: { serverType }, set: { serverTypeRaw = $0.rawValue })
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            labeledField(label: "SERVER URL", systemImage: "link") {
                TextField(
                    "",
                    text: $address,
                    prompt: Text(verbatim: "https://media.example.com")
                        .foregroundStyle(Color.white.opacity(0.55))
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .server)
                .onSubmit { focusedField = .username }
                .accessibilityLabel("Server URL")
            }

            cardDivider

            labeledField(
                label: serverType == .silo ? "USERNAME OR EMAIL" : "USERNAME",
                systemImage: "person.fill"
            ) {
                TextField(
                    "",
                    text: $username,
                    prompt: Text(serverType == .silo ? "username or you@example.com" : "username")
                        .foregroundStyle(Color.white.opacity(0.55))
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .textContentType(.username)
                .keyboardType(serverType == .silo ? .emailAddress : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .username)
                .onSubmit { focusedField = .password }
                .accessibilityLabel(serverType == .silo ? "Username or email" : "Username")
            }

            cardDivider

            passwordRow

            accessGatewaySection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(LoginCardBackground())
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
        .padding(.top, 8)
    }

    @ViewBuilder
    private var accessGatewayFields: some View {
        labeledField(label: "CLIENT ID", systemImage: "key.fill") {
            TextField("Client ID or token ID", text: $gatewayClientID)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .gatewayID)
        }

        cardDivider

        labeledField(label: "CLIENT SECRET", systemImage: "lock.square.fill") {
            SecureField("Client secret or access token", text: $gatewayClientSecret)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
                .textContentType(.password)
                .focused($focusedField, equals: .gatewaySecret)
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
                        .foregroundStyle(LoginPalette.periwinkle)
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
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        guard canSubmit, !isBusy else { return }
                        Task { await connect() }
                    }

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

    private var signInButton: some View {
        let signingIn = isSigningIn
        return Button {
            Task { await connect() }
        } label: {
            HStack(spacing: 8) {
                if signingIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(LoginPalette.actionLabel)
                }
                Text(signingIn ? "SIGNING IN…" : "SIGN IN")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginActionButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isBusy)
        .opacity((!canSubmit || isBusy) ? 0.42 : 1)
        .accessibilityLabel("Sign in with \(serverType.title)")
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
                Text(isStartingQuickConnect ? "STARTING…" : "JELLYFIN QUICK CONNECT")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(trimmedAddress.isEmpty || isBusy)
        .opacity((trimmedAddress.isEmpty || isBusy && !isUsingQuickConnect) ? 0.42 : 1)
        .accessibilityLabel("Jellyfin Quick Connect")
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
        .accessibilityHint("Opens a sample library for App Review. No server required.")
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
            .foregroundStyle(LoginPalette.periwinkle)
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LoginCardBackground())
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
        isSigningIn || isCheckingConnection || isUsingQuickConnect
    }

    private func persistCredentials() {
        storedAddress = address
        storedUsername = username
    }

    private func connect() async {
        guard !isSigningIn else { return }
        persistCredentials()
        isSigningIn = true
        signInError = nil
        testMessage = nil
        defer { isSigningIn = false }

        do {
            try await session.connect(
                serverAddress: address,
                username: username,
                password: password,
                serverType: serverType
            )
        } catch {
            signInError = ServerReachability.signInMessage(for: error)
        }
    }

    private func selectProfile(_ profile: SiloProfile, pin: String?) async {
        guard !isPickingProfile else { return }
        isPickingProfile = true
        signInError = nil
        defer { isPickingProfile = false }
        do {
            try await session.selectSiloProfile(profile, pin: pin)
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func checkConnection() async {
        guard !isCheckingConnection else { return }
        signInError = nil
        testMessage = nil
        isCheckingConnection = true
        defer { isCheckingConnection = false }

        do {
            let url = try ServerURL.normalize(address)
            if await SiloAccountClient.isSiloAddress(url) {
                testMessage = "Silo is reachable. Sign in with your Silo account."
                testDidSucceed = true
                return
            }
            if let info = try? await EmbyAPI.publicInfo(at: url), info.isEmby {
                testMessage = "Emby is reachable."
                testDidSucceed = true
                return
            }
            let probe = ServerProbe()
            let reachability = await probe.checkReachability(at: url)
            if reachability.isReachable {
                testMessage = await probe.isSiloServer(at: url)
                    ? "Silo is reachable through its Jellyfin-compatible API."
                    : "Jellyfin is reachable."
            } else {
                testMessage = reachability.message
            }
            testDidSucceed = reachability.isReachable
        } catch {
            testMessage = error.localizedDescription
            testDidSucceed = false
        }
    }

    private func startQuickConnect() {
        guard !isUsingQuickConnect, !trimmedAddress.isEmpty else { return }
        signInError = nil
        testMessage = nil
        isStartingQuickConnect = true
        quickConnectCode = nil

        persistCredentials()
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

    private func loadBranding() async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loginDisclaimer = nil
            splashscreenURL = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        guard let url = try? ServerURL.normalize(trimmed) else {
            loginDisclaimer = nil
            splashscreenURL = nil
            return
        }
        let branding = await ServerProbe().branding(at: url)
        loginDisclaimer = branding?.loginDisclaimer.trimmingCharacters(in: .whitespacesAndNewlines)
        if branding?.splashscreenEnabled == true {
            splashscreenURL = ServerURL.resolve(base: url, path: "/Branding/Splashscreen")
        } else {
            splashscreenURL = nil
        }
        if loginDisclaimer?.isEmpty == true {
            loginDisclaimer = nil
        }
    }

    private func cancelQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        isStartingQuickConnect = false
        quickConnectCode = nil
    }
}

private enum ConnectField: Hashable {
    case server, username, password, gatewayID, gatewaySecret
}

private struct ConnectSignInBackdrop: View, Equatable {
    let splashURL: URL?
    let isRegularWidth: Bool

    var body: some View {
        ZStack {
            LoginPalette.canvas
            if let splashURL {
                PosterImage(
                    url: splashURL,
                    aspectRatio: 1,
                    contentMode: .fill,
                    fill: .clear
                )
                .clipped()
                .opacity(0.28)
            }
            LoginCanvasGlow(isRegularWidth: isRegularWidth)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

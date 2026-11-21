import SwiftUI

struct FirstRunSetupView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var stepIndex = 0
    @State private var audioCode = PlaybackLanguage.deviceCode
    @State private var subtitleCode = PlaybackLanguage.automaticCode
    @State private var seerrURL = PluginSettings.seerrURLString
    @State private var requestService = PluginSettings.requestService
    @State private var seerrUsername = ""
    @State private var seerrPassword = ""
    @State private var seerrStatus: String?
    @State private var isSigningInToSeerr = false
    @State private var pluginStatus: String?
    @State private var pluginNeedsRestart = false
    @State private var isInstallingPlugin = false
    @State private var isRestarting = false

    private var steps: [Step] {
        var list: [Step] = [.welcome, .languages, .seerr]
        if !session.lacksJellyfinOnlyFeatures {
            list.append(.plugin)
        }
        return list
    }

    private var step: Step { steps[min(stepIndex, steps.count - 1)] }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    var body: some View {
        ZStack {
            LoginPalette.canvas.ignoresSafeArea()
            LoginCanvasGlow(isRegularWidth: horizontalSizeClass == .regular)

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        stepContent
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .zelefinAccentTint()
        .interactiveDismissDisabled()
        .task {
            if seerrUsername.isEmpty {
                seerrUsername = session.session?.userName ?? ""
            }
            await session.detectIntroSkipper()
            await session.detectPlugins()
        }
    }

    private var header: some View {
        HStack {
            if stepIndex > 0 {
                Button(AppLanguage.string("connect.back_caps", default: "BACK")) { stepIndex -= 1 }
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.tint)
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLanguage.string("common.back", default: "Back"))
            }
            Spacer(minLength: 0)
            Button(isLastStep ? AppLanguage.string("ui.done", default: "DONE") : AppLanguage.string("ui.skip", default: "SKIP")) {
                if isLastStep {
                    finish()
                } else {
                    advance()
                }
            }
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.tint)
            .buttonStyle(.plain)
            .accessibilityLabel(isLastStep ? AppLanguage.string("common.done", default: "Done") : "Skip")
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .languages: languagesStep
        case .seerr: seerrStep
        case .plugin: pluginStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            ConnectBrandMark(size: horizontalSizeClass == .regular ? 168 : 148)
            Text(AppLanguage.string("connect.welcome", default: "Welcome to Zelefin"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(LoginPalette.primaryText)
                .multilineTextAlignment(.center)
            Text(welcomeCopy)
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                title: AppLanguage.string("detail.languages", default: "Languages"),
                subtitle: "Zelefin picks matching audio and subtitles when a title has them."
            )
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldLabel(title: AppLanguage.string("player.audio", default: "Audio"))
                    .padding(.bottom, 8)
                Picker(AppLanguage.string("player.audio", default: "Audio"), selection: $audioCode) {
                    ForEach(audioChoices, id: \.self) { code in
                        Text(PlaybackLanguage.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                SettingsCardDivider()
                SettingsFieldLabel(title: AppLanguage.string("player.subtitles", default: "Subtitles"))
                    .padding(.bottom, 8)
                Picker(AppLanguage.string("player.subtitles", default: "Subtitles"), selection: $subtitleCode) {
                    ForEach(subtitleChoices, id: \.self) { code in
                        Text(PlaybackLanguage.displayName(for: code)).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
            }
            .settingsLoginCard()
        }
        .padding(.top, 12)
    }

    private var seerrStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                title: AppLanguage.string("ui.requests", default: "Requests"),
                subtitle: "Optional. Request movies and shows that are not on this server yet. Skip if you do not use Seerr or Ombi."
            )
            VStack(alignment: .leading, spacing: 0) {
                if PluginSettings.isSeerrConfigured {
                    SettingsInfoRow(label: "Signed in as", value: PluginSettings.requestDisplayName ?? requestService.name)
                } else {
                    Picker(AppLanguage.string("connect.service", default: "Service"), selection: $requestService) {
                        ForEach(RequestService.allCases) { service in
                            Text(service.name).tag(service)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 14)
                    SettingsLabeledField(label: "Server", systemImage: "link") {
                        TextField(requestService == .ombi ? "https://ombi.example.com" : "https://seerr.example.com", text: $seerrURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Username", systemImage: "person.fill") {
                        TextField(AppLanguage.string("connect.username_or_email", default: "Username or email"), text: $seerrUsername)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Password", systemImage: "lock.fill") {
                        SecureField(AppLanguage.string("connect.password", default: "Password"), text: $seerrPassword)
                            .textContentType(.password)
                    }
                    SettingsPrimaryButton(
                        title: AppLanguage.string("connect.sign_in", default: "Sign In"),
                        isBusy: isSigningInToSeerr,
                        enabled: canSignInToSeerr,
                        prominent: true
                    ) {
                        Task { await signInToSeerr() }
                    }
                    .padding(.top, 16)
                }
                if let seerrStatus {
                    SettingsStatusText(text: seerrStatus, isError: !seerrStatus.contains(AppLanguage.string("ui.signed_in", default: "Signed in")))
                        .padding(.top, 12)
                }
            }
            .settingsLoginCard()
        }
        .padding(.top, 12)
    }

    private var pluginStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                title: "Zelefin plugin",
                subtitle: session.companionAvailable
                    ? "This server already has the Zelefin plugin. Lock-screen alerts can arrive while the app is closed."
                    : "Notifications need this plugin. It can alert this iPhone when titles are added or a stream starts, including while Zelefin is closed. Jellyfin needs a restart after install."
            )
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(AppLanguage.string("settings.zelefin_section", default: "Zelefin"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LoginPalette.primaryText)
                    Spacer(minLength: 8)
                    SettingsStatusValue(
                        text: pluginStatusLabel,
                        isPositive: session.companionAvailable || pluginNeedsRestart
                    )
                }
                if session.isAdministrator, !session.companionAvailable {
                    SettingsPrimaryButton(
                        title: isInstallingPlugin ? "Installing…" : "Install Plugin",
                        isBusy: isInstallingPlugin,
                        enabled: !isInstallingPlugin && !pluginNeedsRestart,
                        prominent: true
                    ) {
                        Task { await installPlugin() }
                    }
                    .padding(.top, 16)
                    if pluginNeedsRestart {
                        SettingsSecondaryButton(
                            title: isRestarting ? "Restarting…" : "Restart Jellyfin",
                            enabled: !isRestarting,
                            prominent: true
                        ) {
                            Task { await restartServer() }
                        }
                        .padding(.top, 10)
                    }
                } else if !session.isAdministrator, !session.companionAvailable {
                    SettingsStatusText(
                        text: "Ask a server administrator to install the Zelefin plugin from the catalog, or sign in with an admin account."
                    )
                    .padding(.top, 12)
                }
                if let pluginStatus {
                    SettingsStatusText(text: pluginStatus, isError: pluginStatus.contains("could not"))
                        .padding(.top, 12)
                }
            }
            .settingsLoginCard()
        }
        .padding(.top, 12)
    }

    private var welcomeCopy: String {
        session.lacksJellyfinOnlyFeatures
            ? "A few optional choices for this \(session.isEmbyServer ? "Emby" : "Silo") server: languages and Seerr or Ombi requests."
            : "A few optional choices for this server: languages, Seerr or Ombi requests, and the Zelefin plugin for lock-screen alerts."
    }

    private var pluginStatusLabel: String {
        if session.companionAvailable { return "Installed" }
        if pluginNeedsRestart { return "Restart needed" }
        return "Not on this server"
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == stepIndex ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.18)))
                        .frame(width: index == stepIndex ? 18 : 7, height: 7)
                }
            }
            .accessibilityLabel(String(format: AppLanguage.string("connect.step_of", default: "Step %d of %d"), stepIndex + 1, steps.count))

            SettingsPrimaryButton(title: isLastStep ? "Finish Setup" : AppLanguage.string("common.continue", default: "Continue"), prominent: true) {
                if isLastStep {
                    finish()
                } else {
                    advance()
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 28)
    }

    private func stepHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(LoginPalette.primaryText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(LoginPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audioChoices: [String] {
        [PlaybackLanguage.automaticCode] + SubtitleSearchLanguage.choices.map(\.code)
    }

    private var subtitleChoices: [String] {
        [PlaybackLanguage.automaticCode, PlaybackLanguage.offCode] + SubtitleSearchLanguage.choices.map(\.code)
    }

    private var canSignInToSeerr: Bool {
        !seerrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !seerrPassword.isEmpty
    }

    private func advance() {
        if step == .languages {
            Task { await session.applyPlaybackLanguages(audioCode: audioCode, subtitleCode: subtitleCode) }
        }
        stepIndex = min(stepIndex + 1, steps.count - 1)
    }

    private func finish() {
        Task {
            await session.applyPlaybackLanguages(audioCode: audioCode, subtitleCode: subtitleCode)
            session.completeFirstRunSetup()
        }
    }

    private func signInToSeerr() async {
        PluginSettings.seerrURLString = seerrURL
        PluginSettings.requestService = requestService
        guard PluginSettings.seerrURL != nil else {
            seerrStatus = "Enter a valid \(requestService.name) URL."
            return
        }
        isSigningInToSeerr = true
        seerrStatus = nil
        defer { isSigningInToSeerr = false }
        do {
            let name = try await PluginSettings.signIn(
                username: seerrUsername,
                password: seerrPassword,
                ownerAccountID: session.session?.accountID
            )
            seerrURL = PluginSettings.seerrURLString
            seerrPassword = ""
            seerrStatus = "Signed in as \(name)."
        } catch {
            seerrStatus = error.localizedDescription
        }
    }

    private func installPlugin() async {
        isInstallingPlugin = true
        pluginStatus = nil
        defer { isInstallingPlugin = false }
        do {
            try await session.installZelefinPlugin()
            pluginNeedsRestart = !session.companionAvailable
            pluginStatus = pluginNeedsRestart
                ? "Installed. Restart Jellyfin so the plugin can load."
                : "Installed."
        } catch {
            pluginStatus = error.localizedDescription
        }
    }

    private func restartServer() async {
        isRestarting = true
        defer { isRestarting = false }
        do {
            try await session.restartJellyfinAfterPluginInstall()
            pluginStatus = "Jellyfin is restarting. Reopen Zelefin in a minute if the library does not load."
        } catch {
            pluginStatus = error.localizedDescription
        }
    }

    private enum Step: Hashable {
        case welcome
        case languages
        case seerr
        case plugin
    }
}

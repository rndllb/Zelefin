package app.zelefin.client

import android.app.Application
import app.zelefin.client.emby.EmbyLibrary
import app.zelefin.client.emby.accountRights
import app.zelefin.client.push.PushHookRelay
import app.zelefin.core.ZelefinException
import app.zelefin.client.silo.SiloAccountClient
import app.zelefin.client.silo.SiloAlertCategory
import app.zelefin.client.silo.SiloAlertRegistration
import app.zelefin.client.emby.EmbyAlertCategory
import app.zelefin.client.emby.EmbyAlertRegistration
import app.zelefin.client.emby.EmbyAlertsNotAllowed
import app.zelefin.client.emby.availableAlertEvents
import app.zelefin.client.emby.deleteAlertWebhook
import app.zelefin.client.emby.offersWebhooks
import app.zelefin.client.emby.saveAlertWebhook
import app.zelefin.client.emby.testAlertWebhook
import app.zelefin.client.emby.downloadSubtitle
import app.zelefin.client.emby.searchSubtitles
import app.zelefin.client.plugins.DiscoverPage
import app.zelefin.client.plugins.DiscoverQuery
import app.zelefin.client.plugins.DiscoverSection
import app.zelefin.client.plugins.JellyfinEnhancedAwards
import app.zelefin.client.plugins.JellyfinEnhancedClient
import app.zelefin.client.plugins.JellyfinEnhancedHomeSurface
import app.zelefin.client.plugins.JellyfinEnhancedReview
import app.zelefin.client.plugins.JellyfinEnhancedReviewKey
import app.zelefin.client.plugins.JellyfinPluginState
import app.zelefin.client.plugins.JellyfinPlugins
import app.zelefin.client.plugins.OpenSubtitlesPlugin
import app.zelefin.client.plugins.JellyfinTmdbCatalog
import app.zelefin.client.plugins.IntroSkipperClient
import app.zelefin.client.plugins.OpenSubtitlesClient
import app.zelefin.client.plugins.PluginSettings
import app.zelefin.client.plugins.RemoteSubtitle
import app.zelefin.client.plugins.RemoteSubtitleOffer
import app.zelefin.client.plugins.RequestCatalog
import app.zelefin.client.plugins.SeerrClient
import app.zelefin.client.plugins.SeerrRequestCatalog
import app.zelefin.client.plugins.SeerrRequestDraft
import app.zelefin.client.plugins.SeerrTitle
import app.zelefin.client.plugins.SeerrUser
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.client.plugins.TmdbUserReview
import app.zelefin.client.plugins.ZelefinCompanionClient
import app.zelefin.client.plugins.ZelefinPluginInstaller
import app.zelefin.client.push.ZelefinPush
import app.zelefin.core.SavedSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PluginsUiState(
    val jellyfin: JellyfinPluginState = JellyfinPluginState(),
    val detecting: Boolean = false,
    val isAdmin: Boolean = false,
    val canManageSubtitles: Boolean = false,
    val seerrUrl: String = "",
    val seerrName: String? = null,
    val seerrUser: SeerrUser? = null,
    val seerrBusy: Boolean = false,
    val seerrMessage: String? = null,
    val autoSkipIntro: Boolean = false,
    val autoSkipCredits: Boolean = false,
    val isSiloServer: Boolean = false,
    val isEmbyServer: Boolean = false,
    val pushEnabled: Boolean = true,
    val pushRegistered: Boolean = false,
    val pushBusy: Boolean = false,
    val pushMessage: String? = null,
    val pluginInstalling: Boolean = false,
    val pluginRestarting: Boolean = false,
    /** Installed in this session but not yet loaded; Jellyfin needs a restart. */
    val pluginNeedsRestart: Boolean = false,
    val pluginInstallMessage: String? = null,
    /** Emby's Webhooks notifier or Silo's personal webhooks, which carry this phone's alerts on those servers. */
    val webhooksAvailable: Boolean = false,
    /** The switches under "Alert Me About", as (id, title). */
    val alertOptions: List<Pair<String, String>> = emptyList(),
    val alertsOn: Boolean = false,
    val alertCategories: Set<String> = emptySet(),
    /** Events Emby lets this account subscribe to; empty until loaded. */
    val embyAlertEvents: Set<String> = emptySet(),
    /** Set when only an administrator can add this phone's webhook address in Emby. */
    val alertsAdminAddress: String? = null,
    val alertsBusy: Boolean = false,
    val alertsMessage: String? = null,
    val alertsMessageIsError: Boolean = false,
) {
    /** Silo and Emby run no Jellyfin server plugins. */
    val runsJellyfinPlugins: Boolean get() = !isSiloServer && !isEmbyServer

    val companionAvailable: Boolean get() = runsJellyfinPlugins && jellyfin.companion

    val discoverAvailable: Boolean get() = seerrName != null

    val canManageRequests: Boolean get() = seerrUser?.canManageRequests == true

    /** Jellyfin and Emby both search through their Open Subtitles plugin. */
    fun showsAddSubtitles(kind: app.zelefin.core.MediaKind): Boolean =
        (runsJellyfinPlugins || isEmbyServer) &&
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles,
                jellyfin.openSubtitles,
                RemoteSubtitleOffer.supportsRemoteSubtitles(kind),
            )

    val hidesFromHome: Boolean get() = runsJellyfinPlugins && jellyfin.enhanced
}

data class DiscoverGridState(
    val titles: List<SeerrTitle> = emptyList(),
    val page: Int = 0,
    val totalPages: Int = 1,
    val loading: Boolean = true,
    val message: String? = null,
) {
    val hasMore: Boolean get() = page < totalPages
}

data class DiscoverUiState(
    val sections: List<DiscoverSection> = emptyList(),
    val loading: Boolean = false,
    val message: String? = null,
    val term: String = "",
    val hits: List<SeerrTitle> = emptyList(),
    val searching: Boolean = false,
    val grids: Map<String, DiscoverGridState> = emptyMap(),
    val requesting: Set<String> = emptySet(),
    val requested: Set<String> = emptySet(),
    val catalog: JellyfinTmdbCatalog = JellyfinTmdbCatalog.Empty,
    val notice: String? = null,
) {
    fun resolved(title: SeerrTitle): SeerrTitle = when {
        title.availability.isOnServer -> title
        catalog.contains(title) -> title.copy(availability = SeerrTitle.Availability.Available)
        title.id in requested || "${title.kind.raw}-${title.tmdbId}" in requested ->
            title.copy(availability = SeerrTitle.Availability.Pending)
        else -> title
    }
}

class PluginsController(
    private val application: Application,
    private val scope: CoroutineScope,
    private val session: () -> SavedSession?,
    private val allSessions: () -> List<SavedSession> = { listOfNotNull(session()) },
    private val tmdbCatalog: suspend () -> JellyfinTmdbCatalog,
    private val emby: () -> EmbyLibrary? = { null },
    private val silo: () -> SiloAccountClient? = { null },
) {
    private val settings = PluginSettings(application)
    private val _state = MutableStateFlow(
        PluginsUiState(
            seerrUrl = settings.seerrUrl,
            seerrName = settings.seerrSession?.displayName,
            autoSkipIntro = settings.autoSkipIntro,
            autoSkipCredits = settings.autoSkipCredits,
            pushEnabled = ZelefinPush.isEnabled(application),
        ),
    )

    init {
        scope.launch { ZelefinPush.tokens.collect { registerPush() } }
    }
    val state: StateFlow<PluginsUiState> = _state.asStateFlow()
    private val _discover = MutableStateFlow(DiscoverUiState())
    val discover: StateFlow<DiscoverUiState> = _discover.asStateFlow()

    private var detectJob: Job? = null
    private var homeJob: Job? = null
    private var searchJob: Job? = null
    private val gridJobs = mutableMapOf<String, Job>()
    private var lastUser: String? = null
    private var detectedFor: String? = null

    fun ensureDetected() {
        if (session()?.accountId != detectedFor) refresh()
    }

    fun refresh() {
        val current = session() ?: return
        detectedFor = current.accountId
        if (PluginSettings.shouldClearSession(lastUser, current.accountId, settings.seerrOwnerAccountId)) {
            settings.clearSeerrSession()
            _state.update { it.copy(seerrName = null, seerrUser = null) }
            _discover.value = DiscoverUiState()
        } else if (settings.seerrSession != null && settings.seerrOwnerAccountId == null) {
            settings.seerrOwnerAccountId = current.accountId
        }
        lastUser = current.accountId
        _state.update { it.copy(isSiloServer = current.isSiloServer, isEmbyServer = current.isEmbyServer, detecting = true) }
        detectJob?.cancel()
        detectJob = scope.launch {
            detectJellyfin(current)
            _state.update { it.copy(detecting = false) }
        }
    }

    fun reset() {
        detectedFor = null
        detectJob?.cancel()
        homeJob?.cancel()
        searchJob?.cancel()
        gridJobs.values.forEach(Job::cancel)
        gridJobs.clear()
        _discover.value = DiscoverUiState()
        _state.update {
            it.copy(
                jellyfin = JellyfinPluginState(),
                isAdmin = false,
                pushRegistered = false,
                pushMessage = null,
            )
        }
    }

    /**
     * Registers this install's Firebase token with the Zelefin plugin, like iOS
     * `SessionStore.registerCompanionPush()`. Runs after plugin detection and whenever
     * Firebase rotates the token.
     */
    fun registerPush() {
        val current = session() ?: return
        if (current.isEmbyServer) {
            scope.launch { refreshEmbyAlertToken(current) }
            return
        }
        if (current.isSiloServer) {
            scope.launch { refreshSiloAlertToken(current) }
            return
        }
        if (!_state.value.companionAvailable || !ZelefinPush.isEnabled(application)) return
        scope.launch {
            val token = ZelefinPush.fetchToken(application) ?: return@launch
            val stored = ZelefinCompanionClient(current.serverUrl, current.accessToken)
                .registerDevice(token, ZelefinPush.deviceId(application), ZelefinPush.PLATFORM)
            if (session()?.accountId == current.accountId) _state.update { it.copy(pushRegistered = stored) }
        }
    }

    private suspend fun loadEmbyAlerts(current: SavedSession) {
        val library = emby() ?: return
        val webhooks = library.offersWebhooks()
        val events = if (webhooks) library.availableAlertEvents() else emptySet()
        val saved = EmbyAlertRegistration.saved(application, current.accountId)
        val options = EmbyAlertCategory.all
            .filter { category -> events.isEmpty() || category.events.any(events::contains) }
            .map { it.id to it.title }
        _state.update {
            it.copy(
                webhooksAvailable = webhooks,
                alertOptions = options,
                embyAlertEvents = events,
                alertsOn = saved != null,
                alertCategories = saved?.categoryIds?.toSet() ?: EmbyAlertCategory.defaultIds,
                alertsAdminAddress = saved?.takeIf { registration -> registration.entryId == null }?.url,
            )
        }
    }

    /** Turns this phone's webhook alerts on or off for the signed-in Emby or Silo account. */
    fun setWebhookAlerts(on: Boolean) {
        val current = session() ?: return
        _state.update { it.copy(alertsBusy = true, alertsMessage = null) }
        scope.launch {
            if (current.isSiloServer) {
                if (on) saveSiloAlerts(current, _state.value.alertCategories) else disableSiloAlerts(current)
            } else if (on) {
                saveEmbyAlerts(current, _state.value.alertCategories)
            } else {
                EmbyAlertRegistration.saved(application, current.accountId)?.let { registration ->
                    registration.entryId?.let { emby()?.deleteAlertWebhook(it) }
                    PushHookRelay.remove(PushHookRelay.Service.Emby, registration.hookId)
                }
                EmbyAlertRegistration.save(application, current.accountId, null)
                _state.update { it.copy(alertsOn = false, alertsAdminAddress = null) }
            }
            _state.update { it.copy(alertsBusy = false) }
        }
    }

    fun setWebhookAlertCategory(id: String, on: Boolean) {
        val current = session() ?: return
        val next = _state.value.alertCategories.let { if (on) it + id else it - id }
        _state.update { it.copy(alertCategories = next, alertsBusy = true, alertsMessage = null) }
        scope.launch {
            if (current.isSiloServer) saveSiloAlerts(current, next) else saveEmbyAlerts(current, next)
            _state.update { it.copy(alertsBusy = false) }
        }
    }

    fun sendWebhookTestAlert() {
        val current = session() ?: return
        _state.update { it.copy(alertsBusy = true, alertsMessage = null) }
        scope.launch {
            val failure: String? = try {
                if (current.isSiloServer) {
                    val link = current.siloLink
                    val webhookId = SiloAlertRegistration.saved(application, current.accountId)?.webhookId
                    if (link == null || webhookId == null) "Turn on Notifications first."
                    else silo()?.testWebhook(webhookId, link.profileId, link.profileToken)
                } else {
                    val registration = EmbyAlertRegistration.saved(application, current.accountId)
                    if (registration == null) "Turn on Notifications first."
                    else { emby()?.testAlertWebhook(registration.url, registration.events); null }
                }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                error.message ?: "Couldn’t send the test."
            }
            _state.update {
                it.copy(
                    alertsBusy = false,
                    alertsMessage = failure ?: "Sent. It should arrive in a few seconds.",
                    alertsMessageIsError = failure != null,
                )
            }
        }
    }

    private suspend fun loadSiloAlerts(current: SavedSession) {
        val link = current.siloLink
        val available = link != null && silo()?.personalWebhooksAvailable(link.profileId, link.profileToken) == true
        val saved = SiloAlertRegistration.saved(application, current.accountId)
        _state.update {
            it.copy(
                webhooksAvailable = available,
                alertOptions = SiloAlertCategory.all.map { category -> category.id to category.title },
                alertsOn = saved != null,
                alertCategories = saved?.categoryIds?.toSet() ?: SiloAlertCategory.defaultIds,
                alertsAdminAddress = null,
            )
        }
    }

    /**
     * Registers this phone with the push service, adds a webhook to the active Silo profile, and hands
     * the push service that webhook's signing secret so it can check each delivery.
     */
    private suspend fun saveSiloAlerts(current: SavedSession, categories: Set<String>) {
        val link = current.siloLink
        val client = silo()
        if (link == null || client == null) {
            failAlerts(current, "Sign in with your Silo account to get notifications from this server.")
            return
        }
        val token = ZelefinPush.fetchToken(application)
        if (token == null) {
            failAlerts(current, "This phone couldn’t get a push token. Check that Google Play services is up to date.")
            return
        }
        val flags = SiloAlertCategory.flags(categories)
        val chosen = SiloAlertCategory.all.map { it.id }.filter { it in categories }
        try {
            val saved = SiloAlertRegistration.saved(application, current.accountId)
            if (saved?.webhookId != null) {
                client.updateWebhook(saved.webhookId, link.profileId, link.profileToken, flags)
                client.allowNotificationReasons(flags, link.profileId, link.profileToken)
                val refreshed = saved.token == token || PushHookRelay.update(PushHookRelay.Service.Silo, saved.hookId, token)
                SiloAlertRegistration.save(
                    application,
                    current.accountId,
                    saved.copy(token = if (refreshed) token else saved.token, categoryIds = chosen),
                )
                _state.update { it.copy(alertsOn = true) }
                return
            }
            val hook = PushHookRelay.register(PushHookRelay.Service.Silo, token, current.serverName ?: "Silo")
            try {
                val (webhookId, secret) = client.createWebhook(
                    link.profileId,
                    link.profileToken,
                    "Zelefin · ${android.os.Build.MODEL}",
                    hook.url,
                    flags,
                )
                SiloAlertRegistration.save(application, current.accountId, SiloAlertRegistration(hook.hookId, token, webhookId, chosen))
                if (!PushHookRelay.update(PushHookRelay.Service.Silo, hook.hookId, token, signingSecret = secret)) {
                    throw ZelefinException.server("Zelefin's push service could not save this phone. Try again in a moment.")
                }
                client.allowNotificationReasons(flags, link.profileId, link.profileToken)
                _state.update { it.copy(alertsOn = true) }
            } catch (error: Exception) {
                disableSiloAlerts(current)
                PushHookRelay.remove(PushHookRelay.Service.Silo, hook.hookId)
                throw error
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Exception) {
            failAlerts(current, error.message ?: "Couldn’t turn on notifications. Try again.")
        }
    }

    private suspend fun disableSiloAlerts(current: SavedSession) {
        val registration = SiloAlertRegistration.saved(application, current.accountId)
        if (registration != null) {
            val link = current.siloLink
            if (registration.webhookId != null && link != null) {
                silo()?.deleteWebhook(registration.webhookId, link.profileId, link.profileToken)
            }
            PushHookRelay.remove(PushHookRelay.Service.Silo, registration.hookId)
            SiloAlertRegistration.save(application, current.accountId, null)
        }
        _state.update { it.copy(alertsOn = false) }
    }

    /** A new Firebase token goes to the push service under the same hook, so Silo's webhook stays valid. */
    private suspend fun refreshSiloAlertToken(current: SavedSession) {
        val registration = SiloAlertRegistration.saved(application, current.accountId) ?: return
        val token = ZelefinPush.fetchToken(application) ?: return
        if (registration.token == token) return
        if (PushHookRelay.update(PushHookRelay.Service.Silo, registration.hookId, token)) {
            SiloAlertRegistration.save(application, current.accountId, registration.copy(token = token))
        }
    }

    private fun failAlerts(current: SavedSession, message: String) {
        val stillOn = if (current.isSiloServer) SiloAlertRegistration.saved(application, current.accountId) != null
        else EmbyAlertRegistration.saved(application, current.accountId) != null
        _state.update { it.copy(alertsOn = stillOn, alertsMessage = message, alertsMessageIsError = true) }
    }

    /** When Emby refuses, the registration is kept so an admin can add the address by hand. */
    private suspend fun saveEmbyAlerts(current: SavedSession, categories: Set<String>) {
        val library = emby() ?: return
        val token = ZelefinPush.fetchToken(application)
        if (token == null) {
            _state.update {
                it.copy(
                    alertsOn = EmbyAlertRegistration.saved(application, current.accountId) != null,
                    alertsMessage = "This phone couldn’t get a push token. Check that Google Play services is up to date.",
                    alertsMessageIsError = true,
                )
            }
            return
        }
        try {
            var registration = EmbyAlertRegistration.saved(application, current.accountId)
            if (registration == null || registration.token != token) {
                registration?.let { PushHookRelay.remove(PushHookRelay.Service.Emby, it.hookId) }
                val hook = PushHookRelay.register(PushHookRelay.Service.Emby, token)
                registration = EmbyAlertRegistration(hook.hookId, hook.url, token, entryId = registration?.entryId)
            }
            registration = registration.copy(categoryIds = EmbyAlertCategory.all.map { it.id }.filter { it in categories })
            EmbyAlertRegistration.save(application, current.accountId, registration)
            try {
                val entryId = library.saveAlertWebhook(
                    registration.entryId,
                    registration.url,
                    registration.events,
                    "Zelefin · ${android.os.Build.MODEL}",
                )
                EmbyAlertRegistration.save(application, current.accountId, registration.copy(entryId = entryId))
                _state.update { it.copy(alertsOn = true, alertsAdminAddress = null) }
            } catch (refused: EmbyAlertsNotAllowed) {
                _state.update { it.copy(alertsOn = true, alertsAdminAddress = refused.url) }
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Exception) {
            _state.update {
                it.copy(
                    alertsOn = EmbyAlertRegistration.saved(application, current.accountId) != null,
                    alertsMessage = error.message ?: "Couldn’t turn on notifications. Try again.",
                    alertsMessageIsError = true,
                )
            }
        }
    }

    /** A new Firebase token goes to the push service under the same hook, so Emby's address stays valid. */
    private suspend fun refreshEmbyAlertToken(current: SavedSession) {
        val registration = EmbyAlertRegistration.saved(application, current.accountId) ?: return
        val token = ZelefinPush.fetchToken(application) ?: return
        if (registration.token == token) return
        if (PushHookRelay.update(PushHookRelay.Service.Emby, registration.hookId, token)) {
            EmbyAlertRegistration.save(application, current.accountId, registration.copy(token = token))
        } else {
            saveEmbyAlerts(current, registration.categoryIds.toSet())
        }
    }

    /** Removes this install from the plugin. Call before the session is cleared. */
    fun unregisterPush(current: SavedSession? = session()) {
        current ?: return
        if (!current.hasJellyfinExtras) return
        val deviceId = ZelefinPush.deviceId(application)
        scope.launch {
            withContext(NonCancellable) {
                ZelefinCompanionClient(current.serverUrl, current.accessToken).deleteDevice(deviceId)
            }
        }
        _state.update { it.copy(pushRegistered = false) }
    }

    fun setPushEnabled(enabled: Boolean) {
        ZelefinPush.setEnabled(application, enabled)
        _state.update { it.copy(pushEnabled = enabled, pushMessage = null) }
        if (enabled) {
            registerPush()
            return
        }
        // Every signed-in account may have registered this phone; the plugin must forget all of them.
        val servers = (allSessions() + listOfNotNull(session()))
            .filter { it.hasJellyfinExtras }
            .distinctBy { it.serverUrl to it.accessToken }
        if (servers.isEmpty()) {
            _state.update { it.copy(pushRegistered = false) }
            return
        }
        servers.forEach { unregisterPush(it) }
    }

    fun sendTestPush() {
        val current = session() ?: return
        if (!_state.value.companionAvailable) return
        _state.update { it.copy(pushBusy = true, pushMessage = null) }
        scope.launch {
            val token = ZelefinPush.fetchToken(application)
            val client = ZelefinCompanionClient(current.serverUrl, current.accessToken)
            val error = when {
                token == null -> "This phone couldn’t get a push token. Check that Google Play services is up to date."
                !client.registerDevice(token, ZelefinPush.deviceId(application), ZelefinPush.PLATFORM) ->
                    "The server didn’t accept this phone. Update the Zelefin plugin on Jellyfin."
                else -> client.sendTest()
            }
            _state.update {
                it.copy(
                    pushBusy = false,
                    pushRegistered = error == null || it.pushRegistered,
                    pushMessage = error ?: "Sent. It should arrive in a few seconds.",
                )
            }
        }
    }

    /** Mirrors iOS `SessionStore.installZelefinPlugin()` and the Notifications settings install button. */
    fun installZelefinPlugin() {
        val current = session() ?: return
        if (!current.hasJellyfinExtras || !_state.value.isAdmin) {
            _state.update { it.copy(pluginInstallMessage = "Sign in as a Jellyfin administrator to install the Zelefin plugin.") }
            return
        }
        _state.update { it.copy(pluginInstalling = true, pluginInstallMessage = null) }
        scope.launch {
            val result = runCatching { ZelefinPluginInstaller(current.serverUrl, current.accessToken).install() }
            result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
            if (result.isSuccess) {
                val detected = runCatching {
                    JellyfinPlugins.detect(current.serverUrl, current.accessToken, current.userId, isAdmin = true, canManageSubtitles = _state.value.canManageSubtitles)
                }.getOrNull()
                val loaded = detected?.companion == true
                _state.update {
                    it.copy(
                        jellyfin = detected ?: it.jellyfin,
                        pluginInstalling = false,
                        pluginNeedsRestart = !loaded,
                        pluginInstallMessage = if (loaded) "Installed." else "Installed. Restart Jellyfin so the plugin can load.",
                    )
                }
                if (loaded) registerPush()
            } else {
                _state.update {
                    it.copy(
                        pluginInstalling = false,
                        pluginInstallMessage = result.exceptionOrNull()?.message ?: "Jellyfin could not install the Zelefin plugin.",
                    )
                }
            }
        }
    }

    fun restartJellyfin() {
        val current = session() ?: return
        if (!current.hasJellyfinExtras || !_state.value.isAdmin) return
        _state.update { it.copy(pluginRestarting = true) }
        scope.launch {
            val result = runCatching { ZelefinPluginInstaller(current.serverUrl, current.accessToken).restartServer() }
            result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
            _state.update {
                it.copy(
                    pluginRestarting = false,
                    pluginInstallMessage = if (result.isSuccess) {
                        "Jellyfin is restarting. Reopen Zelefin in a minute if the library does not load."
                    } else {
                        result.exceptionOrNull()?.message ?: "Jellyfin could not restart."
                    },
                )
            }
        }
    }

    private suspend fun detectJellyfin(current: SavedSession) {
        if (current.isEmbyServer) {
            val (admin, subtitles) = runCatching { emby()?.accountRights() }.getOrNull() ?: (false to false)
            // Emby lists its plugins to administrators only, so other users fall back to their subtitle rights.
            val names = if (admin) JellyfinPlugins.activeNames(current.serverUrl, current.accessToken) else emptyList()
            val openSubtitles = RemoteSubtitleOffer.pluginAvailable(
                listed = OpenSubtitlesPlugin.isInstalled(names),
                catalogNames = names,
                canManageSubtitles = subtitles,
                canListPlugins = admin,
            )
            _state.update {
                it.copy(
                    jellyfin = JellyfinPluginState(openSubtitles = openSubtitles, names = names),
                    isAdmin = admin,
                    canManageSubtitles = subtitles,
                )
            }
            loadEmbyAlerts(current)
            refreshSeerrUser()
            return
        }
        if (!current.hasJellyfinExtras) {
            _state.update { it.copy(jellyfin = JellyfinPluginState(), isAdmin = false, canManageSubtitles = false) }
            if (current.isSiloServer) loadSiloAlerts(current)
            refreshSeerrUser()
            return
        }
        val (admin, subtitleManagement) = JellyfinPlugins.userPolicy(current.serverUrl, current.accessToken, current.userId)
        val canManage = RemoteSubtitleOffer.canManageSubtitles(admin, subtitleManagement)
        val detected = runCatching {
            JellyfinPlugins.detect(current.serverUrl, current.accessToken, current.userId, admin, canManage)
        }.getOrElse { if (it is CancellationException) throw it else JellyfinPluginState() }
        _state.update { it.copy(jellyfin = detected, isAdmin = admin, canManageSubtitles = canManage) }
        if (detected.companion) registerPush()
        refreshSeerrUser()
    }

    private suspend fun refreshSeerrUser() {
        if (settings.seerrClient() != null) {
            val user = settings.refreshUser()
            val session = settings.seerrSession
            _state.update {
                it.copy(
                    seerrUser = user,
                    seerrName = user?.displayLabel ?: session?.displayName,
                    seerrMessage = if (session == null) "Seerr session expired. Sign in again." else it.seerrMessage,
                )
            }
        }
    }

    fun catalog(): RequestCatalog? {
        if (session() == null || !_state.value.discoverAvailable) return null
        return settings.seerrClient()?.let(::SeerrRequestCatalog)
    }

    fun seerr(): SeerrClient? = settings.seerrClient()

    fun signInSeerr(url: String, username: String, password: String) {
        val normalized = PluginSettings.normalizeSeerrUrl(url)
        if (normalized == null) {
            _state.update { it.copy(seerrMessage = "Enter your Seerr address.") }
            return
        }
        _state.update { it.copy(seerrBusy = true, seerrMessage = null) }
        val ownerAccountId = session()?.accountId
        scope.launch {
            runCatching { SeerrClient.signIn(normalized, username, password) }
                .onSuccess { signedIn ->
                    settings.seerrUrl = url.trim()
                    settings.rememberSignIn(signedIn, username, password, ownerAccountId)
                    val user = runCatching { SeerrClient(normalized, signedIn).currentUser() }.getOrNull()
                    val name = user?.displayLabel ?: signedIn.displayName
                    _state.update {
                        it.copy(
                            seerrUrl = url.trim(),
                            seerrName = name,
                            seerrUser = user,
                            seerrBusy = false,
                            seerrMessage = "Signed in as $name.",
                        )
                    }
                    _discover.value = DiscoverUiState()
                }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    _state.update { it.copy(seerrBusy = false, seerrMessage = error.message ?: "Seerr sign-in failed.") }
                }
        }
    }

    fun signOutSeerr() {
        settings.clearSeerrSession()
        _state.update { it.copy(seerrName = null, seerrUser = null, seerrMessage = null) }
        _discover.value = DiscoverUiState()
    }

    fun setAutoSkipIntro(value: Boolean) {
        settings.autoSkipIntro = value
        _state.update { it.copy(autoSkipIntro = value) }
    }

    fun setAutoSkipCredits(value: Boolean) {
        settings.autoSkipCredits = value
        _state.update { it.copy(autoSkipCredits = value) }
    }

    fun loadDiscoverHome(force: Boolean = false) {
        val current = _discover.value
        if (!force && (current.sections.isNotEmpty() || current.loading)) return
        val catalog = catalog() ?: return
        _discover.update { it.copy(loading = it.sections.isEmpty(), message = null) }
        homeJob?.cancel()
        homeJob = scope.launch {
            launch {
                val ids = runCatching { tmdbCatalog() }.getOrNull()
                if (ids != null) _discover.update { it.copy(catalog = ids) }
            }
            runCatching { catalog.discoverHome() }
                .onSuccess { sections -> _discover.update { it.copy(sections = sections, loading = false) } }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    _discover.update { it.copy(loading = false, message = error.message ?: "Discover couldn’t load.") }
                }
        }
    }

    fun searchDiscover(term: String) {
        val trimmed = term.trim()
        if (trimmed == _discover.value.term) return
        searchJob?.cancel()
        if (trimmed.length < SearchMinimumLength) {
            _discover.update { it.copy(term = trimmed, hits = emptyList(), searching = false) }
            return
        }
        _discover.update { it.copy(term = trimmed, searching = true) }
        val catalog = catalog() ?: return
        searchJob = scope.launch {
            delay(SearchDebounceMillis)
            val hits = runCatching { catalog.search(trimmed) }
                .getOrElse { if (it is CancellationException) throw it else emptyList() }
            _discover.update { if (it.term != trimmed) it else it.copy(hits = hits, searching = false) }
        }
    }

    fun loadDiscoverGrid(query: DiscoverQuery, more: Boolean = false) {
        val key = query.key
        val existing = _discover.value.grids[key]
        if (more && (existing == null || existing.loading || !existing.hasMore)) return
        if (!more && existing != null && existing.titles.isNotEmpty()) return
        val catalog = catalog() ?: return
        val page = if (more) (existing?.page ?: 0) + 1 else 1
        updateGrid(key) { copy(loading = true, message = null) }
        gridJobs.remove(key)?.cancel()
        gridJobs[key] = scope.launch {
            runCatching { catalog.discover(query, page) }
                .onSuccess { result: DiscoverPage ->
                    updateGrid(key) {
                        val merged = if (more) (titles + result.titles).distinctBy { it.id } else result.titles
                        copy(titles = merged, page = result.page, totalPages = result.totalPages, loading = false)
                    }
                }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    updateGrid(key) { copy(loading = false, message = error.message) }
                }
        }
    }

    private fun updateGrid(key: String, transform: DiscoverGridState.() -> DiscoverGridState) {
        _discover.update { state ->
            val current = state.grids[key] ?: DiscoverGridState()
            state.copy(grids = state.grids + (key to current.transform()))
        }
    }

    suspend fun submitSeerr(title: SeerrTitle, draft: SeerrRequestDraft) {
        val client = seerr() ?: return
        client.request(draft)
        markRequested(title)
    }

    suspend fun approveSeerr(requestId: Int, draft: SeerrRequestDraft) {
        val client = seerr() ?: return
        client.approveRequest(requestId, draft)
        refreshAfterReview()
    }

    suspend fun declineSeerr(requestId: Int) {
        val client = seerr() ?: return
        client.declineRequest(requestId)
        refreshAfterReview()
    }

    private fun refreshAfterReview() {
        _discover.update { it.copy(grids = it.grids - DiscoverQuery.Requests.key) }
        loadDiscoverHome(force = true)
    }

    private fun markRequested(title: SeerrTitle) {
        _discover.update {
            it.copy(
                requesting = it.requesting - title.id,
                requested = it.requested + title.id + "${title.kind.raw}-${title.tmdbId}",
            )
        }
    }

    fun clearNotice() {
        _discover.update { it.copy(notice = null) }
    }

    /** Emby marks intros and credits in its chapter list; Jellyfin uses media segments or Intro Skipper. */
    suspend fun skipSegments(itemId: String): List<SkipSegment> {
        val current = session() ?: return emptyList()
        return runCatching {
            if (current.isEmbyServer) {
                emby()?.skipSegments(itemId).orEmpty()
            } else {
                IntroSkipperClient(current.serverUrl, current.accessToken).segments(itemId)
            }
        }.getOrElse { if (it is CancellationException) throw it else emptyList() }
    }

    fun subtitles(): OpenSubtitlesClient? {
        val current = session() ?: return null
        if (!current.hasJellyfinExtras || !_state.value.jellyfin.openSubtitles) return null
        return OpenSubtitlesClient(current.serverUrl, current.accessToken, current.userId)
    }

    suspend fun searchSubtitles(itemId: String, language: String, perfectMatch: Boolean?): List<RemoteSubtitle> {
        embySubtitles()?.let { return it.searchSubtitles(itemId, language, perfectMatch) }
        return subtitles()?.search(itemId, language, perfectMatch).orEmpty()
    }

    suspend fun downloadSubtitle(itemId: String, subtitleId: String) {
        embySubtitles()?.let { return it.downloadSubtitle(itemId, subtitleId) }
        subtitles()?.download(itemId, subtitleId)
    }

    private fun embySubtitles(): EmbyLibrary? =
        emby()?.takeIf { session()?.isEmbyServer == true && _state.value.canManageSubtitles }

    private fun enhanced(): JellyfinEnhancedClient? {
        val current = session() ?: return null
        if (!current.hasJellyfinExtras || !_state.value.jellyfin.enhanced) return null
        return JellyfinEnhancedClient(current.serverUrl, current.accessToken, current.userId)
    }

    val enhancedAvailable: Boolean get() = enhanced() != null

    suspend fun hideFromHome(itemId: String, surface: JellyfinEnhancedHomeSurface) {
        val client = enhanced() ?: throw app.zelefin.core.ZelefinException.server("Jellyfin Enhanced is not on this server.")
        client.hideFromHome(itemId, surface)
    }

    suspend fun enhancedExtras(kind: app.zelefin.core.MediaKind, tmdbId: Int?): EnhancedExtras? {
        val client = enhanced() ?: return null
        val target = JellyfinEnhancedReviewKey.target(kind, tmdbId) ?: return null
        return coroutineScope {
            val reviews = async {
                try {
                    client.reviews(target.mediaType, target.tmdbId)
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (_: Exception) {
                    emptyList()
                }
            }
            val tmdb = async { client.tmdbReviews(target.mediaType, target.tmdbId) }
            val awards = async { client.awards(target.mediaType, target.tmdbId) }
            EnhancedExtras(reviews.await(), tmdb.await(), awards.await()?.takeUnless { it.isEmpty })
        }
    }

    suspend fun saveReview(kind: app.zelefin.core.MediaKind, tmdbId: Int?, content: String, rating: Double?) {
        val client = enhanced() ?: return
        val target = JellyfinEnhancedReviewKey.target(kind, tmdbId) ?: return
        client.saveReview(target.mediaType, target.tmdbId, content, rating)
    }

    suspend fun deleteReview(kind: app.zelefin.core.MediaKind, tmdbId: Int?, review: JellyfinEnhancedReview) {
        val client = enhanced() ?: return
        val target = JellyfinEnhancedReviewKey.target(kind, tmdbId) ?: return
        if (isOwnReview(review)) {
            client.deleteOwnReview(target.mediaType, target.tmdbId)
        } else {
            client.deleteReview(review.userId, target.mediaType, target.tmdbId)
        }
    }

    fun isOwnReview(review: JellyfinEnhancedReview): Boolean {
        val userId = session()?.userId ?: return false
        return review.isAuthoredBy(userId)
    }
}

data class EnhancedExtras(
    val reviews: List<JellyfinEnhancedReview>,
    val tmdbReviews: List<TmdbUserReview>,
    val awards: JellyfinEnhancedAwards?,
)

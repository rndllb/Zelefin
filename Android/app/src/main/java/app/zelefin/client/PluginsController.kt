package app.zelefin.client

import android.app.Application
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
import app.zelefin.client.plugins.SiloRequestCapabilities
import app.zelefin.client.plugins.SiloRequestClient
import app.zelefin.client.plugins.SiloRequestSource
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.client.plugins.TmdbUserReview
import app.zelefin.client.plugins.ZelefinCompanionClient
import app.zelefin.client.push.ZelefinPush
import app.zelefin.core.MediaBackend
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
    val silo: SiloRequestCapabilities = SiloRequestCapabilities.None,
    val siloSource: SiloRequestSource = SiloRequestSource.Seerr,
    val autoSkipIntro: Boolean = false,
    val autoSkipCredits: Boolean = false,
    val backend: MediaBackend = MediaBackend.Jellyfin,
    val pushEnabled: Boolean = true,
    val pushRegistered: Boolean = false,
    val pushBusy: Boolean = false,
    val pushMessage: String? = null,
) {
    val companionAvailable: Boolean get() = backend == MediaBackend.Jellyfin && jellyfin.companion

    val discoverAvailable: Boolean
        get() = when (backend) {
            MediaBackend.Silo -> silo.discoverAvailable(siloSource)
            MediaBackend.Jellyfin -> seerrName != null
        }

    val oneTapRequests: Boolean get() = backend == MediaBackend.Silo
    val canManageRequests: Boolean get() = seerrUser?.canManageRequests == true

    fun showsAddSubtitles(kind: app.zelefin.core.MediaKind): Boolean =
        backend == MediaBackend.Jellyfin &&
            RemoteSubtitleOffer.shouldShowAddSubtitles(
                canManageSubtitles,
                jellyfin.openSubtitles,
                RemoteSubtitleOffer.supportsRemoteSubtitles(kind),
            )

    val hidesFromHome: Boolean get() = backend == MediaBackend.Jellyfin && jellyfin.enhanced
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
    private val siloIdentity: () -> Map<String, String>,
    private val tmdbCatalog: suspend () -> JellyfinTmdbCatalog,
) {
    private val settings = PluginSettings(application)
    private val _state = MutableStateFlow(
        PluginsUiState(
            seerrUrl = settings.seerrUrl,
            seerrName = settings.seerrSession?.displayName,
            siloSource = settings.siloRequestSource,
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
        if (PluginSettings.shouldClearSession(lastUser, current.accountId)) {
            settings.clearSeerrSession()
            _state.update { it.copy(seerrName = null, seerrUser = null) }
            _discover.value = DiscoverUiState()
        }
        lastUser = current.accountId
        _state.update { it.copy(backend = current.backend, detecting = true) }
        detectJob?.cancel()
        detectJob = scope.launch {
            when (current.backend) {
                MediaBackend.Jellyfin -> detectJellyfin(current)
                MediaBackend.Silo -> detectSilo(current)
            }
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
                silo = SiloRequestCapabilities.None,
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
        if (!_state.value.companionAvailable || !ZelefinPush.isEnabled(application)) return
        scope.launch {
            val token = ZelefinPush.fetchToken(application) ?: return@launch
            val stored = ZelefinCompanionClient(current.serverUrl, current.accessToken)
                .registerDevice(token, ZelefinPush.deviceId(application), ZelefinPush.PLATFORM)
            if (session()?.accountId == current.accountId) _state.update { it.copy(pushRegistered = stored) }
        }
    }

    /** Removes this install from the plugin. Call before the session is cleared. */
    fun unregisterPush(current: SavedSession? = session()) {
        current ?: return
        if (current.backend != MediaBackend.Jellyfin) return
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
        if (enabled) registerPush() else unregisterPush()
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

    private suspend fun detectJellyfin(current: SavedSession) {
        val (admin, subtitleManagement) = JellyfinPlugins.userPolicy(current.serverUrl, current.accessToken, current.userId)
        val canManage = RemoteSubtitleOffer.canManageSubtitles(admin, subtitleManagement)
        val detected = runCatching {
            JellyfinPlugins.detect(current.serverUrl, current.accessToken, current.userId, admin, canManage)
        }.getOrElse { if (it is CancellationException) throw it else JellyfinPluginState() }
        _state.update { it.copy(jellyfin = detected, isAdmin = admin, canManageSubtitles = canManage) }
        if (detected.companion) registerPush()
        settings.seerrClient()?.let { client ->
            runCatching { client.currentUser() }
                .onSuccess { user -> _state.update { it.copy(seerrUser = user, seerrName = user.displayLabel) } }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    settings.clearSeerrSession()
                    _state.update {
                        it.copy(seerrName = null, seerrUser = null, seerrMessage = "Seerr session expired. Sign in again.")
                    }
                }
        }
    }

    private suspend fun detectSilo(current: SavedSession) {
        val admin = current.userRole?.lowercase() in setOf("admin", "administrator", "owner")
        val caps = runCatching { siloRequests(current).detectCapabilities(admin) }
            .getOrElse { if (it is CancellationException) throw it else SiloRequestCapabilities.None }
        _state.update { it.copy(silo = caps, isAdmin = admin) }
    }

    private fun siloRequests(current: SavedSession) = SiloRequestClient(
        baseUrl = current.serverUrl,
        accessToken = current.accessToken,
        refreshToken = current.refreshToken,
        profileId = current.profileId,
        profileToken = current.profileToken,
        identityHeaders = siloIdentity(),
    )

    fun catalog(): RequestCatalog? {
        val current = session() ?: return null
        if (!_state.value.discoverAvailable) return null
        return when (current.backend) {
            MediaBackend.Silo -> siloRequests(current)
            MediaBackend.Jellyfin -> settings.seerrClient()?.let(::SeerrRequestCatalog)
        }
    }

    fun seerr(): SeerrClient? = settings.seerrClient()

    fun signInSeerr(url: String, username: String, password: String) {
        val normalized = PluginSettings.normalizeSeerrUrl(url)
        if (normalized == null) {
            _state.update { it.copy(seerrMessage = "Enter your Seerr address.") }
            return
        }
        _state.update { it.copy(seerrBusy = true, seerrMessage = null) }
        scope.launch {
            runCatching { SeerrClient.signIn(normalized, username, password) }
                .onSuccess { session ->
                    settings.seerrUrl = url.trim()
                    settings.seerrSession = session
                    val user = runCatching { SeerrClient(normalized, session).currentUser() }.getOrNull()
                    val name = user?.displayLabel ?: session.displayName
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

    fun setSiloSource(source: SiloRequestSource) {
        settings.siloRequestSource = source
        _state.update { it.copy(siloSource = source) }
        _discover.value = DiscoverUiState()
    }

    fun loadDiscoverHome(force: Boolean = false) {
        val current = _discover.value
        if (!force && (current.sections.isNotEmpty() || current.loading)) return
        val catalog = catalog() ?: return
        _discover.update { it.copy(loading = it.sections.isEmpty(), message = null) }
        homeJob?.cancel()
        homeJob = scope.launch {
            if (session()?.backend == MediaBackend.Jellyfin) {
                launch {
                    val ids = runCatching { tmdbCatalog() }.getOrNull()
                    if (ids != null) _discover.update { it.copy(catalog = ids) }
                }
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

    /** One tap on Silo; Seerr requests go through [submitSeerr] from the request sheet. */
    fun requestOneTap(title: SeerrTitle) {
        val catalog = catalog() ?: return
        _discover.update { it.copy(requesting = it.requesting + title.id) }
        scope.launch {
            runCatching { catalog.request(title) }
                .onSuccess { markRequested(title) }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    _discover.update {
                        it.copy(requesting = it.requesting - title.id, notice = error.message ?: "The request didn’t go through.")
                    }
                }
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

    suspend fun skipSegments(itemId: String): List<SkipSegment> {
        val current = session() ?: return emptyList()
        if (current.backend != MediaBackend.Jellyfin) return emptyList()
        return runCatching { IntroSkipperClient(current.serverUrl, current.accessToken).segments(itemId) }
            .getOrElse { if (it is CancellationException) throw it else emptyList() }
    }

    fun subtitles(): OpenSubtitlesClient? {
        val current = session() ?: return null
        if (current.backend != MediaBackend.Jellyfin || !_state.value.jellyfin.openSubtitles) return null
        return OpenSubtitlesClient(current.serverUrl, current.accessToken, current.userId)
    }

    suspend fun searchSubtitles(itemId: String, language: String, perfectMatch: Boolean?): List<RemoteSubtitle> =
        subtitles()?.search(itemId, language, perfectMatch).orEmpty()

    suspend fun downloadSubtitle(itemId: String, subtitleId: String) {
        subtitles()?.download(itemId, subtitleId)
    }

    private fun enhanced(): JellyfinEnhancedClient? {
        val current = session() ?: return null
        if (current.backend != MediaBackend.Jellyfin || !_state.value.jellyfin.enhanced) return null
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

package app.zelefin.client

import android.app.Application
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.zelefin.client.jellyfin.CollectionEditor
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.client.jellyfin.JellyfinScope
import app.zelefin.client.plugins.HomeQueueHideStore
import app.zelefin.client.plugins.JellyfinEnhancedHomeSurface
import app.zelefin.client.push.ZelefinPush
import app.zelefin.client.session.SessionVault
import app.zelefin.client.session.SnapshotStore
import app.zelefin.client.silo.SiloClient
import app.zelefin.core.GatewaySecrets
import app.zelefin.core.HomeFeed
import app.zelefin.core.HouseholdProfile
import app.zelefin.core.MediaBackend
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.core.QuickConnectHandshake
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerReachability
import app.zelefin.core.ServerUrl
import app.zelefin.core.SiloPendingSignIn
import app.zelefin.core.TitleDetail
import app.zelefin.core.ZelefinException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AppTab { Home, Movies, Shows, Library, Search }

data class LibraryRoom(
    val id: String,
    val name: String,
    val kind: LibraryKind = LibraryKind.Other,
)

sealed interface Screen {
    data object Connect : Screen
    data class Profiles(val pending: SiloPendingSignIn) : Screen
    data class Pin(val pending: SiloPendingSignIn, val profile: HouseholdProfile) : Screen
    data object Library : Screen
    data class Detail(val id: String, val returnTo: Screen = Library) : Screen
    data class Player(val plan: PlaybackPlan, val returnTo: Screen = Library) : Screen
    data class Settings(val returnTo: Screen) : Screen
    data class Profile(val returnTo: Screen) : Screen
    data class SettingsTopic(val id: String, val backTo: Screen) : Screen
}

data class ZelefinUiState(
    val screen: Screen = Screen.Connect,
    val tab: AppTab = AppTab.Home,
    val backend: MediaBackend = MediaBackend.Jellyfin,
    val busy: Boolean = false,
    val message: String? = null,
    val session: SavedSession? = null,
    val home: HomeFeed = HomeFeed(),
    val movies: List<MediaItem> = emptyList(),
    val shows: List<MediaItem> = emptyList(),
    val libraries: List<LibraryRoom> = emptyList(),
    val libraryPath: List<LibraryRoute> = emptyList(),
    val searchPath: List<LibraryRoute> = emptyList(),
    val search: LibrarySearchState = LibrarySearchState(),
    val libraryGrids: Map<LibraryRoute, LibraryGridState> = emptyMap(),
    val libraryOverview: LibraryOverview = LibraryOverview(),
    val libraryLayout: LibraryLayout = LibraryLayout(),
    val librariesLoading: Boolean = false,
    val detail: TitleDetail? = null,
    val quickConnect: QuickConnectHandshake? = null,
    val homeRefreshing: Boolean = false,
    val moviesRefreshing: Boolean = false,
    val showsRefreshing: Boolean = false,
    val moviesLoading: Boolean = false,
    val showsLoading: Boolean = false,
    val movieQuery: CatalogBrowseQuery = CatalogBrowseQuery(),
    val showQuery: CatalogBrowseQuery = CatalogBrowseQuery(),
    val movieFilters: CatalogFilterOptions = CatalogFilterOptions(),
    val showFilters: CatalogFilterOptions = CatalogFilterOptions(),
    val gatewayId: String = "",
    val gatewaySecret: String = "",
)

class ZelefinModel(application: Application) : AndroidViewModel(application) {
    private val vault = SessionVault(application)
    private val snapshots = SnapshotStore(application)
    private val layoutStore = LibraryLayoutStore(application)
    private val searchHistory = SearchHistoryStore(application)
    private val _state = MutableStateFlow(
        ZelefinUiState(libraryLayout = layoutStore.load(), search = LibrarySearchState(recents = searchHistory.load())),
    )
    private var searchJob: Job? = null
    val plugins = PluginsController(
        application = application,
        scope = viewModelScope,
        session = { _state.value.session },
        siloIdentity = { siloClient().identity() },
        tmdbCatalog = { jellyfinClient().tmdbCatalog(userUuid()) },
    )
    val state: StateFlow<ZelefinUiState> = _state.asStateFlow()

    private var jellyfin: JellyfinLibrary? = null
    private var movieCatalogJob: Job? = null
    private var showCatalogJob: Job? = null
    private var overviewJob: Job? = null
    private val gridJobs = mutableMapOf<LibraryRoute, Job>()
    private var silo: SiloClient? = null
    private var activePlan: PlaybackPlan? = null
    private var lastReported = 0.0
    private var quickConnectJob: Job? = null

    init {
        vault.applyGateway()
        val secrets = vault.loadGateway()
        val saved = vault.current()
        _state.update { it.copy(gatewayId = secrets.clientId, gatewaySecret = secrets.clientSecret, session = saved) }
        if (saved != null) {
            restore(saved)
            val cachedHome = snapshots.loadHome(saved)
            _state.update {
                it.copy(
                    screen = Screen.Library,
                    backend = saved.backend,
                    home = cachedHome?.first?.let(::visibleHome) ?: it.home,
                    libraries = cachedHome?.second ?: emptyList(),
                    movies = snapshots.loadCatalog(saved, "movies").orEmpty(),
                    shows = snapshots.loadCatalog(saved, "shows").orEmpty(),
                )
            }
            refreshLibrary()
        }
    }

    fun setBackend(backend: MediaBackend) {
        _state.update { it.copy(backend = backend, message = null) }
    }

    fun saveGateway(id: String, secret: String) {
        vault.saveGateway(GatewaySecrets(id.trim(), secret.trim()))
        _state.update { it.copy(gatewayId = id.trim(), gatewaySecret = secret.trim()) }
    }

    fun testConnection(rawUrl: String) {
        launch("Checking the server…") {
            val url = ServerUrl.normalize(rawUrl)
            val backend = _state.value.backend
            val reachability = probe(url, backend)
            val message = if (reachability.isReachable) {
                if (backend == MediaBackend.Silo) "Silo is reachable." else "Jellyfin is reachable."
            } else {
                reachability.message
            }
            _state.update { it.copy(busy = false, message = message) }
        }
    }

    fun signIn(rawUrl: String, username: String, password: String) {
        launch("Signing in…") {
            val url = ServerUrl.normalize(rawUrl)
            val backend = _state.value.backend
            when (backend) {
                MediaBackend.Jellyfin -> signInJellyfin(url, username, password)
                MediaBackend.Silo -> signInSilo(url, username, password)
            }
        }
    }

    fun startQuickConnect(rawUrl: String) {
        quickConnectJob?.cancel()
        _state.update { it.copy(busy = true, message = null) }
        quickConnectJob = viewModelScope.launch {
            runCatching {
                val url = ServerUrl.normalize(rawUrl)
                val library = JellyfinLibrary(getApplication(), url)
                if (!library.quickConnectEnabled()) throw ZelefinException.quickConnectDisabled()
                val handshake = library.startQuickConnect()
                jellyfin = library
                _state.update { it.copy(busy = false, quickConnect = handshake, message = null) }
                val result = library.waitForQuickConnect(handshake)
                storeJellyfin(url, result.accessToken.orEmpty(), result.user?.id?.toString().orEmpty(), result.user?.name ?: "Jellyfin", result.user?.primaryImageTag, null, null)
                _state.update { it.copy(quickConnect = null, screen = Screen.Library, busy = false) }
                refreshLibrary()
            }.onFailure { error ->
                if (error is CancellationException) return@onFailure
                _state.update { it.copy(busy = false, quickConnect = null, message = error.message) }
            }
        }
    }

    fun cancelQuickConnect() {
        quickConnectJob?.cancel()
        quickConnectJob = null
        _state.update { it.copy(quickConnect = null, busy = false, message = null) }
    }

    fun chooseProfile(profile: HouseholdProfile) {
        val pending = (_state.value.screen as? Screen.Profiles)?.pending ?: return
        if (profile.hasPin) {
            _state.update { it.copy(screen = Screen.Pin(pending, profile), message = null) }
        } else {
            finishSilo(pending, profile, null)
        }
    }

    fun submitPin(pin: String) {
        val screen = _state.value.screen as? Screen.Pin ?: return
        launch("Checking PIN…") {
            val client = silo ?: throw ZelefinException.missingUser()
            val token = client.verifyPin(screen.profile.id, pin)
            finishSilo(screen.pending, screen.profile, token)
        }
    }

    fun selectTab(tab: AppTab) {
        val silo = _state.value.session?.backend == MediaBackend.Silo
        _state.update { it.copy(tab = tab, screen = Screen.Library) }
        if (tab == AppTab.Movies || (tab == AppTab.Search && silo)) loadCatalog(AppTab.Movies)
        if (tab == AppTab.Shows || (tab == AppTab.Search && silo)) loadCatalog(AppTab.Shows)
        if (tab == AppTab.Library) {
            _state.update { it.copy(libraryPath = emptyList()) }
            loadLibraryOverview()
        }
        if (tab == AppTab.Search) {
            _state.update { it.copy(searchPath = emptyList()) }
            loadSearchGenres()
        }
    }

    fun updateSearchTerm(term: String) {
        if (term == _state.value.search.term) return
        searchJob?.cancel()
        val trimmed = term.trim()
        if (trimmed.length < SearchMinimumLength) {
            _state.update { it.copy(search = it.search.copy(term = term, hits = emptyList(), loading = false)) }
            return
        }
        _state.update { it.copy(search = it.search.copy(term = term, loading = true)) }
        searchJob = viewModelScope.launch {
            kotlinx.coroutines.delay(SearchDebounceMillis)
            val result = runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> siloClient().search(trimmed)
                    else -> jellyfinClient().searchHints(userUuid(), trimmed)
                }
            }
            result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
            val hits = result.getOrDefault(emptyList())
            _state.update { state ->
                if (state.search.term.trim() != trimmed) state
                else state.copy(search = state.search.copy(hits = hits, loading = false))
            }
        }
    }

    fun openSearchHit(hit: SearchHit) {
        when (hit.kind) {
            SearchHitKind.Title -> openSearchItem(hit.item)
            SearchHitKind.Person -> openLibraryRoute(LibraryRoute.Person(hit.id, hit.name))
            SearchHitKind.Studio -> openLibraryRoute(LibraryRoute.Studio(hit.id, hit.name))
            SearchHitKind.Genre -> openLibraryRoute(LibraryRoute.Genre(LibraryGenre(hit.id, hit.name)))
        }
    }

    fun openSearchItem(item: MediaItem) {
        val recents = searchHistory.record(item)
        _state.update { it.copy(search = it.search.copy(recents = recents)) }
        openItem(item)
    }

    fun removeRecentSearch(id: String) {
        val recents = searchHistory.remove(id)
        _state.update { it.copy(search = it.search.copy(recents = recents)) }
    }

    fun clearRecentSearches() {
        searchHistory.clear()
        _state.update { it.copy(search = it.search.copy(recents = emptyList())) }
    }

    private fun loadSearchGenres() {
        if (_state.value.search.genres.isNotEmpty()) return
        _state.update { it.copy(search = it.search.copy(genresLoading = true)) }
        viewModelScope.launch {
            val genres = runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val items = _state.value.movies + _state.value.shows
                        catalogOptionsFromItems(items).genres.map { LibraryGenre(it.id, it.name) }
                    }
                    else -> jellyfinClient().genres(userUuid(), limit = 48)
                }
            }.getOrDefault(emptyList()).collapsedGenres().take(24)
            _state.update { it.copy(search = it.search.copy(genres = genres, genresLoading = false)) }
        }
    }

    fun openItem(item: MediaItem) {
        val target = item.seriesDetailItemId ?: item.id
        val current = _state.value.screen
        val returnTo = when (current) {
            is Screen.Detail -> if (current.id == target) current.returnTo else current
            else -> Screen.Library
        }
        showDetail(target, returnTo)
    }

    /** Opens the title from a tapped alert (iOS `DeepLinkStore.openLibraryItem`). */
    fun openPushItem(rawId: String) {
        if (_state.value.session == null) return
        val id = ZelefinPush.normalizedItemId(rawId)
        viewModelScope.launch {
            val item = runCatching { loadDetail(id).item }
                .onFailure { if (it is CancellationException) throw it }
                .getOrNull()
            if (item != null) openItem(item) else showDetail(id, Screen.Library)
        }
    }

    fun openProfile() {
        val current = _state.value.screen
        if (current is Screen.Profile || current is Screen.Player) return
        val backTo = if (current is Screen.Settings) current else sheetParent(current)
        _state.update { it.copy(screen = Screen.Profile(backTo), message = null) }
    }

    fun openSettings() = openSheet { Screen.Settings(it) }

    fun openSessions() = openSettingsTopic("sessions")

    fun openSettingsTopic(id: String) {
        val current = _state.value.screen
        if (current is Screen.Player) return
        val backTo = when (current) {
            is Screen.Settings -> current
            is Screen.SettingsTopic -> current.backTo
            else -> current
        }
        _state.update { it.copy(screen = Screen.SettingsTopic(id, backTo), message = null) }
    }

    fun back() {
        val current = _state.value
        if (current.screen is Screen.Library && current.tab == AppTab.Library && current.libraryPath.isNotEmpty()) {
            _state.update { it.copy(libraryPath = it.libraryPath.dropLast(1), message = null) }
            return
        }
        if (current.screen is Screen.Library && current.tab == AppTab.Search && current.searchPath.isNotEmpty()) {
            _state.update { it.copy(searchPath = it.searchPath.dropLast(1), message = null) }
            return
        }
        val next = when (val screen = current.screen) {
            is Screen.Player -> screen.returnTo
            is Screen.Detail -> screen.returnTo
            is Screen.Pin -> Screen.Profiles(screen.pending)
            is Screen.Settings -> screen.returnTo
            is Screen.Profile -> screen.returnTo
            is Screen.SettingsTopic -> screen.backTo
            else -> return
        }
        _state.update { it.copy(screen = next, message = null) }
        if (next is Screen.Detail && _state.value.detail?.item?.id != next.id) showDetail(next.id, next.returnTo)
    }

    private fun showDetail(target: String, returnTo: Screen) {
        val session = _state.value.session
        val cached = session?.let { snapshots.loadDetail(it, target) }
        _state.update { it.copy(screen = Screen.Detail(target, returnTo), detail = cached, busy = cached == null, message = null) }
        viewModelScope.launch {
            runCatching { loadDetail(target) }
                .onSuccess { detail ->
                    _state.value.session?.let { snapshots.saveDetail(it, detail) }
                    _state.update { state ->
                        val showing = state.screen as? Screen.Detail
                        if (showing?.id == target) state.copy(detail = detail, busy = false) else state
                    }
                    if (_state.value.session?.backend != MediaBackend.Silo && (_state.value.screen as? Screen.Detail)?.id == target) {
                        val collections = runCatching {
                            jellyfinClient().collectionsContaining(UUID.fromString(_state.value.session?.userId), target)
                        }.getOrDefault(emptyList())
                        _state.update { state ->
                            val current = state.detail
                            if ((state.screen as? Screen.Detail)?.id == target && current?.item?.id == target) {
                                state.copy(detail = current.copy(collections = collections))
                            } else {
                                state
                            }
                        }
                        _state.value.session?.let { saved ->
                            _state.value.detail?.takeIf { it.item.id == target }?.let { snapshots.saveDetail(saved, it) }
                        }
                    }
                }
                .onFailure { error ->
                    _state.update { state ->
                        val showing = state.screen as? Screen.Detail
                        if (showing?.id != target) state else state.copy(busy = false, message = if (state.detail == null) error.message else state.message)
                    }
                }
        }
    }

    private fun sheetParent(screen: Screen): Screen = when (screen) {
        is Screen.Settings -> screen.returnTo
        is Screen.Profile -> screen.returnTo
        is Screen.SettingsTopic -> screen.backTo
        else -> screen
    }

    private fun openSheet(sheet: (Screen) -> Screen) {
        val current = _state.value.screen
        if (current is Screen.Settings || current is Screen.Profile || current is Screen.SettingsTopic || current is Screen.Player) return
        _state.update { it.copy(screen = sheet(current), message = null) }
    }

    fun toggleWatched(item: MediaItem) {
        val played = !item.isWatched
        viewModelScope.launch {
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> if (played) siloClient().markWatched(item.id) else siloClient().markUnwatched(item.id)
                    else -> if (played) jellyfinClient().markPlayed(item.id) else jellyfinClient().markUnplayed(item.id)
                }
            }.onSuccess {
                _state.update { state -> state.withItem(item.id) { copy(isPlayed = played) } }
                refreshLibrary()
            }.onFailure { error -> _state.update { it.copy(message = error.message) } }
        }
    }

    fun toggleFavorite(item: MediaItem) {
        val favorite = !item.isFavorite
        viewModelScope.launch {
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> siloClient().setFavorite(item.id, favorite)
                    else -> jellyfinClient().setFavorite(item.id, favorite)
                }
            }.onSuccess {
                _state.update { state -> state.withItem(item.id) { copy(isFavorite = favorite) } }
                refreshLibrary()
            }.onFailure { error -> _state.update { it.copy(message = error.message) } }
        }
    }

    suspend fun loadCollections(itemId: String): CollectionEditor {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        if (session.usesSilo) throw ZelefinException.server("Collections aren't available on this server.")
        return jellyfinClient().collectionEditor(UUID.fromString(session.userId), itemId)
    }

    suspend fun setCollectionMember(collectionId: String, itemId: String, member: Boolean) {
        val client = jellyfinClient()
        if (member) client.addToCollection(collectionId, itemId) else client.removeFromCollection(collectionId, itemId)
    }

    suspend fun createCollection(name: String, itemId: String) {
        jellyfinClient().createCollection(name, itemId)
    }

    fun play(item: MediaItem) {
        val returnTo = _state.value.screen
        _state.value.session?.let { HomeQueueHideStore.remove(getApplication(), item.id, it.userId) }
        launch("Starting playback…") {
            val detail = _state.value.detail
            val target = if (detail != null && detail.item.id == item.id) {
                MediaItem.heroPlaybackItem(item, detail.episodes)
            } else {
                item
            }
            val plan = when (_state.value.session?.backend) {
                MediaBackend.Silo -> siloClient().playback(
                    item = target,
                    appVersion = "0.1.0",
                    osVersion = Build.VERSION.RELEASE ?: "",
                    model = Build.MODEL ?: "Android",
                )
                else -> {
                    val userId = UUID.fromString(_state.value.session?.userId)
                    jellyfinClient().playback(userId, target)
                }
            }
            val reported = PlaybackResumePolicy.reportStartPosition(0.0, plan.startTimeSeconds)
            activePlan = plan
            lastReported = reported
            runCatching { report(plan, reported, paused = false, start = true) }
            _state.update { it.copy(busy = false, screen = Screen.Player(plan, returnTo), message = null) }
        }
    }

    fun playbackProgress(positionSeconds: Double, paused: Boolean) {
        val plan = activePlan ?: return
        if (!paused && kotlin.math.abs(positionSeconds - lastReported) < 10) return
        lastReported = positionSeconds
        viewModelScope.launch {
            runCatching { report(plan, positionSeconds, paused, start = false) }
        }
    }

    fun playbackStopped(positionSeconds: Double) {
        val plan = activePlan ?: return
        activePlan = null
        viewModelScope.launch {
            runCatching {
                when (plan.item.kind) {
                    else -> Unit
                }
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> plan.playSessionId?.let { sessionId ->
                        siloClient().report(sessionId, positionSeconds, paused = true)
                        siloClient().stop(sessionId)
                    }
                    else -> jellyfinClient().reportStop(plan, positionSeconds)
                }
            }
        }
    }

    fun refreshLibrary() {
        plugins.ensureDetected()
        viewModelScope.launch {
            val session = _state.value.session
            val cached = session?.let { snapshots.loadHome(it) }
            _state.update {
                it.copy(
                    homeRefreshing = true,
                    home = cached?.first?.let(::visibleHome) ?: it.home,
                    libraries = if (cached != null && it.libraries.isEmpty()) cached.second else it.libraries,
                )
            }
            runCatching { currentHome() }
                .onSuccess { feed ->
                    _state.update { it.copy(home = feed, homeRefreshing = false, message = null) }
                    _state.value.session?.let { snapshots.saveHome(it, feed, _state.value.libraries) }
                }
                .onFailure { error -> _state.update { it.copy(homeRefreshing = false, message = error.message) } }
        }
    }

    fun signOut() {
        plugins.unregisterPush()
        vault.clear()
        jellyfin = null
        silo = null
        plugins.reset()
        _state.update {
            ZelefinUiState(
                gatewayId = it.gatewayId,
                gatewaySecret = it.gatewaySecret,
                libraryLayout = it.libraryLayout,
                search = LibrarySearchState(recents = searchHistory.load()),
            )
        }
    }

    private suspend fun signInJellyfin(url: String, username: String, password: String) {
        val library = JellyfinLibrary(getApplication(), url)
        val result = library.login(username.trim(), password)
        jellyfin = library
        val user = result.user ?: throw ZelefinException.missingUser()
        storeJellyfin(
            url = url,
            token = result.accessToken.orEmpty(),
            userId = user.id.toString(),
            userName = user.name ?: username,
            imageTag = user.primaryImageTag,
            serverName = null,
            serverVersion = null,
        )
        _state.update { it.copy(busy = false, screen = Screen.Library) }
        refreshLibrary()
    }

    private suspend fun signInSilo(url: String, username: String, password: String) {
        val client = newSilo(url)
        val auth = client.login(username.trim(), password)
        silo = client
        val label = runCatching { client.serverLabel() }.getOrNull()
        val profiles = client.profiles()
        val pending = SiloPendingSignIn(
            serverUrl = url,
            accessToken = auth.accessToken,
            refreshToken = auth.refreshToken,
            userId = auth.userId,
            userName = auth.userName,
            deviceId = vault.deviceId,
            serverName = label?.first,
            serverVersion = label?.second,
            userRole = auth.role,
            profiles = profiles,
        )
        val unlocked = pending.singleUnlockedProfile
        if (unlocked != null) {
            finishSilo(pending, unlocked, null)
        } else if (profiles.isEmpty()) {
            finishSilo(pending, HouseholdProfile(id = auth.userId, name = auth.userName, isPrimary = true), null)
        } else {
            _state.update { it.copy(busy = false, screen = Screen.Profiles(pending), message = null) }
        }
    }

    private fun finishSilo(pending: SiloPendingSignIn, profile: HouseholdProfile, profileToken: String?) {
        silo?.profileId = profile.id
        silo?.profileToken = profileToken
        val session = SavedSession(
            serverUrl = pending.serverUrl,
            accessToken = silo?.accessToken ?: pending.accessToken,
            userId = pending.userId,
            userName = pending.userName,
            deviceId = pending.deviceId,
            serverName = pending.serverName,
            serverVersion = pending.serverVersion,
            backend = MediaBackend.Silo,
            refreshToken = silo?.refreshToken ?: pending.refreshToken,
            profileId = profile.id,
            profileToken = profileToken,
            profileName = profile.name,
            userRole = pending.userRole,
            isPrimaryProfile = profile.isPrimary,
        )
        vault.save(session)
        _state.update { it.copy(session = session, busy = false, screen = Screen.Library, message = null) }
        refreshLibrary()
    }

    private fun storeJellyfin(
        url: String,
        token: String,
        userId: String,
        userName: String,
        imageTag: String?,
        serverName: String?,
        serverVersion: String?,
    ) {
        val session = SavedSession(
            serverUrl = url,
            accessToken = token,
            userId = userId,
            userName = userName,
            deviceId = vault.deviceId,
            userImageTag = imageTag,
            serverName = serverName,
            serverVersion = serverVersion,
            backend = MediaBackend.Jellyfin,
        )
        vault.save(session)
        _state.update { it.copy(session = session) }
    }

    private fun restore(saved: SavedSession) {
        when (saved.backend) {
            MediaBackend.Jellyfin -> jellyfin = JellyfinLibrary(getApplication(), saved.serverUrl, saved.accessToken)
            MediaBackend.Silo -> {
                val client = newSilo(saved.serverUrl)
                client.accessToken = saved.accessToken
                client.refreshToken = saved.refreshToken
                client.profileId = saved.profileId
                client.profileToken = saved.profileToken
                silo = client
            }
        }
    }

    private suspend fun probe(url: String, preferred: MediaBackend): ServerReachability {
        val client = newSilo(url)
        val siloLabel = runCatching { client.serverLabel() }.getOrNull()
        if (siloLabel != null && (preferred == MediaBackend.Silo || preferred == MediaBackend.Jellyfin)) {
            if (preferred == MediaBackend.Silo || siloLabel.first != "Silo" || preferred == MediaBackend.Silo) {
                if (preferred == MediaBackend.Silo) return ServerReachability.Reachable(siloLabel.first, siloLabel.second)
            }
        }
        if (preferred == MediaBackend.Silo) {
            return siloLabel?.let { ServerReachability.Reachable(it.first, it.second) }
                ?: ServerReachability.Failed("That address did not answer as a Silo server.")
        }
        if (siloLabel != null && preferred == MediaBackend.Jellyfin) {
            // A host that answers Silo health is Silo even if the picker says Jellyfin.
            return ServerReachability.Reachable(siloLabel.first, siloLabel.second)
        }
        return JellyfinLibrary(getApplication(), url).probe()
    }

    private suspend fun currentHome(): HomeFeed = visibleHome(
        when (_state.value.session?.backend) {
            MediaBackend.Silo -> siloClient().home()
            else -> jellyfinClient().home(UUID.fromString(_state.value.session?.userId))
        },
    )

    private fun visibleHome(feed: HomeFeed): HomeFeed {
        val session = _state.value.session ?: return feed
        if (session.backend != MediaBackend.Jellyfin) return feed
        val app = getApplication<Application>()
        return feed.copy(
            continueWatching = HomeQueueHideStore.filter(app, feed.continueWatching, session.userId, JellyfinEnhancedHomeSurface.ContinueWatching),
            nextUp = HomeQueueHideStore.filter(app, feed.nextUp, session.userId, JellyfinEnhancedHomeSurface.NextUp),
        )
    }

    /** Jellyfin Enhanced hide; the title leaves the row right away and comes back if the server says no. Returns an error message. */
    suspend fun hideFromHome(item: MediaItem, surface: JellyfinEnhancedHomeSurface): String? {
        val session = _state.value.session ?: return null
        if (surface == JellyfinEnhancedHomeSurface.ContinueWatching && !plugins.state.value.jellyfin.enhancedRemoveContinueWatching) {
            return "Remove from Continue Watching is turned off in Jellyfin Enhanced."
        }
        val app = getApplication<Application>()
        HomeQueueHideStore.insert(app, item.id, session.userId, surface)
        _state.update { it.copy(home = visibleHome(it.home)) }
        return try {
            plugins.hideFromHome(item.id, surface)
            _state.value.session?.let { snapshots.saveHome(it, _state.value.home, _state.value.libraries) }
            null
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Throwable) {
            HomeQueueHideStore.remove(app, item.id, session.userId)
            refreshLibrary()
            error.message ?: "Jellyfin Enhanced couldn’t remove this title."
        }
    }

    fun openLibraryRoute(route: LibraryRoute) {
        _state.update { state ->
            if (state.tab == AppTab.Search) {
                val path = state.searchPath + route
                state.copy(searchPath = path, libraryGrids = state.libraryGrids.filterKeys { it in path || it in state.libraryPath }, message = null)
            } else {
                val path = state.libraryPath + route
                state.copy(libraryPath = path, libraryGrids = state.libraryGrids.filterKeys { it in path || it in state.searchPath }, message = null)
            }
        }
        when (route) {
            LibraryRoute.Genres -> loadGenres()
            is LibraryRoute.Discover -> plugins.loadDiscoverGrid(route.query)
            else -> loadLibraryGrid(route)
        }
    }

    fun applyLibraryQuery(route: LibraryRoute, query: CatalogBrowseQuery) {
        if (_state.value.libraryGrids[route]?.query == query) return
        updateGrid(route) { copy(query = query) }
        loadLibraryGrid(route)
    }

    fun refreshLibraryGrid(route: LibraryRoute) = loadLibraryGrid(route, refreshing = true)

    fun loadLibraryFilters(route: LibraryRoute) {
        viewModelScope.launch {
            val items = _state.value.libraryGrids[route]?.items.orEmpty()
            val options = runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> catalogOptionsFromItems(items)
                    else -> jellyfinClient().catalogFilters(userUuid(), jellyfinScope(route))
                }
            }.getOrDefault(catalogOptionsFromItems(items))
            updateGrid(route) { copy(filters = options) }
        }
    }

    fun updateLibraryLayout(layout: LibraryLayout) {
        layoutStore.save(layout)
        _state.update { it.copy(libraryLayout = layout) }
        loadRoomDetails()
    }

    fun resetLibraryLayout() {
        layoutStore.reset()
        _state.update { it.copy(libraryLayout = LibraryLayout()) }
        loadRoomDetails()
    }

    private fun updateGrid(route: LibraryRoute, transform: LibraryGridState.() -> LibraryGridState) {
        _state.update { state ->
            val current = state.libraryGrids[route] ?: LibraryGridState()
            state.copy(libraryGrids = state.libraryGrids + (route to current.transform()))
        }
    }

    private fun userUuid(): UUID = UUID.fromString(_state.value.session?.userId)

    private fun jellyfinScope(route: LibraryRoute): JellyfinScope {
        val titles = listOf(org.jellyfin.sdk.model.api.BaseItemKind.MOVIE, org.jellyfin.sdk.model.api.BaseItemKind.SERIES)
        return when (route) {
            is LibraryRoute.Room -> jellyfinClient().scope(route.room)
            is LibraryRoute.Genre -> JellyfinScope(titles, genreIds = listOf(route.genre.id))
            is LibraryRoute.Collection -> JellyfinScope(emptyList(), parentId = route.id)
            is LibraryRoute.Person -> JellyfinScope(titles, personIds = listOf(route.id))
            is LibraryRoute.Studio -> JellyfinScope(titles, studioIds = listOf(route.id))
            else -> JellyfinScope(titles)
        }
    }

    private fun loadLibraryGrid(route: LibraryRoute, refreshing: Boolean = false) {
        val query = _state.value.libraryGrids[route]?.query ?: CatalogBrowseQuery()
        val effective = if (route == LibraryRoute.Favorites) {
            query.copy(statuses = query.statuses + CatalogStatusFilter.Favorite)
        } else {
            query
        }
        updateGrid(route) { copy(loading = items.isEmpty() && !refreshing, refreshing = refreshing) }
        gridJobs.remove(route)?.cancel()
        gridJobs[route] = viewModelScope.launch {
            val gridJob = this
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val client = siloClient()
                        when (route) {
                            is LibraryRoute.Room -> client.catalog(client.catalogType(route.room.kind), route.room.id, effective)
                            is LibraryRoute.Genre -> client.catalog(null, null, effective.copy(genres = effective.genres + route.genre.name))
                            LibraryRoute.Favorites -> client.catalog(null, null, effective)
                            else -> emptyList()
                        }
                    }
                    else -> jellyfinClient().browse(userUuid(), jellyfinScope(route), effective) { page ->
                        if (gridJob.isActive) updateGrid(route) { copy(items = page, loading = false) }
                    }
                }
            }.onSuccess { items ->
                updateGrid(route) { copy(items = items, loading = false, refreshing = false) }
            }.onFailure { error ->
                if (error is CancellationException) throw error
                updateGrid(route) { copy(loading = false, refreshing = false) }
            }
        }
    }

    private fun loadGenres() {
        if (_state.value.libraryOverview.genres.isNotEmpty()) return
        _state.update { it.copy(libraryOverview = it.libraryOverview.copy(genresLoading = true)) }
        viewModelScope.launch {
            val genres = runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val items = _state.value.movies + _state.value.shows
                        catalogOptionsFromItems(items).genres.map { LibraryGenre(it.id, it.name) }
                    }
                    else -> jellyfinClient().genres(userUuid())
                }
            }.getOrDefault(emptyList())
            _state.update { it.copy(libraryOverview = it.libraryOverview.copy(genres = genres, genresLoading = false)) }
        }
    }

    private fun loadLibraryOverview() {
        overviewJob?.cancel()
        overviewJob = viewModelScope.launch {
            _state.update { it.copy(librariesLoading = it.libraries.isEmpty()) }
            if (_state.value.libraries.isNotEmpty()) loadRoomDetails()
            val silo = _state.value.session?.backend == MediaBackend.Silo
            launch {
                val counts = runCatching {
                    if (silo) siloClient().serverCounts() else jellyfinClient().serverCounts(userUuid())
                }.getOrNull()
                if (counts != null) _state.update { it.copy(libraryOverview = it.libraryOverview.copy(counts = counts)) }
            }
            if (!silo) {
                launch {
                    val collections = jellyfinClient().collectionPreview(userUuid())
                    _state.update { it.copy(libraryOverview = it.libraryOverview.copy(collections = collections)) }
                }
            }
            runCatching {
                if (silo) siloClient().libraries() else jellyfinClient().libraries(userUuid())
            }.onSuccess { rooms ->
                val changed = rooms != _state.value.libraries
                _state.update { it.copy(libraries = rooms, librariesLoading = false, message = null) }
                _state.value.session?.let { snapshots.saveHome(it, _state.value.home, rooms) }
                if (changed || _state.value.libraryOverview.covers.isEmpty()) loadRoomDetails()
            }.onFailure { error ->
                if (error is CancellationException) throw error
                _state.update { it.copy(librariesLoading = false, message = if (it.libraries.isEmpty()) error.message else it.message) }
            }
        }
    }

    private fun loadRoomDetails() {
        val state = _state.value
        val silo = state.session?.backend == MediaBackend.Silo
        val rooms = state.libraryLayout.displayed(state.libraries.libraryTabRooms(silo))
        viewModelScope.launch {
            rooms.forEach { room ->
                launch {
                    val counts = runCatching {
                        if (silo) siloClient().roomCounts(room) else jellyfinClient().roomCounts(userUuid(), room)
                    }.getOrNull() ?: return@launch
                    _state.update {
                        it.copy(libraryOverview = it.libraryOverview.copy(roomCounts = it.libraryOverview.roomCounts + (room.id to counts)))
                    }
                }
                if (room.kind == LibraryKind.LiveTV || state.libraryOverview.covers[room.id]?.isNotEmpty() == true) return@forEach
                launch {
                    val covers = runCatching {
                        if (silo) siloClient().previewItems(room) else jellyfinClient().previewItems(userUuid(), room)
                    }.getOrDefault(emptyList())
                    if (covers.isEmpty()) return@launch
                    _state.update {
                        it.copy(libraryOverview = it.libraryOverview.copy(covers = it.libraryOverview.covers + (room.id to covers)))
                    }
                }
            }
        }
    }

    fun applyCatalogQuery(tab: AppTab, query: CatalogBrowseQuery) {
        val current = if (tab == AppTab.Movies) _state.value.movieQuery else _state.value.showQuery
        if (current == query) return
        _state.update { if (tab == AppTab.Movies) it.copy(movieQuery = query) else it.copy(showQuery = query) }
        loadCatalog(tab)
    }

    fun refreshCatalog(tab: AppTab) {
        loadCatalog(tab, refreshing = true)
    }

    fun loadCatalogFilters(tab: AppTab) {
        viewModelScope.launch {
            val items = if (tab == AppTab.Movies) _state.value.movies else _state.value.shows
            val options = runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> catalogOptionsFromItems(items)
                    else -> {
                        val kind = if (tab == AppTab.Movies) {
                            org.jellyfin.sdk.model.api.BaseItemKind.MOVIE
                        } else {
                            org.jellyfin.sdk.model.api.BaseItemKind.SERIES
                        }
                        jellyfinClient().catalogFilters(UUID.fromString(_state.value.session?.userId), kind)
                    }
                }
            }.getOrDefault(catalogOptionsFromItems(items))
            _state.update { if (tab == AppTab.Movies) it.copy(movieFilters = options) else it.copy(showFilters = options) }
        }
    }

    private fun loadCatalog(tab: AppTab, refreshing: Boolean = false) {
        val session = _state.value.session
        val kind = if (tab == AppTab.Movies) "movies" else "shows"
        val query = if (tab == AppTab.Movies) _state.value.movieQuery else _state.value.showQuery
        if (query.isDefault) {
            session?.let { snapshots.loadCatalog(it, kind) }?.let { cached ->
                _state.update { if (tab == AppTab.Movies) it.copy(movies = cached) else it.copy(shows = cached) }
            }
        }
        val empty = if (tab == AppTab.Movies) _state.value.movies.isEmpty() else _state.value.shows.isEmpty()
        _state.update {
            if (tab == AppTab.Movies) {
                it.copy(moviesRefreshing = refreshing, moviesLoading = empty && !refreshing)
            } else {
                it.copy(showsRefreshing = refreshing, showsLoading = empty && !refreshing)
            }
        }
        val previous = if (tab == AppTab.Movies) movieCatalogJob else showCatalogJob
        previous?.cancel()
        val job = viewModelScope.launch {
            val catalogJob = this
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val type = if (tab == AppTab.Movies) "movie" else "series"
                        siloClient().catalog(type, browse = query)
                    }
                    else -> {
                        val itemKind = if (tab == AppTab.Movies) {
                            org.jellyfin.sdk.model.api.BaseItemKind.MOVIE
                        } else {
                            org.jellyfin.sdk.model.api.BaseItemKind.SERIES
                        }
                        jellyfinClient().catalog(UUID.fromString(_state.value.session?.userId), itemKind, query) { page ->
                            if (!catalogJob.isActive) return@catalog
                            _state.update { state ->
                                if (tab == AppTab.Movies) state.copy(movies = page, moviesLoading = false)
                                else state.copy(shows = page, showsLoading = false)
                            }
                        }
                    }
                }
            }.onSuccess { items ->
                _state.update {
                    if (tab == AppTab.Movies) {
                        it.copy(movies = items, moviesRefreshing = false, moviesLoading = false)
                    } else {
                        it.copy(shows = items, showsRefreshing = false, showsLoading = false)
                    }
                }
                if (query.isDefault) {
                    _state.value.session?.let { snapshots.saveCatalog(it, kind, items) }
                }
            }.onFailure { error ->
                if (error is CancellationException) throw error
                _state.update {
                    if (tab == AppTab.Movies) it.copy(moviesRefreshing = false, moviesLoading = false)
                    else it.copy(showsRefreshing = false, showsLoading = false)
                }
            }
        }
        if (tab == AppTab.Movies) movieCatalogJob = job else showCatalogJob = job
    }

    private suspend fun loadDetail(id: String): TitleDetail = when (_state.value.session?.backend) {
        MediaBackend.Silo -> siloClient().detail(id)
        else -> jellyfinClient().detail(UUID.fromString(_state.value.session?.userId), id)
    }

    private suspend fun report(plan: PlaybackPlan, position: Double, paused: Boolean, start: Boolean) {
        when (_state.value.session?.backend) {
            MediaBackend.Silo -> {
                val sessionId = plan.playSessionId ?: return
                if (start) siloClient().report(sessionId, position, false) else siloClient().report(sessionId, position, paused)
            }
            else -> {
                val library = jellyfinClient()
                if (start) library.reportStart(plan, position) else library.reportProgress(plan, position, paused)
            }
        }
    }

    private fun jellyfinClient(): JellyfinLibrary = jellyfin ?: throw ZelefinException.missingUser()

    private fun siloClient(): SiloClient = silo ?: throw ZelefinException.missingUser()

    private fun newSilo(url: String) = SiloClient(
        baseUrl = url,
        deviceId = vault.deviceId,
        deviceName = Build.MODEL ?: "Android",
        formFactor = if (getApplication<Application>().resources.configuration.smallestScreenWidthDp >= 600) "tablet" else "mobile",
        appVersion = "0.1.0",
        osVersion = Build.VERSION.RELEASE ?: "",
    )

    private fun ZelefinUiState.withItem(id: String, transform: MediaItem.() -> MediaItem): ZelefinUiState {
        fun List<MediaItem>.mapId() = map { if (it.id == id) it.transform() else it }
        return copy(
            home = home.copy(
                featured = home.featured.mapId(),
                continueWatching = home.continueWatching.mapId(),
                nextUp = home.nextUp.mapId(),
                recentMovies = home.recentMovies.mapId(),
                recentShows = home.recentShows.mapId(),
            ),
            movies = movies.mapId(),
            shows = shows.mapId(),
            libraryGrids = libraryGrids.mapValues { (_, grid) -> grid.copy(items = grid.items.mapId()) },
            detail = detail?.copy(
                item = if (detail.item.id == id) detail.item.transform() else detail.item,
                episodes = detail.episodes.mapId(),
                related = detail.related.mapId(),
            ),
        )
    }

    private fun launch(status: String, block: suspend () -> Unit) {
        _state.update { it.copy(busy = true, message = status) }
        viewModelScope.launch {
            runCatching { block() }
                .onFailure { error ->
                    _state.update { it.copy(busy = false, message = error.message ?: "Something went wrong.") }
                }
        }
    }
}

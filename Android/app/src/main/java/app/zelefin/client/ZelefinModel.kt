package app.zelefin.client

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.Uri
import android.os.Build
import app.zelefin.client.network.HomeNetwork
import app.zelefin.client.network.HomeNetworkProfile
import app.zelefin.client.network.HomeNetworkStore
import app.zelefin.client.network.ServerRoute
import app.zelefin.client.session.AccountPhoto
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.zelefin.client.jellyfin.CollectionEditor
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.client.jellyfin.JellyfinScope
import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteImageChoice
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.SyncPlayGroup
import app.zelefin.client.jellyfin.deleteLibraryItem
import app.zelefin.client.jellyfin.downloadRemoteArtwork
import app.zelefin.client.jellyfin.playOnSession
import app.zelefin.client.jellyfin.playbackSessions
import app.zelefin.client.jellyfin.refreshItemMetadata
import app.zelefin.client.jellyfin.remoteArtwork
import app.zelefin.client.jellyfin.reportedDeviceId
import app.zelefin.client.jellyfin.applyIdentify
import app.zelefin.client.jellyfin.randomTitle
import app.zelefin.client.jellyfin.searchIdentify
import app.zelefin.client.jellyfin.setWatchlisted
import app.zelefin.client.jellyfin.updateItemMetadata
import app.zelefin.client.jellyfin.watchlistItems
import app.zelefin.client.jellyfin.syncPlayCreateGroup
import app.zelefin.client.jellyfin.activityLog
import app.zelefin.client.jellyfin.adminMediaFolders
import app.zelefin.client.jellyfin.adminUser
import app.zelefin.client.jellyfin.adminUsers
import app.zelefin.client.jellyfin.changeOwnPassword
import app.zelefin.client.jellyfin.createServerBackup
import app.zelefin.client.jellyfin.deleteSplashscreen
import app.zelefin.client.jellyfin.deleteUserImage
import app.zelefin.client.jellyfin.parentalRatings
import app.zelefin.client.jellyfin.renameUser
import app.zelefin.client.jellyfin.resetUserPassword
import app.zelefin.client.jellyfin.restoreServerBackup
import app.zelefin.client.jellyfin.scanLibraries
import app.zelefin.client.jellyfin.scheduledTasks
import app.zelefin.client.jellyfin.serverBackups
import app.zelefin.client.jellyfin.serverBranding
import app.zelefin.client.jellyfin.setUserPassword
import app.zelefin.client.jellyfin.startScheduledTask
import app.zelefin.client.jellyfin.stopScheduledTask
import app.zelefin.client.jellyfin.syncPlayGroups
import app.zelefin.client.jellyfin.updateServerBranding
import app.zelefin.client.jellyfin.updateUserPolicy
import app.zelefin.client.jellyfin.uploadSplashscreen
import app.zelefin.client.jellyfin.syncPlayJoinGroup
import app.zelefin.client.jellyfin.syncPlayLeaveGroup
import app.zelefin.client.jellyfin.syncPlayPause
import app.zelefin.client.jellyfin.syncPlayReady
import app.zelefin.client.jellyfin.syncPlaySeek
import app.zelefin.client.jellyfin.syncPlaySetQueue
import app.zelefin.client.jellyfin.syncPlayStop
import app.zelefin.client.jellyfin.syncPlayUnpause
import app.zelefin.client.plugins.HomeQueueHideStore
import app.zelefin.client.plugins.JellyfinEnhancedHomeSurface
import app.zelefin.client.push.ZelefinPush
import app.zelefin.client.session.SessionSocket
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import org.jellyfin.sdk.model.api.PlaystateCommand
import org.jellyfin.sdk.model.api.SendCommandType
import app.zelefin.client.downloads.LocalPlayback
import app.zelefin.client.downloads.SessionDownloadBackend
import app.zelefin.client.downloads.ZelefinDownloads
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** [Room] is a custom library pinned to the dock; [ZelefinUiState.dockRoomId] says which one. */
enum class AppTab { Home, Movies, Shows, Library, Search, Collections, Favorites, Room }

/** customPrefs keys in the "zelefin" display preferences, same as iOS `DisplayPreferencesSync`. */
private const val SyncTabOrder = "tabOrder"
private const val SyncMerge = "mergeContinueNextUp"
private const val SyncHomeRowOrder = "homeRowOrder"
private const val SyncHomeRowHidden = "homeRowHidden"
private const val SyncHero = "featuredHeroContent"
private const val SyncLibraryOrder = "libraryOrder"
private const val SyncLibraryHidden = "libraryHidden"
private const val SyncLibraryPageHidden = "libraryPageHidden"

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
    data class Browse(val page: BrowsePage, val returnTo: Screen = Library) : Screen
    data class Settings(val returnTo: Screen) : Screen
    data class Profile(val returnTo: Screen) : Screen
    data class SettingsTopic(val id: String, val backTo: Screen) : Screen
}

data class ZelefinUiState(
    val screen: Screen = Screen.Connect,
    val tab: AppTab = AppTab.Home,
    val dockRoomId: String? = null,
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
    val libraryRefreshing: Boolean = false,
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
    val accounts: List<SavedSession> = emptyList(),
    val addAccount: AddAccountState = AddAccountState(),
    val localServerUrl: String? = null,
    val syncPlayGroupId: String? = null,
    val syncPlayGroupName: String? = null,
    val syncPlayPlaylistItemId: String? = null,
    /** Last title played on this account. Drives the dock's mini player. */
    val nowPlaying: MediaItem? = null,
)

sealed interface PlayerDirective {
    data object Play : PlayerDirective
    data object Pause : PlayerDirective
    data class Seek(val seconds: Double) : PlayerDirective
}

/** Settings → Add User / Add Account. [pending] is set while a Silo login waits for a household profile. */
data class AddAccountState(
    val busy: Boolean = false,
    val message: String? = null,
    val pending: SiloPendingSignIn? = null,
    val pinFor: HouseholdProfile? = null,
)

class ZelefinModel(application: Application) : AndroidViewModel(application) {
    private val vault = SessionVault(application)
    private val snapshots = SnapshotStore(application)
    private val layoutStore = LibraryLayoutStore(application)
    private val queryStore = CatalogQueryStore(application)
    private val searchHistory = SearchHistoryStore(application)
    private val nowPlayingStore = NowPlayingStore(application)
    private val _state = MutableStateFlow(
        ZelefinUiState(libraryLayout = layoutStore.load(), search = LibrarySearchState(recents = searchHistory.load())),
    )
    private var searchJob: Job? = null
    val plugins = PluginsController(
        application = application,
        scope = viewModelScope,
        session = { _state.value.session },
        allSessions = { vault.accounts() },
        siloIdentity = { siloClient().identity() },
        tmdbCatalog = { jellyfinClient().tmdbCatalog(userUuid()) },
    )
    val state: StateFlow<ZelefinUiState> = _state.asStateFlow()

    private var jellyfin: JellyfinLibrary? = null
    private var movieCatalogJob: Job? = null
    private var showCatalogJob: Job? = null
    private var overviewJob: Job? = null
    /** The account whose Library rooms are loaded. Counts still refresh on resume and pull. */
    private var overviewLoadedFor: String? = null
    private val gridJobs = mutableMapOf<LibraryRoute, Job>()
    private var silo: SiloClient? = null
    private var activePlan: PlaybackPlan? = null
    private var lastReported = 0.0
    private var localPlan: PlaybackPlan? = null
    private var quickConnectJob: Job? = null
    private val homeNetworks = HomeNetworkStore(application)
    private var routeJob: Job? = null
    private var pendingSilo: SiloClient? = null
    private val sessionSocket = SessionSocket(application, viewModelScope)
    private val _playerDirectives = MutableSharedFlow<PlayerDirective>(replay = 1, extraBufferCapacity = 8)
    val playerDirectives: SharedFlow<PlayerDirective> = _playerDirectives.asSharedFlow()
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = refreshRoute()
        override fun onLost(network: Network) = refreshRoute()
    }

    init {
        vault.applyGateway()
        val secrets = vault.loadGateway()
        val saved = vault.current()
        _state.update {
            it.copy(gatewayId = secrets.clientId, gatewaySecret = secrets.clientSecret, session = saved, accounts = vault.accounts())
        }
        runCatching { application.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(networkCallback) }
        if (saved != null) {
            restore(saved)
            _state.update { it.copy(screen = Screen.Library, backend = saved.backend) }
            applyStartPage()
            viewModelScope.launch {
                applyCachedSnapshots(saved)
                refreshLibrary()
            }
            bindSessionSocket(saved)
        }
    }

    init {
        ZelefinDownloads.attach(application, SessionDownloadBackend { silo }, _state.map { it.session })
    }

    init {
        viewModelScope.launch {
            _state.map { it.session?.accountId }.distinctUntilChanged().collect { accountId ->
                _state.update { it.copy(nowPlaying = accountId?.let(nowPlayingStore::load)) }
            }
        }
    }

    /**
     * The cached Home feed and catalogs paint the first screen. Decoding them (a full catalog can
     * be megabytes of JSON) on the main thread made the app stutter right after opening.
     */
    private suspend fun applyCachedSnapshots(session: SavedSession) {
        val (home, movies, shows) = withContext(Dispatchers.IO) {
            Triple(
                snapshots.loadHome(session),
                snapshots.loadCatalog(session, "movies"),
                snapshots.loadCatalog(session, "shows"),
            )
        }
        if (_state.value.session?.accountId != session.accountId) return
        _state.update {
            it.copy(
                home = home?.first?.let(::visibleHome) ?: it.home,
                libraries = if (it.libraries.isEmpty()) home?.second.orEmpty() else it.libraries,
                movies = if (it.movies.isEmpty()) movies.orEmpty() else it.movies,
                shows = if (it.shows.isEmpty()) shows.orEmpty() else it.shows,
            )
        }
    }

    fun playNowPlaying() {
        _state.value.nowPlaying?.let { play(it) }
    }

    fun clearNowPlaying() {
        val accountId = _state.value.session?.accountId ?: return
        _state.update { it.copy(nowPlaying = null) }
        nowPlayingStore.save(null, accountId)
    }

    private fun rememberNowPlaying(item: MediaItem) {
        val accountId = _state.value.session?.accountId ?: return
        _state.update { it.copy(nowPlaying = item) }
        nowPlayingStore.save(item, accountId)
    }

    private fun noteNowPlayingPosition(itemId: String, positionSeconds: Double) {
        val current = _state.value.nowPlaying ?: return
        if (current.id != itemId || positionSeconds <= 0.0) return
        rememberNowPlaying(current.copy(playbackPosition = positionSeconds))
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

    /** On cold launch, open the page the user chose as their start page (Home by default). */
    private fun applyStartPage() {
        val start = app.zelefin.client.ui.StartPagePreferences.tab
        if (start == app.zelefin.client.ui.DockTab.Home) return
        val appTab = start.appTab ?: return
        if (!app.zelefin.client.ui.TabPreferences.isShown(start)) return
        selectTab(appTab)
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
        if (tab == AppTab.Collections) ensureBrowseGrid(LibraryRoute.AllCollections)
        if (tab == AppTab.Favorites) ensureBrowseGrid(LibraryRoute.Favorites)
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
        val target = if (item.isYouTube && item.kind == MediaKind.Episode) item.id else item.seriesDetailItemId ?: item.id
        val current = _state.value.screen
        val returnTo = when (current) {
            is Screen.Detail -> if (current.id == target) current.returnTo else current
            is Screen.Browse -> current
            else -> Screen.Library
        }
        showDetail(target, returnTo)
    }

    /** Pushes a full list page from a row chevron (iOS `NavigationLink` on section headers). */
    fun openBrowse(page: BrowsePage) {
        val current = _state.value.screen
        if (current is Screen.Player || current is Screen.Settings || current is Screen.Profile || current is Screen.SettingsTopic) return
        _state.update { it.copy(screen = Screen.Browse(page, current), message = null) }
        (page as? BrowsePage.Library)?.let { ensureBrowseGrid(it.route) }
    }

    fun ensureBrowseGrid(route: LibraryRoute) {
        val grid = _state.value.libraryGrids[route]
        if (grid != null && (grid.items.isNotEmpty() || grid.loading)) return
        loadLibraryGrid(route)
    }

    /** Reloads the open title page in place, keeping collection membership. */
    fun refreshDetail() {
        val target = (_state.value.screen as? Screen.Detail)?.id ?: return
        viewModelScope.launch {
            runCatching { loadDetail(target) }
                .onSuccess { fresh ->
                    _state.update { state ->
                        val current = state.detail
                        if ((state.screen as? Screen.Detail)?.id != target) {
                            state
                        } else {
                            state.copy(detail = fresh.copy(collections = current?.takeIf { it.item.id == target }?.collections ?: fresh.collections))
                        }
                    }
                    _state.value.session?.let { saved ->
                        _state.value.detail?.takeIf { it.item.id == target }?.let { snapshots.saveDetail(saved, it) }
                    }
                }
                .onFailure { if (it is CancellationException) throw it }
        }
    }

    /** Other Jellyfin clients this user may control, leaving this phone out (iOS `PlayOnDeviceSheet.targets`). */
    suspend fun remotePlayTargets(): List<RemoteSession> {
        val client = jellyfinClient()
        val me = client.reportedDeviceId
        return client.playbackSessions(userUuid()).filter { it.canControl && !it.isThisDevice(me) }
    }

    suspend fun playOnRemote(session: RemoteSession, item: MediaItem) {
        jellyfinClient().playOnSession(session.id, item)
    }

    suspend fun syncPlayGroups(): List<SyncPlayGroup> = jellyfinClient().syncPlayGroups()

    /** Creates or joins a group only when needed, then queues the title. Playback opens from the socket queue. */
    suspend fun playInSyncPlay(item: MediaItem, joinGroupId: String?, newGroupName: String?) {
        val client = jellyfinClient()
        if (joinGroupId != null) {
            client.syncPlayJoinGroup(joinGroupId)
            val name = runCatching { client.syncPlayGroups().firstOrNull { it.id == joinGroupId }?.name }.getOrNull()
            _state.update { it.copy(syncPlayGroupId = joinGroupId, syncPlayGroupName = name ?: it.syncPlayGroupName) }
        } else if (_state.value.syncPlayGroupId == null) {
            val name = newGroupName?.trim()?.takeIf { it.isNotEmpty() } ?: "${_state.value.session?.userName ?: "Zelefin"}’s group"
            val group = client.syncPlayCreateGroup(name)
            _state.update { it.copy(syncPlayGroupId = group.id, syncPlayGroupName = group.name) }
        }
        val queued = playbackTarget(item)
        client.syncPlaySetQueue(queued)
        play(queued, fromSyncPlay = true)
    }

    suspend fun createSyncPlayGroup(name: String) {
        val group = jellyfinClient().syncPlayCreateGroup(name.trim())
        _state.update { it.copy(syncPlayGroupId = group.id, syncPlayGroupName = group.name) }
    }

    suspend fun joinSyncPlayGroup(group: SyncPlayGroup) {
        jellyfinClient().syncPlayJoinGroup(group.id)
        _state.update { it.copy(syncPlayGroupId = group.id, syncPlayGroupName = group.name) }
    }

    suspend fun leaveSyncPlayGroup() {
        jellyfinClient().syncPlayLeaveGroup()
        _state.update { it.copy(syncPlayGroupId = null, syncPlayGroupName = null, syncPlayPlaylistItemId = null) }
    }

    suspend fun refreshMetadata(item: MediaItem) {
        jellyfinClient().refreshItemMetadata(item.id)
        viewModelScope.launch {
            kotlinx.coroutines.delay(4_000)
            refreshDetail()
        }
    }

    suspend fun remoteArtwork(item: MediaItem, kind: RemoteArtworkKind): List<RemoteImageChoice> =
        jellyfinClient().remoteArtwork(item.id, kind)

    suspend fun applyRemoteArtwork(item: MediaItem, kind: RemoteArtworkKind, choice: RemoteImageChoice) {
        jellyfinClient().downloadRemoteArtwork(item.id, kind, choice.url)
        refreshDetail()
    }

    /** Deletes the title, leaves its page, and refreshes Home and any open grids. */
    suspend fun deleteFromLibrary(item: MediaItem) {
        jellyfinClient().deleteLibraryItem(item.id)
        val showing = _state.value.screen as? Screen.Detail
        if (showing != null && (showing.id == item.id || _state.value.detail?.item?.id == item.id)) back()
        _state.update { state ->
            state.copy(libraryGrids = state.libraryGrids.mapValues { (_, grid) -> grid.copy(items = grid.items.filterNot { it.id == item.id }) })
        }
        refreshLibrary()
    }

    fun sessionsClient(): JellyfinLibrary? = jellyfin.takeIf { _state.value.session?.usesSilo == false }

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
            is Screen.Settings, is Screen.SettingsTopic -> current
            else -> current
        }
        _state.update { it.copy(screen = Screen.SettingsTopic(id, backTo), message = null) }
    }

    fun closePlayer() {
        if (_state.value.syncPlayGroupId != null) {
            viewModelScope.launch { runCatching { jellyfinClient().syncPlayStop() } }
        }
        if (_state.value.screen is Screen.Player) back()
    }

    fun syncPlayPlayerReady() {
        val screen = _state.value.screen as? Screen.Player ?: return
        notifySyncPlayReady(screen.plan.startTimeSeconds)
    }

    fun forwardSyncPlay(directive: PlayerDirective) {
        if (_state.value.syncPlayGroupId == null) return
        viewModelScope.launch {
            runCatching {
                val client = jellyfinClient()
                when (directive) {
                    PlayerDirective.Pause -> client.syncPlayPause()
                    PlayerDirective.Play -> client.syncPlayUnpause()
                    is PlayerDirective.Seek -> {
                        client.syncPlaySeek(directive.seconds)
                        client.syncPlayReady(true, _state.value.syncPlayPlaylistItemId, directive.seconds)
                    }
                }
            }
        }
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
            is Screen.Browse -> screen.returnTo
            is Screen.Pin -> Screen.Profiles(screen.pending)
            is Screen.Settings -> screen.returnTo
            is Screen.Profile -> screen.returnTo
            is Screen.SettingsTopic -> screen.backTo
            else -> return
        }
        _state.update { it.copy(screen = next, message = null) }
        if (next is Screen.Detail && _state.value.detail?.item?.id != next.id) showDetail(next.id, next.returnTo)
    }

    suspend fun loadPerson(id: String): app.zelefin.core.CreditPerson? {
        val session = _state.value.session ?: return null
        if (session.backend == MediaBackend.Silo) return null
        val userId = runCatching { UUID.fromString(session.userId) }.getOrNull() ?: return null
        return runCatching { jellyfinClient().person(userId, id) }.getOrNull()
    }

    /** A fresh title read drops person tags the cached copy already learned; keep those so the row never blanks. */
    private fun TitleDetail.keepingCastPhotos(from: TitleDetail?): TitleDetail {
        val known = from?.item?.people?.filter { !it.imageTag.isNullOrBlank() }?.associateBy { it.id }.orEmpty()
        if (known.isEmpty()) return this
        val people = item.people.map { person ->
            if (!person.imageTag.isNullOrBlank()) return@map person
            val cached = known[person.id] ?: return@map person
            person.copy(imageTag = cached.imageTag, overview = cached.overview ?: person.overview, birthYear = cached.birthYear ?: person.birthYear)
        }
        return copy(item = item.copy(people = people))
    }

    /** Cast portraits arrive once Jellyfin refreshes each person; swap them into the open title as they land. */
    private suspend fun fillCastPhotos(target: String, people: List<app.zelefin.core.CreditPerson>) {
        val session = _state.value.session ?: return
        if (session.backend == MediaBackend.Silo || people.isEmpty()) return
        val userId = runCatching { UUID.fromString(session.userId) }.getOrNull() ?: return
        runCatching {
            jellyfinClient().peopleWithPhotos(userId, people) { updated ->
                _state.update { state ->
                    val current = state.detail
                    if ((state.screen as? Screen.Detail)?.id == target && current?.item?.id == target) {
                        state.copy(detail = current.copy(item = current.item.copy(people = updated)))
                    } else {
                        state
                    }
                }
                _state.value.detail?.takeIf { it.item.id == target }?.let { snapshots.saveDetail(session, it) }
            }
        }
    }

    private fun showDetail(target: String, returnTo: Screen) {
        val session = _state.value.session
        val cached = session?.let { snapshots.loadDetail(it, target) } ?: ZelefinDownloads.offlineDetail(target)
        _state.update { it.copy(screen = Screen.Detail(target, returnTo), detail = cached, busy = cached == null, message = null) }
        viewModelScope.launch {
            runCatching { loadDetail(target) }
                .onSuccess { fresh ->
                    val detail = fresh.keepingCastPhotos(from = cached)
                    _state.value.session?.let { snapshots.saveDetail(it, detail) }
                    _state.update { state ->
                        val showing = state.screen as? Screen.Detail
                        if (showing?.id == target) state.copy(detail = detail, busy = false) else state
                    }
                    launch { fillCastPhotos(target, detail.item.people) }
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

    fun toggleWatchlist(item: MediaItem) {
        if (_state.value.session?.usesSilo == true) return
        val watchlisted = !item.isWatchlisted
        viewModelScope.launch {
            runCatching { jellyfinClient().setWatchlisted(userUuid(), item.id, watchlisted) }
                .onSuccess {
                    _state.update { state -> state.withItem(item.id) { copy(isWatchlisted = watchlisted) } }
                    if (_state.value.libraryPath.lastOrNull() == LibraryRoute.Watchlist ||
                        _state.value.searchPath.lastOrNull() == LibraryRoute.Watchlist
                    ) {
                        loadLibraryGrid(LibraryRoute.Watchlist, refreshing = true)
                    }
                }
                .onFailure { error -> _state.update { it.copy(message = error.message) } }
        }
    }

    fun pickRandomTitle() {
        viewModelScope.launch {
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val pool = (_state.value.movies + _state.value.shows).ifEmpty {
                            siloClient().catalog(null, null, CatalogBrowseQuery(sort = CatalogSortField.Random))
                        }
                        pool.randomOrNull() ?: throw ZelefinException.server("Nothing to pick yet.")
                    }
                    else -> jellyfinClient().randomTitle(userUuid())
                        ?: throw ZelefinException.server("Nothing to pick yet.")
                }
            }.onSuccess { openItem(it) }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    _state.update { it.copy(message = error.message) }
                }
        }
    }

    suspend fun identifyHits(item: MediaItem) = jellyfinClient().searchIdentify(item)

    suspend fun applyIdentify(item: MediaItem, hit: app.zelefin.client.jellyfin.RemoteIdentifyHit) {
        jellyfinClient().applyIdentify(item.id, hit)
        refreshDetail()
    }

    suspend fun saveItemMetadata(item: MediaItem, draft: app.zelefin.client.jellyfin.ItemMetadataDraft) {
        jellyfinClient().updateItemMetadata(userUuid(), item.id, draft)
        refreshDetail()
    }

    fun downloadRelated(item: MediaItem) {
        viewModelScope.launch {
            runCatching {
                val fromDetail = _state.value.detail
                val episodes = when (item.kind) {
                    MediaKind.Series, MediaKind.Season -> {
                        val loaded = fromDetail?.takeIf {
                            it.item.id == item.id || it.item.id == item.seriesId || it.episodes.any { episode -> episode.id == item.id }
                        } ?: if (_state.value.session?.usesSilo == true) {
                            fromDetail
                        } else {
                            jellyfinClient().detail(userUuid(), item.seriesId ?: item.id)
                        }
                        val all = loaded?.episodes.orEmpty()
                        if (item.kind == MediaKind.Season) all.filter { it.seasonIndex == item.seasonIndex } else all
                    }
                    else -> listOf(item)
                }
                app.zelefin.client.downloads.ZelefinDownloads.startAll(episodes.ifEmpty { listOf(item) })
            }.onFailure { error ->
                if (error is CancellationException) throw error
                _state.update { it.copy(message = error.message) }
            }
        }
    }

    suspend fun loadCollections(itemId: String): CollectionEditor {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        if (session.usesSilo) throw ZelefinException.server("Collections aren't available on this server.")
        return jellyfinClient().collectionEditor(UUID.fromString(session.userId), itemId)
    }

    suspend fun collectionPosterMembers(parentId: String): List<MediaItem> {
        val session = _state.value.session ?: return emptyList()
        if (session.usesSilo) return emptyList()
        return runCatching {
            jellyfinClient().collectionPosterMembers(UUID.fromString(session.userId), parentId)
        }.getOrDefault(emptyList())
    }

    suspend fun setCollectionMember(collectionId: String, itemId: String, member: Boolean) {
        val client = jellyfinClient()
        if (member) client.addToCollection(collectionId, itemId) else client.removeFromCollection(collectionId, itemId)
    }

    suspend fun createCollection(name: String, itemId: String) {
        jellyfinClient().createCollection(name, itemId)
    }

    /** [bitrateOverride] pins the stream cap (live adaptive steps); null lets Playback settings decide. */
    fun play(item: MediaItem, bitrateOverride: Int? = null, fromSyncPlay: Boolean = false) {
        val returnTo = _state.value.screen.let { if (it is Screen.Player) it.returnTo else it }
        launch("Starting playback…") {
            val target = resolvePlaybackTarget(item)
            rememberNowPlaying(target)
            if (!fromSyncPlay && _state.value.syncPlayGroupId != null && _state.value.session?.backend == MediaBackend.Jellyfin) {
                runCatching { jellyfinClient().syncPlaySetQueue(target) }
                    .onFailure { error -> _state.update { it.copy(message = error.message) } }
            }
            _state.value.session?.let { HomeQueueHideStore.remove(getApplication(), target.id, it.userId) }
            when (val local = ZelefinDownloads.localPlayback(target)) {
                is LocalPlayback.Ready -> {
                    activePlan = null
                    localPlan = local.plan
                    _state.update { it.copy(busy = false, screen = Screen.Player(local.plan, returnTo), message = null) }
                    notifySyncPlayReady(local.plan.startTimeSeconds)
                    return@launch
                }
                LocalPlayback.Missing -> {
                    _state.update { it.copy(busy = false, message = null) }
                    return@launch
                }
                LocalPlayback.None -> Unit
            }
            val appContext = getApplication<Application>()
            val audioLanguage = PlaybackPreferences.audioLanguage(appContext)
            val subtitleLanguage = PlaybackPreferences.subtitleLanguage(appContext)
            val plan = when (_state.value.session?.backend) {
                // Like iOS, Silo starts from the original file; only a picked quality (or a live step) caps it.
                MediaBackend.Silo -> siloClient().playback(
                    item = target,
                    appVersion = BuildConfig.VERSION_NAME,
                    osVersion = Build.VERSION.RELEASE ?: "",
                    model = Build.MODEL ?: "Android",
                    maxBitrate = bitrateOverride ?: PlaybackPreferences.selectedQuality(appContext).takeIf { it != PlaybackQuality.Auto }?.bits,
                    audioLanguage = audioLanguage,
                    subtitleLanguage = subtitleLanguage,
                )
                else -> {
                    val userId = UUID.fromString(_state.value.session?.userId)
                    val client = jellyfinClient()
                    // The user's Jellyfin account settings (Settings → Playback) decide the starting
                    // streams, so the device-side language picks only apply to Silo.
                    client.playback(
                        userId,
                        target,
                        PlaybackPreferences.AUTOMATIC,
                        PlaybackPreferences.AUTOMATIC,
                        preferSdh = PlaybackPreferences.preferSdh(appContext),
                    ) { sourceBitrate ->
                        bitrateOverride ?: streamingCap(appContext, client, sourceBitrate)
                    }
                }
            }
            val reported = PlaybackResumePolicy.reportStartPosition(0.0, plan.startTimeSeconds)
            activePlan = plan
            lastReported = reported
            runCatching { report(plan, reported, paused = false, start = true) }
            val routed = plan.copy(
                streamUrl = ServerRoute.rewrite(plan.streamUrl),
                externalSubtitles = plan.externalSubtitles.map { it.copy(url = ServerRoute.rewrite(it.url)) },
            )
            _state.update { it.copy(busy = false, screen = Screen.Player(routed, returnTo), message = null) }
            notifySyncPlayReady(routed.startTimeSeconds)
        }
    }

    /**
     * Auto on a home server Direct Plays. A guessed cap used to sit under the file bitrate, so
     * Jellyfin answered BitrateExceedsLimit and held PlaybackInfo until the transcode started.
     * That wait is the long pause before the player appears. A measured remote link can still
     * cap, and a quality the user picked still wins.
     */
    private fun streamingCap(context: Context, client: JellyfinLibrary, sourceBitrate: Int?): Int {
        val selected = PlaybackPreferences.selectedQuality(context)
        if (selected == PlaybackQuality.Auto && ServerUrl.isInternalHost(playbackHost())) {
            return PlaybackQuality.MAX_BITRATE
        }
        viewModelScope.launch {
            runCatching { AdaptiveBitrateStore.refreshIfNeeded(context, client::measureBitrate) }
        }
        return AdaptiveBitrateStore.resolvedBitsPerSecond(context, sourceBitrate)
    }

    private fun playbackHost(): String {
        val raw = ServerRoute.activeLocal ?: _state.value.session?.serverUrl.orEmpty()
        return runCatching { java.net.URI(raw).host }.getOrNull().orEmpty()
    }

    /** Ignores reports from a player that is still on screen after the next episode took over. */
    fun playbackProgress(plan: PlaybackPlan, positionSeconds: Double, paused: Boolean) {
        if (isCurrentPlayback(plan)) playbackProgress(positionSeconds, paused)
    }

    fun playbackStopped(plan: PlaybackPlan, positionSeconds: Double) {
        if (isCurrentPlayback(plan)) playbackStopped(positionSeconds)
    }

    fun playNext(finished: PlaybackPlan, positionSeconds: Double, next: MediaItem) {
        playbackStopped(finished, positionSeconds)
        play(next)
    }

    /** Restarts the same title at the current spot so a subtitle saved from the player shows up. */
    fun reloadPlayback(current: PlaybackPlan, positionSeconds: Double) {
        playbackStopped(current, positionSeconds)
        play(current.item.copy(playbackPosition = positionSeconds))
    }

    /**
     * The player lost the stream ("Source error"). Ask which server address answers right now,
     * then open a new playback session from the same spot. Reusing the dead URL does not.
     */
    fun recoverPlayback(current: PlaybackPlan, positionSeconds: Double) {
        playbackStopped(current, positionSeconds)
        val item = current.item.copy(playbackPosition = positionSeconds)
        routeJob?.cancel()
        viewModelScope.launch {
            refreshRouteNow()
            play(item)
        }
    }

    /** Live adaptive bitrate: re-requests the same title at [bitsPerSecond] from the current spot. */
    fun reloadPlaybackAtBitrate(current: PlaybackPlan, positionSeconds: Double, bitsPerSecond: Int) {
        if (!isCurrentPlayback(current) || localPlan != null) return
        playbackStopped(current, positionSeconds)
        play(current.item.copy(playbackPosition = positionSeconds), bitrateOverride = bitsPerSecond)
    }

    /** Settings → Playback → Test Connection. Throws with the iOS copy when nothing downloads. */
    suspend fun testConnection(): BitrateProbeResult {
        val session = _state.value.session ?: throw ZelefinException.server("Sign in to test this connection.")
        val transport = NetworkPathSnapshot.current(getApplication()).transport
        val size = AdaptiveBitratePolicy.SETTINGS_SAMPLE_BYTES
        val timeout = AdaptiveBitratePolicy.SETTINGS_PROBE_TIMEOUT_MILLIS
        val result = if (session.usesSilo) {
            siloClient().measureBitrate(size, timeout, transport)
        } else {
            jellyfinClient().measureBitrate(size, timeout, transport)
        } ?: throw ZelefinException.server(
            "Zelefin could not download the demo file from this server. Check the connection and try again.",
        )
        AdaptiveBitrateStore.record(result)
        return result
    }

    /** Stores the language picks and, on Jellyfin, mirrors them into the user's server configuration. */
    fun applyPlaybackLanguages(audioCode: String, subtitleCode: String) {
        val appContext = getApplication<Application>()
        PlaybackPreferences.setAudioLanguage(appContext, audioCode)
        PlaybackPreferences.setSubtitleLanguage(appContext, subtitleCode)
        val session = _state.value.session ?: return
        if (session.usesSilo) return
        viewModelScope.launch {
            runCatching {
                jellyfinClient().applyPlaybackLanguages(UUID.fromString(session.userId), audioCode, subtitleCode)
            }
        }
    }

    /** Admin-only: starts a scan of every Jellyfin library. */
    suspend fun scanLibraries() {
        val session = _state.value.session
        if (session == null || session.usesSilo) throw ZelefinException.server("Sign in to a Jellyfin server to scan its libraries.")
        jellyfinClient().scanLibraries()
    }

    suspend fun activityLog() = jellyfinClient().activityLog()
    suspend fun serverBackups() = jellyfinClient().serverBackups()
    suspend fun createServerBackup() = jellyfinClient().createServerBackup()
    suspend fun restoreServerBackup(backup: app.zelefin.client.jellyfin.ServerBackup) = jellyfinClient().restoreServerBackup(backup)
    suspend fun serverBranding() = jellyfinClient().serverBranding()
    suspend fun updateServerBranding(branding: app.zelefin.client.jellyfin.ServerBranding) = jellyfinClient().updateServerBranding(branding)
    suspend fun uploadSplashscreen(jpeg: ByteArray) = jellyfinClient().uploadSplashscreen(jpeg)
    suspend fun deleteSplashscreen() = jellyfinClient().deleteSplashscreen()
    suspend fun scheduledTasks() = jellyfinClient().scheduledTasks()
    suspend fun startScheduledTask(id: String) = jellyfinClient().startScheduledTask(id)
    suspend fun stopScheduledTask(id: String) = jellyfinClient().stopScheduledTask(id)
    suspend fun adminUsers() = jellyfinClient().adminUsers()
    suspend fun adminUser(id: String) = jellyfinClient().adminUser(id)
    suspend fun adminMediaFolders() = jellyfinClient().adminMediaFolders()
    suspend fun parentalRatings() = jellyfinClient().parentalRatings()
    suspend fun updateUserPolicy(userId: String, policy: org.jellyfin.sdk.model.api.UserPolicy) = jellyfinClient().updateUserPolicy(userId, policy)
    suspend fun renameUser(account: app.zelefin.client.jellyfin.ServerUserAccount, name: String) {
        jellyfinClient().renameUser(account, name)
        val session = _state.value.session ?: return
        if (session.userId == account.id) {
            val updated = session.copy(userName = name.trim())
            vault.save(updated)
            _state.update { it.copy(session = updated, accounts = vault.accounts()) }
        }
    }
    suspend fun resetUserPassword(userId: String) = jellyfinClient().resetUserPassword(userId)
    suspend fun setUserPassword(userId: String, password: String) = jellyfinClient().setUserPassword(userId, password)
    suspend fun deleteUserImage(userId: String) {
        jellyfinClient().deleteUserImage(userId)
        refreshEditedUserPhoto(userId, null)
    }
    suspend fun uploadUserPhoto(userId: String, uri: Uri) {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        val jpeg = AccountPhoto.jpeg(getApplication(), uri)
        AccountPhoto.upload(session, jpeg, userId)
        val tag = if (userId == session.userId) AccountPhoto.imageTag(session) else jellyfinClient().adminUser(userId).primaryImageTag
        refreshEditedUserPhoto(userId, tag)
    }

    private fun refreshEditedUserPhoto(userId: String, tag: String?) {
        val session = _state.value.session ?: return
        if (session.userId != userId) return
        val updated = session.copy(userImageTag = tag ?: session.userImageTag)
        vault.save(updated)
        _state.update { it.copy(session = updated, accounts = vault.accounts()) }
    }

    suspend fun jellyfinPlaybackPreferences(): JellyfinPlaybackPreferences {
        val session = _state.value.session
        if (session == null || session.usesSilo) throw ZelefinException.server("Sign in to a Jellyfin server to change these settings.")
        return jellyfinClient().playbackPreferences()
    }

    /**
     * Jellyfin picks the starting streams from these, so the device-side language picks step
     * aside; otherwise an older local pick would override what the user just chose.
     */
    suspend fun saveJellyfinPlaybackPreferences(preferences: JellyfinPlaybackPreferences) {
        val session = _state.value.session
        if (session == null || session.usesSilo) throw ZelefinException.server("Sign in to a Jellyfin server to change these settings.")
        jellyfinClient().savePlaybackPreferences(UUID.fromString(session.userId), preferences)
        val appContext = getApplication<Application>()
        PlaybackPreferences.setAudioLanguage(appContext, PlaybackPreferences.AUTOMATIC)
        PlaybackPreferences.setSubtitleLanguage(appContext, PlaybackPreferences.AUTOMATIC)
    }

    suspend fun nextEpisode(item: MediaItem): MediaItem? {
        if (item.kind != MediaKind.Episode) return null
        val seriesId = item.seriesDetailItemId ?: return null
        val episodes = MediaItem.orderedEpisodes(runCatching { loadDetail(seriesId).episodes }.getOrDefault(emptyList()))
        val index = episodes.indexOfFirst { it.id == item.id }
        if (index >= 0) return episodes.getOrNull(index + 1)
        val season = item.seasonIndex ?: return null
        val episode = item.episodeIndex ?: return null
        return episodes.firstOrNull { candidate ->
            val candidateSeason = candidate.seasonIndex ?: Int.MIN_VALUE
            val candidateEpisode = candidate.episodeIndex ?: Int.MIN_VALUE
            candidateSeason > season || (candidateSeason == season && candidateEpisode > episode)
        }
    }

    private fun isCurrentPlayback(plan: PlaybackPlan): Boolean {
        localPlan?.let { return it.item.id == plan.item.id }
        val active = activePlan ?: return false
        return active.item.id == plan.item.id && active.playSessionId == plan.playSessionId
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
        (localPlan ?: activePlan)?.item?.id?.let { noteNowPlayingPosition(it, positionSeconds) }
        localPlan?.let { local ->
            localPlan = null
            ZelefinDownloads.updatePosition(local.item.id, positionSeconds)
            return
        }
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

    /** Movie, show, and episode totals. Called when the app returns to the foreground. */
    fun refreshLibraryStats() {
        if (_state.value.session == null) return
        viewModelScope.launch {
            val silo = _state.value.session?.backend == MediaBackend.Silo
            val counts = runCatching {
                if (silo) siloClient().serverCounts() else jellyfinServerCounts(_state.value.libraries)
            }.getOrNull()
            if (counts != null) _state.update { it.copy(libraryOverview = it.libraryOverview.copy(counts = counts)) }
            if (_state.value.libraries.isNotEmpty()) loadRoomDetails(onlyMissing = false)
        }
    }

    fun refreshLibrary() {
        plugins.ensureDetected()
        viewModelScope.launch {
            val session = _state.value.session
            val cached = if (_state.value.home == HomeFeed()) {
                session?.let { withContext(Dispatchers.IO) { snapshots.loadHome(it) } }
            } else {
                null
            }
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
                    refreshLibraryStats()
                }
                .onFailure { error -> _state.update { it.copy(homeRefreshing = false, message = error.message) } }
        }
    }

    /** Signs out the current account only; like iOS, the next saved account takes over. */
    fun signOut() {
        val current = _state.value.session
        sessionSocket.disconnect()
        plugins.unregisterPush(current)
        val remaining = if (current != null) vault.remove(current.accountId) else null
        if (current == null) vault.clear()
        if (remaining != null) {
            activate(remaining)
            return
        }
        jellyfin = null
        silo = null
        pendingSilo = null
        plugins.reset()
        routeJob?.cancel()
        ServerRoute.set(null, null)
        _state.update {
            ZelefinUiState(
                gatewayId = it.gatewayId,
                gatewaySecret = it.gatewaySecret,
                libraryLayout = it.libraryLayout,
                search = LibrarySearchState(recents = searchHistory.load()),
            )
        }
    }

    fun switchAccount(account: SavedSession) {
        if (_state.value.session?.accountId == account.accountId) return
        val saved = vault.accounts().firstOrNull { it.accountId == account.accountId } ?: account
        vault.save(saved, select = true)
        activate(saved)
    }

    fun removeAccount(account: SavedSession) {
        if (_state.value.session?.accountId == account.accountId) {
            signOut()
            return
        }
        vault.remove(account.accountId)
        _state.update { it.copy(accounts = vault.accounts()) }
    }

    fun resetAddAccount() {
        pendingSilo = null
        _state.update { it.copy(addAccount = AddAccountState()) }
    }

    /** Signs in another user without dropping the current one (iOS `AddAccountView`). */
    fun addAccount(rawUrl: String, username: String, password: String) {
        val backend = _state.value.session?.backend ?: _state.value.backend
        _state.update { it.copy(addAccount = AddAccountState(busy = true)) }
        viewModelScope.launch {
            runCatching {
                val url = ServerUrl.normalize(rawUrl)
                val name = username.trim()
                if (name.isEmpty()) throw ZelefinException.server(if (backend == MediaBackend.Silo) "Enter an email or username." else "Enter a username.")
                when (backend) {
                    MediaBackend.Jellyfin -> {
                        val result = JellyfinLibrary(getApplication(), url).login(name, password)
                        val user = result.user ?: throw ZelefinException.missingUser()
                        val session = SavedSession(
                            serverUrl = url,
                            accessToken = result.accessToken.orEmpty(),
                            userId = user.id.toString(),
                            userName = user.name ?: name,
                            deviceId = vault.deviceId,
                            userImageTag = user.primaryImageTag,
                            serverName = user.serverName,
                            backend = MediaBackend.Jellyfin,
                        )
                        vault.save(session)
                        activate(session)
                    }
                    MediaBackend.Silo -> {
                        val client = newSilo(url)
                        val auth = client.login(name, password)
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
                        pendingSilo = client
                        val direct = pending.singleUnlockedProfile
                            ?: if (profiles.isEmpty()) HouseholdProfile(id = auth.userId, name = auth.userName, isPrimary = true) else null
                        if (direct != null) {
                            completeAddedSilo(pending, direct, null)
                        } else {
                            _state.update { it.copy(addAccount = AddAccountState(pending = pending)) }
                        }
                    }
                }
            }.onFailure { error ->
                if (error is CancellationException) throw error
                _state.update { it.copy(addAccount = it.addAccount.copy(busy = false, message = error.message ?: "Something went wrong.")) }
            }
        }
    }

    fun chooseAddedProfile(profile: HouseholdProfile) {
        val pending = _state.value.addAccount.pending ?: return
        if (profile.hasPin) {
            _state.update { it.copy(addAccount = it.addAccount.copy(pinFor = profile, message = null)) }
        } else {
            completeAddedSilo(pending, profile, null)
        }
    }

    fun submitAddedPin(pin: String) {
        val add = _state.value.addAccount
        val pending = add.pending ?: return
        val profile = add.pinFor ?: return
        val client = pendingSilo ?: return
        _state.update { it.copy(addAccount = it.addAccount.copy(busy = true, message = null)) }
        viewModelScope.launch {
            runCatching { client.verifyPin(profile.id, pin.trim()) }
                .onSuccess { token -> completeAddedSilo(pending, profile, token) }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    _state.update { it.copy(addAccount = it.addAccount.copy(busy = false, message = error.message ?: "That PIN is not correct.")) }
                }
        }
    }

    fun cancelAddedPin() {
        _state.update { it.copy(addAccount = it.addAccount.copy(pinFor = null, message = null)) }
    }

    private fun completeAddedSilo(pending: SiloPendingSignIn, profile: HouseholdProfile, profileToken: String?) {
        val client = pendingSilo ?: return
        client.profileId = profile.id
        client.profileToken = profileToken
        val session = SavedSession(
            serverUrl = pending.serverUrl,
            accessToken = client.accessToken ?: pending.accessToken,
            userId = pending.userId,
            userName = pending.userName,
            deviceId = pending.deviceId,
            serverName = pending.serverName,
            serverVersion = pending.serverVersion,
            backend = MediaBackend.Silo,
            refreshToken = client.refreshToken ?: pending.refreshToken,
            profileId = profile.id,
            profileToken = profileToken,
            profileName = profile.name,
            userRole = pending.userRole,
            isPrimaryProfile = profile.isPrimary,
        )
        pendingSilo = null
        vault.save(session)
        activate(session)
    }

    /** Makes [session] the live account: fresh clients, plugin detection, and that account's cached home. */
    private fun activate(session: SavedSession) {
        quickConnectJob?.cancel()
        movieCatalogJob?.cancel()
        showCatalogJob?.cancel()
        overviewJob?.cancel()
        overviewLoadedFor = null
        searchJob?.cancel()
        gridJobs.values.forEach(Job::cancel)
        gridJobs.clear()
        activePlan = null
        plugins.reset()
        restore(session)
        _state.update {
            ZelefinUiState(
                screen = Screen.Library,
                backend = session.backend,
                session = session,
                accounts = vault.accounts(),
                gatewayId = it.gatewayId,
                gatewaySecret = it.gatewaySecret,
                libraryLayout = it.libraryLayout,
                search = LibrarySearchState(recents = searchHistory.load()),
                localServerUrl = it.localServerUrl.takeIf { _ -> it.session?.serverUrl == session.serverUrl },
            )
        }
        refreshRoute()
        viewModelScope.launch {
            applyCachedSnapshots(session)
            refreshLibrary()
        }
        bindSessionSocket(session)
    }

    /** Uploads a new Jellyfin profile picture and saves the new image tag so every avatar reloads. */
    suspend fun updateProfilePhoto(uri: Uri) {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        if (session.usesSilo) throw ZelefinException.server("Change Silo profile pictures in Silo.")
        val jpeg = AccountPhoto.jpeg(getApplication(), uri)
        AccountPhoto.upload(session, jpeg)
        val tag = AccountPhoto.imageTag(session)
        val latest = _state.value.session?.takeIf { it.accountId == session.accountId } ?: return
        val updated = latest.copy(userImageTag = tag ?: latest.userImageTag)
        vault.save(updated)
        _state.update { it.copy(session = updated, accounts = vault.accounts()) }
    }

    suspend fun changePassword(current: String, new: String) {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        if (current.isBlank() || new.isBlank()) throw ZelefinException.server("Enter your current password and a new password.")
        if (session.usesSilo) {
            if (!session.isPrimaryProfile) throw ZelefinException.server("Switch to the primary household profile to change this password.")
            if (new.length < 8) throw ZelefinException.server("Use at least 8 characters for the new password.")
            siloClient().changePassword(current, new)
        } else {
            jellyfinClient().changeOwnPassword(session.userId, current, new)
        }
    }

    suspend fun removeProfilePhoto() {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        if (session.usesSilo) throw ZelefinException.server("Change Silo profile pictures in Silo.")
        jellyfinClient().deleteUserImage(session.userId)
        val latest = _state.value.session?.takeIf { it.accountId == session.accountId } ?: return
        val updated = latest.copy(userImageTag = null)
        vault.save(updated)
        _state.update { it.copy(session = updated, accounts = vault.accounts()) }
    }

    fun homeNetwork(): HomeNetworkProfile =
        _state.value.session?.let { homeNetworks.load(it.accountId) } ?: HomeNetworkProfile()

    fun saveHomeNetwork(profile: HomeNetworkProfile) {
        val session = _state.value.session ?: return
        homeNetworks.save(session.accountId, profile)
        refreshRoute()
    }

    /** Picks the local address on home Wi-Fi when it answers, and the saved address otherwise. */
    private suspend fun refreshRouteNow() {
        val session = _state.value.session
        if (session == null) {
            ServerRoute.set(null, null)
            _state.update { it.copy(localServerUrl = null) }
            return
        }
        val local = HomeNetwork.resolve(getApplication(), homeNetworks.load(session.accountId))
        if (_state.value.session?.accountId != session.accountId) return
        ServerRoute.set(session.serverUrl, local)
        _state.update { it.copy(localServerUrl = local) }
    }

    fun refreshRoute() {
        routeJob?.cancel()
        val session = _state.value.session
        if (session == null) {
            ServerRoute.set(null, null)
            _state.update { it.copy(localServerUrl = null) }
            return
        }
        routeJob = viewModelScope.launch {
            kotlinx.coroutines.delay(300)
            val local = HomeNetwork.resolve(getApplication(), homeNetworks.load(session.accountId))
            if (_state.value.session?.accountId != session.accountId) return@launch
            ServerRoute.set(session.serverUrl, local)
            _state.update { it.copy(localServerUrl = local) }
        }
    }

    override fun onCleared() {
        sessionSocket.disconnect()
        runCatching {
            getApplication<Application>().getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(networkCallback)
        }
        super.onCleared()
    }

    private fun bindSessionSocket(session: SavedSession) {
        if (session.backend != MediaBackend.Jellyfin) {
            sessionSocket.disconnect()
            return
        }
        val library = jellyfin ?: return
        sessionSocket.connect(session, library, object : SessionSocket.Events {
            override fun onGroupJoined(groupId: String, name: String) {
                _state.update {
                    it.copy(syncPlayGroupId = groupId, syncPlayGroupName = name.ifBlank { it.syncPlayGroupName })
                }
            }

            override fun onGroupLeft() {
                _state.update { it.copy(syncPlayGroupId = null, syncPlayGroupName = null, syncPlayPlaylistItemId = null) }
            }

            override fun onPlayQueue(itemId: String, playlistItemId: String, startSeconds: Double) {
                presentSyncPlayItem(itemId, playlistItemId, startSeconds)
            }

            override fun onSyncPlayCommand(command: SendCommandType, positionSeconds: Double?) {
                applySyncPlayCommand(command, positionSeconds)
            }

            override fun onRemotePlay(itemId: String) {
                if (_state.value.syncPlayGroupId != null) presentSyncPlayItem(itemId, _state.value.syncPlayPlaylistItemId, 0.0)
            }

            override fun onRemoteStop() {
                if (_state.value.syncPlayGroupId == null) applyRemoteStop()
            }

            override fun onPlaystate(command: PlaystateCommand, positionSeconds: Double?) {
                if (_state.value.syncPlayGroupId != null) return
                when (command) {
                    PlaystateCommand.PAUSE -> _playerDirectives.tryEmit(PlayerDirective.Pause)
                    PlaystateCommand.UNPAUSE -> _playerDirectives.tryEmit(PlayerDirective.Play)
                    PlaystateCommand.SEEK -> positionSeconds?.let { _playerDirectives.tryEmit(PlayerDirective.Seek(it)) }
                    PlaystateCommand.STOP -> applyRemoteStop()
                    else -> Unit
                }
            }
        })
    }

    private fun presentSyncPlayItem(itemId: String, playlistItemId: String?, startSeconds: Double) {
        if (playlistItemId != null) {
            _state.update { it.copy(syncPlayPlaylistItemId = playlistItemId) }
        }
        val playing = _state.value.screen as? Screen.Player
        if (playing != null && playing.plan.item.id == itemId) {
            notifySyncPlayReady(playing.plan.startTimeSeconds)
            return
        }
        viewModelScope.launch {
            val loaded = runCatching { jellyfinClient().mediaItem(userUuid(), itemId) }.getOrNull()
                ?: runCatching { jellyfinClient().detail(userUuid(), itemId).item }.getOrNull()
            if (loaded == null) {
                _state.update { it.copy(message = "SyncPlay couldn’t open that title.") }
                return@launch
            }
            play(loaded.copy(playbackPosition = startSeconds.coerceAtLeast(0.0)), fromSyncPlay = true)
        }
    }

    private fun applySyncPlayCommand(command: SendCommandType, positionSeconds: Double?) {
        when (command) {
            SendCommandType.PAUSE -> _playerDirectives.tryEmit(PlayerDirective.Pause)
            SendCommandType.UNPAUSE -> _playerDirectives.tryEmit(PlayerDirective.Play)
            SendCommandType.SEEK -> positionSeconds?.let { seconds ->
                _playerDirectives.tryEmit(PlayerDirective.Seek(seconds))
                notifySyncPlayReady(seconds)
            }
            SendCommandType.STOP -> applyRemoteStop()
        }
    }

    private fun notifySyncPlayReady(positionSeconds: Double, isPlaying: Boolean = true) {
        if (_state.value.syncPlayGroupId == null) return
        viewModelScope.launch {
            var playlistId = _state.value.syncPlayPlaylistItemId
            if (playlistId == null) {
                repeat(15) {
                    kotlinx.coroutines.delay(100)
                    playlistId = _state.value.syncPlayPlaylistItemId
                    if (playlistId != null) return@repeat
                }
            }
            if (_state.value.syncPlayGroupId == null) return@launch
            runCatching { jellyfinClient().syncPlayReady(isPlaying, playlistId, positionSeconds) }
        }
    }

    private fun applyRemoteStop() {
        if (_state.value.screen is Screen.Player) back()
    }

    private fun playbackTarget(item: MediaItem): MediaItem {
        val detail = _state.value.detail
        return if (detail != null && detail.item.id == item.id) {
            MediaItem.heroPlaybackItem(item, detail.episodes)
        } else {
            item
        }
    }

    private suspend fun resolvePlaybackTarget(item: MediaItem): MediaItem {
        val fromDetail = playbackTarget(item)
        if (fromDetail.kind != MediaKind.Series && fromDetail.kind != MediaKind.Season) return fromDetail
        val seriesId = if (fromDetail.kind == MediaKind.Season) fromDetail.seriesId ?: fromDetail.id else fromDetail.id
        val home = _state.value.home
        MediaItem.preferredEpisode(
            (home.continueWatching + home.nextUp).filter { it.kind == MediaKind.Episode && it.seriesId == seriesId },
        )?.let { return it }
        val session = _state.value.session ?: return fromDetail
        return when (session.backend) {
            MediaBackend.Silo -> fromDetail
            MediaBackend.Jellyfin -> jellyfinClient().playableItem(UUID.fromString(session.userId), fromDetail)
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
        _state.value.session?.let(::bindSessionSocket)
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
        _state.update { it.copy(session = session, accounts = vault.accounts(), busy = false, screen = Screen.Library, message = null) }
        refreshRoute()
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
        _state.update { it.copy(session = session, accounts = vault.accounts()) }
        refreshRoute()
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

    private suspend fun currentHome(): HomeFeed {
        val hero = app.zelefin.client.ui.HomeLayoutPreferences.heroContent
        return visibleHome(
            when (_state.value.session?.backend) {
                MediaBackend.Silo -> siloHero(siloClient().home(), hero)
                else -> jellyfinClient().home(
                    UUID.fromString(_state.value.session?.userId),
                    JellyfinLibrary.HeroContent.entries.first { it.name == hero.name },
                )
            },
        )
    }

    /** Silo serves its own hero; Random shuffles recently added, and queue sources use those rows. */
    private fun siloHero(feed: HomeFeed, hero: app.zelefin.client.ui.FeaturedHeroContent): HomeFeed {
        val homeHero = app.zelefin.client.ui.HomeHero
        val picked = when (hero) {
            app.zelefin.client.ui.FeaturedHeroContent.Random -> homeHero.fromPool((feed.recentMovies + feed.recentShows).shuffled())
            app.zelefin.client.ui.FeaturedHeroContent.ContinueWatching -> homeHero.fromPool(feed.continueWatching)
            app.zelefin.client.ui.FeaturedHeroContent.NextUp -> homeHero.fromPool(feed.nextUp)
            app.zelefin.client.ui.FeaturedHeroContent.RecentlyWatched -> homeHero.fromPool(feed.recentlyWatched)
            app.zelefin.client.ui.FeaturedHeroContent.Recommendations -> homeHero.fromPool(feed.recommendations.flatMap { it.items })
            else -> emptyList()
        }
        return if (picked.isEmpty()) feed else feed.copy(featured = picked)
    }

    /** Pulls Interface and Library layout choices from Jellyfin display preferences (iOS `pullDisplayPreferences`). */
    fun pullDisplayPreferences() {
        val session = _state.value.session ?: return
        if (session.backend != MediaBackend.Jellyfin) return
        viewModelScope.launch {
            val prefs = runCatching { jellyfinClient().displayPreferenceCustomPrefs(userUuid()) }.getOrNull() ?: return@launch
            if (_state.value.session?.accountId != session.accountId) return@launch
            val context = getApplication<Application>()
            val layout = app.zelefin.client.ui.HomeLayoutPreferences
            val before = layout.mergeContinueAndNextUp to layout.heroContent
            app.zelefin.client.ui.TabPreferences.applySyncedOrder(context, prefs[SyncTabOrder])
            layout.applySynced(
                context,
                orderRaw = prefs[SyncHomeRowOrder],
                hiddenRaw = prefs[SyncHomeRowHidden],
                merge = prefs[SyncMerge]?.let { it == "true" || it == "1" },
                hero = prefs[SyncHero],
            )
            val libraryOrder = prefs[SyncLibraryOrder]
            val libraryHidden = prefs[SyncLibraryHidden]
            val pageHidden = prefs[SyncLibraryPageHidden]
            if (libraryOrder != null || libraryHidden != null || pageHidden != null) {
                val current = _state.value.libraryLayout
                val parsedHidden = libraryHidden?.let(LibraryLayout::parseHidden)
                val next = current.copy(
                    order = libraryOrder?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: current.order,
                    hidden = parsedHidden?.first ?: current.hidden,
                    hiddenBlocks = pageHidden?.let(::libraryBlocks) ?: current.hiddenBlocks,
                    usesDefaultHidden = parsedHidden?.second ?: current.usesDefaultHidden,
                )
                if (next != current) {
                    layoutStore.save(next)
                    _state.update { it.copy(libraryLayout = next) }
                }
            }
            if (before != (layout.mergeContinueAndNextUp to layout.heroContent)) refreshLibrary()
        }
    }

    /** Pushes Interface and Library layout choices to Jellyfin display preferences (iOS `pushDisplayPreferences`). */
    fun pushDisplayPreferences() {
        val session = _state.value.session ?: return
        if (session.backend != MediaBackend.Jellyfin) return
        val layout = app.zelefin.client.ui.HomeLayoutPreferences
        val libraryLayout = _state.value.libraryLayout
        val prefs = mapOf(
            SyncTabOrder to app.zelefin.client.ui.DockTab.rawOrder(app.zelefin.client.ui.TabPreferences.order),
            SyncMerge to if (layout.mergeContinueAndNextUp) "true" else "false",
            SyncHomeRowOrder to app.zelefin.client.ui.HomeRowKind.rawOrder(layout.order),
            SyncHomeRowHidden to app.zelefin.client.ui.HomeRowKind.rawHidden(layout.hidden),
            SyncHero to layout.heroContent.raw,
            SyncLibraryOrder to libraryLayout.order.joinToString(","),
            SyncLibraryHidden to libraryLayout.encodedHidden(),
            SyncLibraryPageHidden to if (libraryLayout.hiddenBlocks.isEmpty()) {
                "none"
            } else {
                libraryLayout.hiddenBlocks.map { it.name.lowercase() }.sorted().joinToString(",")
            },
        )
        viewModelScope.launch {
            runCatching { jellyfinClient().updateDisplayPreferenceCustomPrefs(userUuid(), prefs) }
        }
    }

    private fun libraryBlocks(raw: String): Set<LibraryPageBlock> = when (raw.trim()) {
        "" -> setOf(LibraryPageBlock.Collections)
        "none" -> emptySet()
        else -> raw.split(',').mapNotNull { token -> LibraryPageBlock.entries.firstOrNull { it.name.lowercase() == token.trim() } }.toSet()
    }

    /** Opens a custom library pinned to the dock. */
    fun selectDockRoom(room: LibraryRoom) {
        _state.update { it.copy(tab = AppTab.Room, dockRoomId = room.id, screen = Screen.Library) }
        ensureBrowseGrid(LibraryRoute.Room(room))
    }

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
            LibraryRoute.Downloaded -> Unit
            is LibraryRoute.Discover -> plugins.loadDiscoverGrid(route.query)
            else -> loadLibraryGrid(route)
        }
    }

    fun applyLibraryQuery(route: LibraryRoute, query: CatalogBrowseQuery) {
        if (_state.value.libraryGrids[route]?.query == query) return
        queryStore.save(CatalogQueryStore.routeKey(route), query)
        updateGrid(route) { copy(query = query) }
        loadLibraryGrid(route)
    }

    fun refreshLibraryGrid(route: LibraryRoute) = loadLibraryGrid(route, refreshing = true)

    fun refreshLibraryOverview() = loadLibraryOverview(force = true)

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
        pushDisplayPreferences()
    }

    fun resetLibraryLayout() {
        layoutStore.reset()
        _state.update { it.copy(libraryLayout = LibraryLayout()) }
        loadRoomDetails()
        pushDisplayPreferences()
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
            LibraryRoute.AllCollections -> JellyfinScope(listOf(org.jellyfin.sdk.model.api.BaseItemKind.BOX_SET))
            else -> JellyfinScope(titles)
        }
    }

    private fun loadLibraryGrid(route: LibraryRoute, refreshing: Boolean = false) {
        val stored = _state.value.libraryGrids[route]?.query ?: queryStore.load(CatalogQueryStore.routeKey(route))
        if (_state.value.libraryGrids[route]?.query != stored) {
            updateGrid(route) { copy(query = stored) }
        }
        val query = stored
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
                            LibraryRoute.Watchlist -> emptyList()
                            LibraryRoute.AllCollections -> client.catalog("collection", null, effective)
                            else -> emptyList()
                        }
                    }
                    else -> when (route) {
                        LibraryRoute.Watchlist -> jellyfinClient().watchlistItems(userUuid())
                        else -> jellyfinClient().browse(userUuid(), jellyfinScope(route), effective) { page ->
                            if (gridJob.isActive) updateGrid(route) { copy(items = page, loading = false) }
                        }
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

    private suspend fun jellyfinServerCounts(rooms: List<LibraryRoom>): LibraryCounts {
        val client = jellyfinClient()
        val counts = client.serverCounts(userUuid())
        if (rooms.none { it.kind == LibraryKind.YouTube }) return counts
        return counts.separatingYouTube(client.youTubeCounts(userUuid(), rooms))
    }

    private fun loadLibraryOverview(force: Boolean = false) {
        val account = _state.value.session?.accountId
        if (!force && account != null && account == overviewLoadedFor && _state.value.libraries.isNotEmpty()) {
            refreshLibraryStats()
            return
        }
        overviewJob?.cancel()
        overviewJob = viewModelScope.launch {
            val job = coroutineContext[Job]
            if (force) _state.update { it.copy(libraryRefreshing = true) }
            try {
                _state.update { it.copy(librariesLoading = it.libraries.isEmpty()) }
                if (_state.value.libraries.isNotEmpty()) loadRoomDetails()
                val silo = _state.value.session?.backend == MediaBackend.Silo
                val roomsReady = CompletableDeferred<List<LibraryRoom>>()
                val countsJob = launch {
                    val counts = runCatching {
                        if (silo) siloClient().serverCounts() else jellyfinServerCounts(roomsReady.await())
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
                    roomsReady.complete(rooms)
                    val changed = rooms != _state.value.libraries
                    overviewLoadedFor = account
                    _state.update { it.copy(libraries = rooms, librariesLoading = false, message = null) }
                    _state.value.session?.let { snapshots.saveHome(it, _state.value.home, rooms) }
                    if (changed || _state.value.libraryOverview.covers.isEmpty()) loadRoomDetails()
                }.onFailure { error ->
                    if (error is CancellationException) throw error
                    roomsReady.complete(_state.value.libraries)
                    _state.update { it.copy(librariesLoading = false, message = if (it.libraries.isEmpty()) error.message else it.message) }
                }
                countsJob.join()
            } finally {
                if (force && overviewJob == job) _state.update { it.copy(libraryRefreshing = false) }
            }
        }
    }

    private fun loadRoomDetails(onlyMissing: Boolean = false) {
        val state = _state.value
        val silo = state.session?.backend == MediaBackend.Silo
        val rooms = state.libraryLayout.displayed(state.libraries.libraryTabRooms(silo))
        viewModelScope.launch {
            rooms.forEach { room ->
                if (!onlyMissing || room.id !in state.libraryOverview.roomCounts) launch {
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
            if (query.isDefault && empty && session != null) {
                val cached = withContext(Dispatchers.IO) { snapshots.loadCatalog(session, kind) }
                if (cached != null) {
                    _state.update {
                        if (tab == AppTab.Movies) it.copy(movies = cached, moviesLoading = false)
                        else it.copy(shows = cached, showsLoading = false)
                    }
                }
            }
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
        appVersion = BuildConfig.VERSION_NAME,
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
                channel = detail.channel?.let { if (it.id == id) it.transform() else it },
                channelVideos = detail.channelVideos.mapId(),
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

package app.zelefin.client

import android.app.Application
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.zelefin.client.jellyfin.CollectionEditor
import app.zelefin.client.jellyfin.JellyfinLibrary
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AppTab { Home, Movies, Shows, Library, Search }

data class LibraryRoom(
    val id: String,
    val name: String,
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
    val libraryItems: List<MediaItem> = emptyList(),
    val openLibraryId: String? = null,
    val detail: TitleDetail? = null,
    val quickConnect: QuickConnectHandshake? = null,
    val homeRefreshing: Boolean = false,
    val gatewayId: String = "",
    val gatewaySecret: String = "",
)

class ZelefinModel(application: Application) : AndroidViewModel(application) {
    private val vault = SessionVault(application)
    private val snapshots = SnapshotStore(application)
    private val _state = MutableStateFlow(ZelefinUiState())
    val state: StateFlow<ZelefinUiState> = _state.asStateFlow()

    private var jellyfin: JellyfinLibrary? = null
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
                    home = cachedHome?.first ?: it.home,
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
        _state.update { it.copy(tab = tab, screen = Screen.Library) }
        if ((tab == AppTab.Movies || tab == AppTab.Search) && _state.value.movies.isEmpty()) loadCatalog(AppTab.Movies)
        if ((tab == AppTab.Shows || tab == AppTab.Search) && _state.value.shows.isEmpty()) loadCatalog(AppTab.Shows)
        if (tab == AppTab.Library) {
            _state.update { it.copy(openLibraryId = null, libraryItems = emptyList()) }
            if (_state.value.libraries.isEmpty()) loadLibraries()
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
        if (current.screen is Screen.Library && current.openLibraryId != null) {
            _state.update { it.copy(openLibraryId = null, libraryItems = emptyList(), message = null) }
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
        viewModelScope.launch {
            val session = _state.value.session
            val cached = session?.let { snapshots.loadHome(it) }
            _state.update {
                it.copy(
                    homeRefreshing = true,
                    home = cached?.first ?: it.home,
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
        vault.clear()
        jellyfin = null
        silo = null
        _state.update { ZelefinUiState(gatewayId = it.gatewayId, gatewaySecret = it.gatewaySecret) }
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

    private suspend fun currentHome(): HomeFeed = when (_state.value.session?.backend) {
        MediaBackend.Silo -> siloClient().home()
        else -> jellyfinClient().home(UUID.fromString(_state.value.session?.userId))
    }

    fun openLibrary(room: LibraryRoom) {
        _state.update { it.copy(openLibraryId = room.id, libraryItems = emptyList(), busy = true, message = null) }
        viewModelScope.launch {
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> siloClient().libraryItems(room.id)
                    else -> jellyfinClient().itemsInLibrary(UUID.fromString(_state.value.session?.userId), room.id)
                }
            }.onSuccess { items ->
                _state.update { it.copy(libraryItems = items, busy = false) }
            }.onFailure { error ->
                _state.update { it.copy(busy = false, message = error.message) }
            }
        }
    }

    private fun loadLibraries() {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> siloClient().libraries()
                    else -> jellyfinClient().libraries(UUID.fromString(_state.value.session?.userId))
                }
            }.onSuccess { rooms ->
                _state.update { it.copy(libraries = rooms, busy = false, message = null) }
                _state.value.session?.let { snapshots.saveHome(it, _state.value.home, rooms) }
            }.onFailure { error ->
                _state.update { it.copy(busy = false, message = error.message) }
            }
        }
    }

    private fun loadCatalog(tab: AppTab) {
        val session = _state.value.session
        val kind = if (tab == AppTab.Movies) "movies" else "shows"
        session?.let { snapshots.loadCatalog(it, kind) }?.let { cached ->
            _state.update { if (tab == AppTab.Movies) it.copy(movies = cached) else it.copy(shows = cached) }
        }
        viewModelScope.launch {
            runCatching {
                when (_state.value.session?.backend) {
                    MediaBackend.Silo -> {
                        val type = if (tab == AppTab.Movies) "movie" else "series"
                        siloClient().catalog(type)
                    }
                    else -> {
                        val kind = if (tab == AppTab.Movies) org.jellyfin.sdk.model.api.BaseItemKind.MOVIE else org.jellyfin.sdk.model.api.BaseItemKind.SERIES
                        jellyfinClient().catalog(UUID.fromString(_state.value.session?.userId), kind)
                    }
                }
            }.onSuccess { items ->
                _state.update {
                    if (tab == AppTab.Movies) it.copy(movies = items) else it.copy(shows = items)
                }
                _state.value.session?.let { snapshots.saveCatalog(it, kind, items) }
            }
        }
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
            libraryItems = libraryItems.mapId(),
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

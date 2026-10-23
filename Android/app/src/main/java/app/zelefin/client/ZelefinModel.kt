package app.zelefin.client

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.Uri
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
import app.zelefin.client.silo.SiloAccountClient
import app.zelefin.client.silo.SiloHandoff
import app.zelefin.client.silo.SiloHousehold
import app.zelefin.client.silo.SiloNotice
import app.zelefin.client.silo.SiloPinPrompt
import app.zelefin.client.silo.SiloProfilePicker
import app.zelefin.core.GatewaySecrets
import app.zelefin.core.SiloAccount
import app.zelefin.core.SiloAvatarPreset
import app.zelefin.core.SiloProfile
import app.zelefin.core.SiloTokens
import app.zelefin.core.HomeFeed
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.core.QuickConnectHandshake
import app.zelefin.core.SavedAccountsCodec
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl
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
    val siloPicker: SiloProfilePicker? = null,
    val siloPin: SiloPinPrompt? = null,
    val siloNotice: SiloNotice? = null,
    val household: SiloHousehold = SiloHousehold(),
) {
    /** Signed in through Silo's Jellyfin-compatible API, which leaves several Jellyfin features out. */
    val isSiloServer: Boolean get() = session?.isSiloServer == true
}

sealed interface PlayerDirective {
    data object Play : PlayerDirective
    data object Pause : PlayerDirective
    data class Seek(val seconds: Double) : PlayerDirective
}

/** Settings → Add User. */
data class AddAccountState(
    val busy: Boolean = false,
    val message: String? = null,
)

private class PendingSiloSignIn(
    val client: SiloAccountClient,
    val account: SiloAccount,
    val jellyfinUrl: String,
    val serverName: String?,
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
    private var activePlan: PlaybackPlan? = null
    private var lastReported = 0.0
    private var localPlan: PlaybackPlan? = null
    private var quickConnectJob: Job? = null
    /** A Silo sign-in waiting on the "Who's watching?" pick. */
    private var siloPending: PendingSiloSignIn? = null
    private var siloJob: Job? = null
    private var householdJob: Job? = null
    /** The native Silo client of the current account, keyed by its account id. */
    private var siloClient: Pair<String, SiloAccountClient>? = null
    private val homeNetworks = HomeNetworkStore(application)
    private var routeJob: Job? = null
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
        val dropped = vault.dropLegacySiloSessions()
        val saved = vault.current()?.takeUnless { dropped?.droppedCurrent == true }
        _state.update {
            it.copy(
                gatewayId = secrets.clientId,
                gatewaySecret = secrets.clientSecret,
                session = saved,
                accounts = vault.accounts(),
                message = if (saved == null && dropped != null) SavedAccountsCodec.SiloSignInAgainMessage else null,
            )
        }
        runCatching { application.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(networkCallback) }
        if (saved != null) {
            restore(saved)
            _state.update { it.copy(screen = Screen.Library) }
            applyStartPage()
            viewModelScope.launch {
                applyCachedSnapshots(saved)
                refreshLibrary()
            }
            bindSessionSocket(saved)
            refreshHousehold()
        }
    }

    init {
        ZelefinDownloads.attach(application, SessionDownloadBackend(), _state.map { it.session })
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

    fun saveGateway(id: String, secret: String) {
        vault.saveGateway(GatewaySecrets(id.trim(), secret.trim()))
        _state.update { it.copy(gatewayId = id.trim(), gatewaySecret = secret.trim()) }
    }

    fun testConnection(rawUrl: String) {
        launch("Checking the server…") {
            val url = ServerUrl.normalize(rawUrl)
            if (SiloAccountClient.isSiloAddress(url)) {
                _state.update { it.copy(busy = false, message = "Silo is reachable.") }
                return@launch
            }
            val library = JellyfinLibrary(getApplication(), url)
            val reachability = library.probe()
            val message = when {
                !reachability.isReachable -> reachability.message
                library.detectSiloServer() == true -> "Silo is reachable."
                else -> "Jellyfin is reachable."
            }
            _state.update { it.copy(busy = false, message = message) }
        }
    }

    fun signIn(rawUrl: String, username: String, password: String, type: SignInServerType) {
        launch("Signing in…") {
            val url = ServerUrl.normalize(rawUrl)
            val route = SignInRouting.route(type, SiloAccountClient.isSiloAddress(url)) { isSiloCompatAddress(url) }
            when (route) {
                SignInRoute.SiloNative -> {
                    openSiloPicker(url, username.trim(), password)
                    _state.update { it.copy(busy = false, message = null) }
                }
                SignInRoute.Jellyfin -> signInJellyfin(url, username, password)
                is SignInRoute.Refused -> throw ZelefinException.server(route.message)
            }
        }
    }

    /** Silo's Jellyfin-compatible API, by its branding; an unreachable server reports why instead. */
    private suspend fun isSiloCompatAddress(url: String): Boolean {
        val library = JellyfinLibrary(getApplication(), url)
        library.detectSiloServer()?.let { return it }
        val reachability = library.probe()
        if (!reachability.isReachable) throw ZelefinException.server(reachability.message)
        return false
    }

    /** `username#profile` only means something on Silo's Jellyfin-compatible address. */
    private suspend fun isSiloSignIn(url: String, username: String): Boolean =
        !username.contains('#') && SiloAccountClient.isSiloAddress(url)

    /** Native Silo sign-in, then the household profiles and the Jellyfin-compatible address for the picker. */
    private suspend fun openSiloPicker(url: String, username: String, password: String) {
        if (username.isEmpty()) throw ZelefinException.server("Enter a username.")
        val client = SiloAccountClient(url, onTokens = ::persistSiloTokens)
        val signIn = client.login(username, password)
        try {
            val info = client.connectInfo()
            val jellyfinUrl = info.requireJellyfinUrl()
            val profiles = client.profiles().items
            if (profiles.isEmpty()) throw ZelefinException.server("This Silo account has no profiles yet. Add one in Silo, then sign in again.")
            siloPending?.client?.let(::logOutSiloQuietly)
            siloPending = PendingSiloSignIn(client, signIn.account, jellyfinUrl, info.serverName)
            _state.update {
                it.copy(
                    siloPicker = SiloProfilePicker(info.serverName ?: "Silo", signIn.account.username, profiles),
                    siloPin = null,
                )
            }
        } catch (error: Throwable) {
            logOutSiloQuietly(client)
            throw error
        }
    }

    /** A tap on the "Who's watching?" picker. */
    fun chooseSiloProfile(profile: SiloProfile) {
        if (_state.value.siloPicker?.busyProfileId != null) return
        if (profile.hasPin) {
            _state.update { it.copy(siloPin = SiloPinPrompt(profile)) }
            return
        }
        linkPendingProfile(profile, pin = null)
    }

    fun submitSiloPin(pin: String) {
        val prompt = _state.value.siloPin ?: return
        if (prompt.busy) return
        val digits = pin.trim()
        if (digits.isEmpty()) return
        if (_state.value.siloPicker != null) linkPendingProfile(prompt.profile, digits) else switchSiloProfile(prompt.profile, digits)
    }

    fun cancelSiloPin() {
        if (_state.value.siloPin?.busy == true) siloJob?.cancel()
        _state.update {
            it.copy(
                siloPin = null,
                siloPicker = it.siloPicker?.copy(busyProfileId = null),
                household = it.household.copy(switchingTo = null),
            )
        }
    }

    /** "Use a different account": drops the pending Silo sign-in. */
    fun cancelSiloPicker() {
        siloJob?.cancel()
        siloPending?.client?.let(::logOutSiloQuietly)
        siloPending = null
        _state.update { it.copy(siloPicker = null, siloPin = null, busy = false, addAccount = AddAccountState()) }
    }

    fun dismissSiloNotice() {
        _state.update { it.copy(siloNotice = null) }
    }

    /** The Silo sign-in behind this account is gone; sign out so the user can sign in again. */
    fun signInToSiloAgain() {
        _state.update { it.copy(siloNotice = null) }
        if (_state.value.session?.siloLink != null) signOut()
    }

    private fun linkPendingProfile(profile: SiloProfile, pin: String?) {
        val pending = siloPending ?: return
        siloJob?.cancel()
        _state.update {
            it.copy(
                siloPicker = it.siloPicker?.copy(busyProfileId = profile.id, message = null),
                siloPin = it.siloPin?.copy(busy = true, message = null),
            )
        }
        siloJob = viewModelScope.launch {
            runCatching {
                val token = pin?.let { verifiedProfileToken(pending.client, profile, it) }
                SiloHandoff.signIn(
                    context = getApplication(),
                    native = pending.client,
                    account = pending.account,
                    profile = profile,
                    profileToken = token,
                    jellyfinUrl = pending.jellyfinUrl,
                    serverName = pending.serverName,
                    deviceId = vault.deviceId,
                )
            }.onSuccess { session ->
                siloPending = null
                vault.save(session)
                siloClient = session.accountId to pending.client
                activate(session)
            }.onFailure { error ->
                if (error is CancellationException) return@onFailure
                val message = error.message ?: "Silo could not sign this profile in."
                _state.update {
                    if (it.siloPin != null) {
                        it.copy(siloPin = it.siloPin.copy(busy = false, message = message), siloPicker = it.siloPicker?.copy(busyProfileId = null))
                    } else {
                        it.copy(siloPicker = it.siloPicker?.copy(busyProfileId = null, message = message))
                    }
                }
            }
        }
    }

    /** The PIN profile's token, or null when Silo unlocked it without one. */
    private suspend fun verifiedProfileToken(client: SiloAccountClient, profile: SiloProfile, pin: String): String? {
        val result = client.verifyPin(profile.id, pin)
        if (!result.valid) throw ZelefinException.server("That PIN is not right. Try again.")
        return result.profileToken
    }

    /** Reloads the household profiles of a Silo-linked account. */
    fun refreshHousehold() {
        val session = _state.value.session
        val link = session?.siloLink
        if (session == null || link == null) {
            householdJob?.cancel()
            if (_state.value.household != SiloHousehold()) _state.update { it.copy(household = SiloHousehold()) }
            return
        }
        if (householdJob?.isActive == true) return
        _state.update { it.copy(household = it.household.copy(loading = true)) }
        householdJob = viewModelScope.launch {
            runCatching { siloClientFor(session).profiles() }
                .onSuccess { collection ->
                    if (_state.value.session?.accountId != session.accountId) return@onSuccess
                    _state.update {
                        it.copy(
                            household = it.household.copy(
                                profiles = collection.items,
                                avatarUploadEnabled = collection.avatarUploadEnabled,
                                loading = false,
                                message = null,
                                signInExpired = false,
                            ),
                        )
                    }
                    collection.items.firstOrNull { it.id == link.profileId }?.let { applySiloProfile(session.accountId, it) }
                }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    if (_state.value.session?.accountId != session.accountId) return@onFailure
                    val expired = error.isSiloSignInExpired()
                    _state.update {
                        it.copy(household = it.household.copy(loading = false, message = error.message, signInExpired = expired))
                    }
                }
        }
    }

    /**
     * Moves this Silo-linked account to another household profile: a fresh Jellyfin session
     * replaces the current one in place, and the old Jellyfin token is ended.
     */
    fun switchSiloProfile(profile: SiloProfile, pin: String? = null) {
        val session = _state.value.session ?: return
        val link = session.siloLink ?: return
        if (profile.id == link.profileId) return
        if (_state.value.household.switchingTo != null) return
        if (profile.hasPin && pin == null) {
            _state.update { it.copy(siloPin = SiloPinPrompt(profile)) }
            return
        }
        siloJob?.cancel()
        _state.update {
            it.copy(
                household = it.household.copy(switchingTo = profile.id, message = null),
                siloPin = it.siloPin?.copy(busy = true, message = null),
            )
        }
        siloJob = viewModelScope.launch {
            runCatching {
                val client = siloClientFor(session)
                val token = pin?.let { verifiedProfileToken(client, profile, it) }
                val info = client.connectInfo()
                val next = SiloHandoff.signIn(
                    context = getApplication(),
                    native = client,
                    account = link.account,
                    profile = profile,
                    profileToken = token,
                    jellyfinUrl = info.requireJellyfinUrl(),
                    serverName = info.serverName ?: session.serverName,
                    deviceId = vault.deviceId,
                )
                client to next
            }.onSuccess { (client, next) ->
                if (_state.value.session?.accountId != session.accountId) return@onSuccess
                sessionSocket.disconnect()
                plugins.unregisterPush(session)
                vault.replace(session.accountId, next)
                siloClient = next.accountId to client
                activate(next)
                if (next.accessToken != session.accessToken) logOutJellyfinQuietly(session)
            }.onFailure { error ->
                if (error is CancellationException) return@onFailure
                val expired = error.isSiloSignInExpired()
                val message = error.message ?: "Silo could not switch to ${profile.name}."
                _state.update {
                    val pinOpen = it.siloPin != null && !expired
                    it.copy(
                        household = it.household.copy(switchingTo = null, message = message, signInExpired = expired),
                        siloPin = if (pinOpen) it.siloPin?.copy(busy = false, message = message) else null,
                        siloNotice = if (pinOpen) null else SiloNotice("Couldn’t Switch Profile", message, signInAgain = expired),
                    )
                }
            }
        }
    }

    private fun siloClientFor(session: SavedSession): SiloAccountClient {
        val link = session.siloLink ?: throw ZelefinException.missingUser()
        siloClient?.takeIf { it.first == session.accountId }?.let { return it.second }
        val client = SiloAccountClient(link.nativeUrl, link.tokens, ::persistSiloTokens)
        siloClient = session.accountId to client
        return client
    }

    /** Saves a refreshed Silo token pair into whichever saved account held the old one. */
    private fun persistSiloTokens(previous: SiloTokens?, next: SiloTokens) {
        val stale = previous?.refreshToken ?: return
        vault.accounts().filter { it.siloLink?.refreshToken == stale }.forEach { saved ->
            val updated = saved.copy(siloLink = saved.siloLink?.withTokens(next))
            vault.save(updated, select = false)
            if (_state.value.session?.accountId == saved.accountId) {
                _state.update { it.copy(session = updated, accounts = vault.accounts()) }
            }
        }
    }

    /** Keeps the saved profile name and picture in step with Silo. */
    private fun applySiloProfile(accountId: String, profile: SiloProfile) {
        val latest = _state.value.session?.takeIf { it.accountId == accountId } ?: return
        val link = latest.siloLink ?: return
        val updatedLink = link.withProfile(profile)
        _state.update { state ->
            state.copy(household = state.household.copy(profiles = state.household.profiles.map { if (it.id == profile.id) profile else it }))
        }
        if (updatedLink == link && latest.userName == profile.name) return
        val updated = latest.copy(siloLink = updatedLink, userName = profile.name)
        vault.save(updated, select = false)
        _state.update { it.copy(session = updated, accounts = vault.accounts()) }
    }

    private fun logOutSiloQuietly(client: SiloAccountClient) {
        viewModelScope.launch { runCatching { client.logout() } }
    }

    private fun logOutJellyfinQuietly(session: SavedSession) {
        viewModelScope.launch { runCatching { JellyfinLibrary(getApplication(), session.serverUrl, session.accessToken).logout() } }
    }

    private fun Throwable.isSiloSignInExpired(): Boolean =
        this is ZelefinException && code == ZelefinException.Code.SiloSignInExpired

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
                storeJellyfin(
                    url = url,
                    token = result.accessToken.orEmpty(),
                    userId = result.user?.id?.toString().orEmpty(),
                    userName = result.user?.name ?: "Jellyfin",
                    imageTag = result.user?.primaryImageTag,
                    serverName = null,
                    serverVersion = null,
                    isSiloServer = library.detectSiloServer() == true,
                )
                _state.update { it.copy(quickConnect = null, screen = Screen.Library, busy = false) }
                refreshLibrary()
                _state.value.session?.let(::bindSessionSocket)
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

    /** On cold launch, open the page the user chose as their start page (Home by default). */
    private fun applyStartPage() {
        val start = app.zelefin.client.ui.StartPagePreferences.tab
        if (start == app.zelefin.client.ui.DockTab.Home) return
        val appTab = start.appTab ?: return
        if (!app.zelefin.client.ui.TabPreferences.isShown(start)) return
        selectTab(appTab)
    }

    fun selectTab(tab: AppTab) {
        _state.update { it.copy(tab = tab, screen = Screen.Library) }
        if (tab == AppTab.Movies) loadCatalog(AppTab.Movies)
        if (tab == AppTab.Shows) loadCatalog(AppTab.Shows)
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
            val result = runCatching { jellyfinClient().searchHints(userUuid(), trimmed) }
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
            val genres = runCatching { jellyfinClient().genres(userUuid(), limit = 48) }
                .getOrDefault(emptyList()).collapsedGenres().take(24)
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

    fun sessionsClient(): JellyfinLibrary? = jellyfin.takeIf { _state.value.session?.isSiloServer == false }

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
        if (people.isEmpty()) return
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
                    if ((_state.value.screen as? Screen.Detail)?.id == target) {
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
                if (played) jellyfinClient().markPlayed(item.id) else jellyfinClient().markUnplayed(item.id)
            }.onSuccess {
                _state.update { state -> state.withItem(item.id) { copy(isPlayed = played) } }
                refreshLibrary()
            }.onFailure { error -> _state.update { it.copy(message = error.message) } }
        }
    }

    fun toggleFavorite(item: MediaItem) {
        val favorite = !item.isFavorite
        viewModelScope.launch {
            runCatching { jellyfinClient().setFavorite(item.id, favorite) }.onSuccess {
                _state.update { state -> state.withItem(item.id) { copy(isFavorite = favorite) } }
                refreshLibrary()
            }.onFailure { error -> _state.update { it.copy(message = error.message) } }
        }
    }

    fun toggleWatchlist(item: MediaItem) {
        if (_state.value.isSiloServer) return
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
                jellyfinClient().randomTitle(userUuid()) ?: throw ZelefinException.server("Nothing to pick yet.")
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
                        } ?: jellyfinClient().detail(userUuid(), item.seriesId ?: item.id)
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
        if (session.isSiloServer) throw ZelefinException.server("Collections are edited in Silo.")
        return jellyfinClient().collectionEditor(UUID.fromString(session.userId), itemId)
    }

    suspend fun collectionPosterMembers(parentId: String): List<MediaItem> {
        val session = _state.value.session ?: return emptyList()
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
            if (!fromSyncPlay && _state.value.syncPlayGroupId != null && !_state.value.isSiloServer) {
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
            val userId = UUID.fromString(_state.value.session?.userId)
            val client = jellyfinClient()
            if (bitrateOverride == null) measureConnectionIfUnknown(appContext, client)
            // The user's account settings (Settings → Playback) decide the starting streams.
            val plan = client.playback(
                userId,
                target,
                PlaybackPreferences.AUTOMATIC,
                PlaybackPreferences.AUTOMATIC,
                preferSdh = PlaybackPreferences.preferSdh(appContext),
            ) { sourceBitrate ->
                bitrateOverride ?: streamingCap(appContext, client, sourceBitrate)
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

    /**
     * Off the home network with no recent sample for this network, measure before choosing: with
     * nothing measured Auto Direct Plays the original, which is what froze on a weak hotspot.
     * Costs at most the 4s probe timeout, once per network every 90s.
     */
    private suspend fun measureConnectionIfUnknown(context: Context, client: JellyfinLibrary) {
        if (PlaybackPreferences.selectedQuality(context) != PlaybackQuality.Auto) return
        if (ServerUrl.isInternalHost(playbackHost())) return
        runCatching { AdaptiveBitrateStore.refreshIfNeeded(context, client::measureBitrate) }
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

    /**
     * Theme song and video for a title page, when the user turned them on in Settings → Playback
     * and the server has them. Silo serves theme songs only.
     */
    suspend fun themeMedia(itemId: String): ThemeMedia? {
        val context = getApplication<Application>()
        if (!PlaybackPreferences.themeSongs(context) && !PlaybackPreferences.themeVideos(context)) return null
        val session = _state.value.session ?: return null
        val media = runCatching { jellyfinClient().themeMedia(itemId, UUID.fromString(session.userId)) }.getOrNull()
            ?: return null
        val videoUrl = media.videoUrl?.takeIf { PlaybackPreferences.themeVideos(context) }?.let { ServerRoute.rewrite(it) }
        // As in Jellyfin, a theme video is preferred and the song does not play alongside it.
        val songUrl = media.songUrl?.takeIf { videoUrl == null && PlaybackPreferences.themeSongs(context) }
            ?.let { ServerRoute.rewrite(it) }
        return ThemeMedia(
            songUrl = songUrl,
            videoUrl = videoUrl,
            videoSound = PlaybackPreferences.themeVideoSound(context),
        ).takeIf { !it.isEmpty }
    }

    /** Settings → Playback → Test Connection. Throws with the iOS copy when nothing downloads. */
    suspend fun testConnection(): BitrateProbeResult {
        val session = _state.value.session ?: throw ZelefinException.server("Sign in to test this connection.")
        val transport = NetworkPathSnapshot.current(getApplication()).transport
        val size = AdaptiveBitratePolicy.SETTINGS_SAMPLE_BYTES
        val timeout = AdaptiveBitratePolicy.SETTINGS_PROBE_TIMEOUT_MILLIS
        val result = jellyfinClient().measureBitrate(size, timeout, transport) ?: throw ZelefinException.server(
            "Zelefin could not download the demo file from this server. Check the connection and try again.",
        )
        AdaptiveBitrateStore.record(result, NetworkPathSnapshot.current(getApplication()))
        return result
    }

    /** Stores the language picks and mirrors them into the user's server configuration. */
    fun applyPlaybackLanguages(audioCode: String, subtitleCode: String) {
        val appContext = getApplication<Application>()
        PlaybackPreferences.setAudioLanguage(appContext, audioCode)
        PlaybackPreferences.setSubtitleLanguage(appContext, subtitleCode)
        val session = _state.value.session ?: return
        viewModelScope.launch {
            runCatching {
                jellyfinClient().applyPlaybackLanguages(UUID.fromString(session.userId), audioCode, subtitleCode)
            }
        }
    }

    /** Admin-only: starts a scan of every Jellyfin library. */
    suspend fun scanLibraries() {
        val session = _state.value.session
        if (session == null || session.isSiloServer) throw ZelefinException.server("Sign in to a Jellyfin server to scan its libraries.")
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
        if (_state.value.session == null) throw ZelefinException.server("Sign in to change these settings.")
        return jellyfinClient().playbackPreferences()
    }

    /**
     * Jellyfin picks the starting streams from these, so the device-side language picks step
     * aside; otherwise an older local pick would override what the user just chose.
     */
    suspend fun saveJellyfinPlaybackPreferences(preferences: JellyfinPlaybackPreferences) {
        val session = _state.value.session ?: throw ZelefinException.server("Sign in to change these settings.")
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
                jellyfinClient().reportStop(plan, positionSeconds)
            }
        }
    }

    /** Movie, show, and episode totals. Called when the app returns to the foreground. */
    fun refreshLibraryStats() {
        if (_state.value.session == null) return
        viewModelScope.launch {
            val counts = runCatching { jellyfinServerCounts(_state.value.libraries) }.getOrNull()
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
        current?.let(::endSiloSession)
        val remaining = if (current != null) vault.remove(current.accountId) else null
        if (current == null) vault.clear()
        if (remaining != null) {
            activate(remaining)
            return
        }
        jellyfin = null
        householdJob?.cancel()
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
        endSiloSession(account)
        vault.remove(account.accountId)
        _state.update { it.copy(accounts = vault.accounts()) }
    }

    /** Best-effort native Silo logout for an account that is leaving this phone. */
    private fun endSiloSession(account: SavedSession) {
        val link = account.siloLink ?: return
        val cached = siloClient?.takeIf { it.first == account.accountId }?.second
        if (cached != null) siloClient = null
        logOutSiloQuietly(cached ?: SiloAccountClient(link.nativeUrl, link.tokens))
    }

    fun resetAddAccount() {
        _state.update { it.copy(addAccount = AddAccountState()) }
    }

    /** Signs in another user without dropping the current one (iOS `AddAccountView`). */
    fun addAccount(rawUrl: String, username: String, password: String) {
        _state.update { it.copy(addAccount = AddAccountState(busy = true)) }
        viewModelScope.launch {
            runCatching {
                val url = ServerUrl.normalize(rawUrl)
                val name = username.trim()
                if (name.isEmpty()) throw ZelefinException.server("Enter a username.")
                if (isSiloSignIn(url, name)) {
                    openSiloPicker(url, name, password)
                    _state.update { it.copy(addAccount = AddAccountState()) }
                    return@runCatching
                }
                val library = JellyfinLibrary(getApplication(), url)
                val result = library.login(name, password)
                val user = result.user ?: throw ZelefinException.missingUser()
                val isSilo = library.detectSiloServer() == true
                val session = SavedSession(
                    serverUrl = url,
                    accessToken = result.accessToken.orEmpty(),
                    userId = user.id.toString(),
                    userName = SavedSession.displayName(user.name ?: name, isSilo),
                    deviceId = vault.deviceId,
                    userImageTag = user.primaryImageTag,
                    serverName = user.serverName,
                    isSiloServer = isSilo,
                )
                vault.save(session)
                activate(session)
            }.onFailure { error ->
                if (error is CancellationException) throw error
                _state.update { it.copy(addAccount = it.addAccount.copy(busy = false, message = error.message ?: "Something went wrong.")) }
            }
        }
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
        householdJob?.cancel()
        if (siloClient?.first != session.accountId) siloClient = null
        plugins.reset()
        restore(session)
        _state.update {
            ZelefinUiState(
                screen = Screen.Library,
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
        refreshHousehold()
    }

    /** Uploads a new profile picture (to Silo for a Silo-linked account) and saves it so every avatar reloads. */
    suspend fun updateProfilePhoto(uri: Uri) {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        session.siloLink?.let { link ->
            val jpeg = AccountPhoto.jpeg(getApplication(), uri)
            val profile = siloClientFor(session).uploadAvatar(link.profileId, link.profileToken, jpeg)
            applySiloProfile(session.accountId, profile)
            return
        }
        if (session.isSiloServer) throw ZelefinException.server("Change your profile picture in Silo.")
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
        if (session.isSiloServer) throw ZelefinException.server("Change your password in Silo.")
        jellyfinClient().changeOwnPassword(session.userId, current, new)
    }

    /** Gives the current Silo profile one of Silo's premade avatars. */
    suspend fun chooseSiloAvatarPreset(preset: SiloAvatarPreset) {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        val link = session.siloLink ?: throw ZelefinException.server("Premade pictures need a Silo sign-in.")
        val profile = siloClientFor(session).setAvatarPreset(link.profileId, link.profileToken, preset.id)
        applySiloProfile(session.accountId, profile)
    }

    /** The signed-in Silo profile, freshest copy first. */
    fun currentSiloProfile(): SiloProfile? {
        val link = _state.value.session?.siloLink ?: return null
        return _state.value.household.profiles.firstOrNull { it.id == link.profileId } ?: link.profile
    }

    suspend fun removeProfilePhoto() {
        val session = _state.value.session ?: throw ZelefinException.missingUser()
        session.siloLink?.let { link ->
            val current = currentSiloProfile() ?: link.profile
            val client = siloClientFor(session)
            if (current.avatarSource == "preset") {
                applySiloProfile(session.accountId, client.setAvatarPreset(link.profileId, link.profileToken, presetId = null))
            } else {
                client.deleteAvatar(link.profileId, link.profileToken)
                applySiloProfile(session.accountId, current.copy(avatarUrl = null, avatar = null, avatarSource = "none"))
            }
            return
        }
        if (session.isSiloServer) throw ZelefinException.server("Change your profile picture in Silo.")
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

    /** Silo's socket only keeps alive: it has no SyncPlay and no remote control. */
    private fun bindSessionSocket(session: SavedSession) {
        if (session.isSiloServer) {
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
        return jellyfinClient().playableItem(UUID.fromString(session.userId), fromDetail)
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
            isSiloServer = library.detectSiloServer() == true,
        )
        _state.update { it.copy(busy = false, screen = Screen.Library) }
        refreshLibrary()
        _state.value.session?.let(::bindSessionSocket)
    }

    private fun storeJellyfin(
        url: String,
        token: String,
        userId: String,
        userName: String,
        imageTag: String?,
        serverName: String?,
        serverVersion: String?,
        isSiloServer: Boolean,
    ) {
        val session = SavedSession(
            serverUrl = url,
            accessToken = token,
            userId = userId,
            userName = SavedSession.displayName(userName, isSiloServer),
            deviceId = vault.deviceId,
            userImageTag = imageTag,
            serverName = serverName,
            serverVersion = serverVersion,
            isSiloServer = isSiloServer,
        )
        vault.save(session)
        _state.update { it.copy(session = session, accounts = vault.accounts()) }
        refreshRoute()
    }

    private fun restore(saved: SavedSession) {
        val library = JellyfinLibrary(getApplication(), saved.serverUrl, saved.accessToken)
        jellyfin = library
        viewModelScope.launch { refreshSiloDetection(saved, library) }
    }

    /** Keeps [SavedSession.isSiloServer] current, e.g. for accounts signed in before Silo was detected. */
    private suspend fun refreshSiloDetection(saved: SavedSession, library: JellyfinLibrary) {
        val silo = library.detectSiloServer() ?: return
        val latest = _state.value.session?.takeIf { it.accountId == saved.accountId } ?: return
        if (latest.isSiloServer == silo) return
        val updated = latest.copy(isSiloServer = silo)
        vault.save(updated)
        _state.update { it.copy(session = updated, accounts = vault.accounts()) }
        plugins.refresh()
        bindSessionSocket(updated)
    }

    private suspend fun currentHome(): HomeFeed {
        val hero = app.zelefin.client.ui.HomeLayoutPreferences.heroContent
        return visibleHome(
            jellyfinClient().home(
                UUID.fromString(_state.value.session?.userId),
                JellyfinLibrary.HeroContent.entries.first { it.name == hero.name },
            ),
        )
    }

    /** Pulls Interface and Library layout choices from Jellyfin display preferences (iOS `pullDisplayPreferences`). */
    fun pullDisplayPreferences() {
        val session = _state.value.session ?: return
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
        if (_state.value.session == null) return
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
            val options = runCatching { jellyfinClient().catalogFilters(userUuid(), jellyfinScope(route)) }
                .getOrDefault(catalogOptionsFromItems(items))
            updateGrid(route) { copy(filters = options.forServer()) }
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

    private fun CatalogBrowseQuery.forServer(): CatalogBrowseQuery = if (_state.value.isSiloServer) forSiloServer() else this

    private fun CatalogFilterOptions.forServer(): CatalogFilterOptions = if (_state.value.isSiloServer) forSiloServer() else this

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
        val query = stored.forServer()
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
                when (route) {
                    LibraryRoute.Watchlist -> if (_state.value.isSiloServer) emptyList() else jellyfinClient().watchlistItems(userUuid())
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
            val genres = runCatching { jellyfinClient().genres(userUuid()) }.getOrDefault(emptyList())
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
                val roomsReady = CompletableDeferred<List<LibraryRoom>>()
                val countsJob = launch {
                    val counts = runCatching { jellyfinServerCounts(roomsReady.await()) }.getOrNull()
                    if (counts != null) _state.update { it.copy(libraryOverview = it.libraryOverview.copy(counts = counts)) }
                }
                launch {
                    val collections = jellyfinClient().collectionPreview(userUuid())
                    _state.update { it.copy(libraryOverview = it.libraryOverview.copy(collections = collections)) }
                }
                runCatching { jellyfinClient().libraries(userUuid()) }.onSuccess { rooms ->
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
        val rooms = state.libraryLayout.displayed(state.libraries.libraryTabRooms(state.isSiloServer))
        viewModelScope.launch {
            rooms.forEach { room ->
                if (!onlyMissing || room.id !in state.libraryOverview.roomCounts) launch {
                    val counts = runCatching { jellyfinClient().roomCounts(userUuid(), room) }.getOrNull() ?: return@launch
                    _state.update {
                        it.copy(libraryOverview = it.libraryOverview.copy(roomCounts = it.libraryOverview.roomCounts + (room.id to counts)))
                    }
                }
                if (room.kind == LibraryKind.LiveTV || state.libraryOverview.covers[room.id]?.isNotEmpty() == true) return@forEach
                launch {
                    val covers = runCatching { jellyfinClient().previewItems(userUuid(), room) }.getOrDefault(emptyList())
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
            val kind = if (tab == AppTab.Movies) {
                org.jellyfin.sdk.model.api.BaseItemKind.MOVIE
            } else {
                org.jellyfin.sdk.model.api.BaseItemKind.SERIES
            }
            val options = runCatching { jellyfinClient().catalogFilters(userUuid(), kind) }
                .getOrDefault(catalogOptionsFromItems(items))
                .forServer()
            _state.update { if (tab == AppTab.Movies) it.copy(movieFilters = options) else it.copy(showFilters = options) }
        }
    }

    private fun loadCatalog(tab: AppTab, refreshing: Boolean = false) {
        val session = _state.value.session
        val kind = if (tab == AppTab.Movies) "movies" else "shows"
        val query = (if (tab == AppTab.Movies) _state.value.movieQuery else _state.value.showQuery).forServer()
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

    private suspend fun loadDetail(id: String): TitleDetail =
        jellyfinClient().detail(UUID.fromString(_state.value.session?.userId), id)

    private suspend fun report(plan: PlaybackPlan, position: Double, paused: Boolean, start: Boolean) {
        val library = jellyfinClient()
        if (start) library.reportStart(plan, position) else library.reportProgress(plan, position, paused)
    }

    private fun jellyfinClient(): JellyfinLibrary = jellyfin ?: throw ZelefinException.missingUser()

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

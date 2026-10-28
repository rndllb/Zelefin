package app.zelefin.client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import app.zelefin.client.push.ZelefinPush
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.updateTransition
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ui.BrowseScreen
import app.zelefin.client.ui.ConnectScreen
import app.zelefin.client.ui.DetailScreen
import app.zelefin.client.ui.DetailTitleActions
import app.zelefin.client.ui.LibraryScreen
import app.zelefin.client.ui.SiloNoticeDialog
import app.zelefin.client.ui.SiloPinDialog
import app.zelefin.client.ui.SiloProfilePickerScreen
import app.zelefin.client.ui.PlayerScreen
import app.zelefin.client.ui.ProfileScreen
import app.zelefin.client.ui.AddAccountTopicId
import app.zelefin.client.ui.SettingsBarAction
import app.zelefin.client.ui.SettingsScreen
import app.zelefin.client.ui.SettingsTopicScreen
import app.zelefin.client.ui.cancelPredictiveDismiss
import app.zelefin.client.ui.cancelPredictivePop
import app.zelefin.client.ui.finishPredictiveDismiss
import app.zelefin.client.ui.finishPredictivePop
import app.zelefin.client.ui.followPredictiveDismiss
import app.zelefin.client.ui.followPredictivePop
import app.zelefin.client.ui.LocalCollectionPosters
import app.zelefin.client.ui.LocalZelefinGlassHost
import app.zelefin.client.ui.LocalZelefinHaze
import app.zelefin.client.ui.DockChromeState
import app.zelefin.client.ui.GlassSource
import app.zelefin.client.ui.LocalDockChrome
import app.zelefin.client.ui.LocalGlassDiscPage
import app.zelefin.client.ui.LocalGlassSource
import app.zelefin.client.ui.glassSource
import app.zelefin.client.ui.ZelefinCyan
import app.zelefin.client.ui.ZelefinGlassDock
import app.zelefin.client.ui.ZelefinForeground
import app.zelefin.client.ui.ZelefinGlassDiscs
import app.zelefin.client.ui.ZelefinGlassHost
import app.zelefin.client.ui.LocalZelefinInSheet
import app.zelefin.client.ui.ZelefinPush
import app.zelefin.client.ui.ZelefinPushRelation
import app.zelefin.client.ui.ZelefinSheetScrim
import app.zelefin.client.ui.ZelefinSheetSurface
import app.zelefin.client.ui.ZelefinTheme
import app.zelefin.client.ui.rememberZelefinHazeState
import app.zelefin.client.ui.rememberZelefinPush
import app.zelefin.client.ui.rememberZelefinSheet
import app.zelefin.client.ui.zelefinHazeSource
import app.zelefin.client.ui.zelefinSheetBackdrop
import app.zelefin.core.TitleDetail
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

class MainActivity : ComponentActivity() {
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        app.zelefin.client.ui.PlayerWindow.onUserLeaveHint(this)
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        app.zelefin.client.ui.PlayerWindow.onModeChanged(this, isInPictureInPictureMode)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ZelefinPush.handleLaunch(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) ZelefinPush.handleLaunch(intent)
        enableEdgeToEdge()
        app.zelefin.client.ui.GlassShaders.warmUp(this)
        setContent {
            val model: ZelefinModel = viewModel()
            val state by model.state.collectAsState()
            LifecycleEventEffect(Lifecycle.Event.ON_START) { model.refreshLibraryStats() }
            PushEffects(model, state)
            val configuration = LocalConfiguration.current
            val tablet = configuration.smallestScreenWidthDp >= 600
            val context = LocalContext.current
            LaunchedEffect(state.screen, tablet) {
                val activity = context as? Activity ?: return@LaunchedEffect
                activity.requestedOrientation = when {
                    state.screen is Screen.Player -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
                    tablet -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
            }
            ZelefinTheme {
                val handlesBack = when (val screen = state.screen) {
                    Screen.Connect -> false
                    Screen.Library -> (state.tab == AppTab.Library && state.libraryPath.isNotEmpty()) ||
                        (state.tab == AppTab.Search && state.searchPath.isNotEmpty())
                    else -> true
                }
                var detailCoversDock by remember { mutableStateOf(false) }
                val pageSheet = state.screen.takeIf { it.isPageSheet() }
                val sheetMotion = rememberZelefinSheet(pageSheet)
                val backdrop = sheetMotion.displayed?.underSheet() ?: state.screen
                val sheetUp = sheetMotion.displayed != null
                val sheetNavigation = rememberZelefinPush(sheetMotion.displayed ?: backdrop, ::sheetPushRelation)
                val goBack by rememberUpdatedState(model::back)
                val sheetScreen by rememberUpdatedState(state.screen)
                PredictiveBackHandler(enabled = handlesBack) { events ->
                    val from = sheetScreen
                    val sheetTo = from.sheetBackTarget()
                    val popInSheet = from.isPageSheet() && sheetTo != null && sheetTo.isPageSheet()
                    val dismissSheet = from.isPageSheet() && sheetTo != null && !sheetTo.isPageSheet()
                    try {
                        events.collect { event ->
                            when {
                                popInSheet && sheetTo != null -> sheetNavigation.followPredictivePop(from, sheetTo, event.progress)
                                dismissSheet -> sheetMotion.followPredictiveDismiss(event.progress)
                            }
                        }
                        when {
                            popInSheet && sheetTo != null -> sheetNavigation.finishPredictivePop(sheetTo)
                            dismissSheet -> sheetMotion.finishPredictiveDismiss()
                        }
                        goBack()
                    } catch (e: CancellationException) {
                        withContext(NonCancellable) {
                            when {
                                popInSheet -> sheetNavigation.cancelPredictivePop(from)
                                dismissSheet -> sheetMotion.cancelPredictiveDismiss()
                            }
                        }
                        throw e
                    }
                }
                val navigation = updateTransition(backdrop, label = "page")
                val knownDetails = remember { mutableMapOf<String, TitleDetail>() }
                state.detail?.let { knownDetails[it.item.id] = it }
                LaunchedEffect(backdrop) {
                    if (backdrop !is Screen.Detail && backdrop !is Screen.Browse && backdrop != Screen.Library) detailCoversDock = false
                }
                val hazeState = rememberZelefinHazeState()
                val glassHost = remember { ZelefinGlassHost() }
                val dockChrome = remember { DockChromeState() }
                val glassSource = remember { GlassSource() }
                // Keep the dock hidden for the whole player slide (open and close), so the tab bar never
                // draws over the sheet while it travels; it reappears once the player has fully left.
                val playerActive = navigation.currentState is Screen.Player || navigation.targetState is Screen.Player
                val showDock = state.session != null && !sheetUp && !playerActive && when (backdrop) {
                    Screen.Library -> !detailCoversDock
                    is Screen.Detail -> !detailCoversDock
                    is Screen.Browse -> !detailCoversDock
                    else -> false
                }
                val miniVisible = showDock && state.nowPlaying != null
                SideEffect { dockChrome.hasMiniPlayer = miniVisible }
                LaunchedEffect(state.tab, backdrop.pageKey()) { dockChrome.expand() }
                CompositionLocalProvider(
                    LocalZelefinHaze provides hazeState,
                    LocalZelefinGlassHost provides glassHost,
                    LocalCollectionPosters provides model::collectionPosterMembers,
                    LocalDockChrome provides dockChrome,
                    LocalGlassSource provides glassSource,
                ) {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .glassSource(glassSource)
                            .background(Color.Black)
                            .nestedScroll(dockChrome.scroll)
                            .zelefinHazeSource(hazeState),
                    ) {
                    // Glass drawn inside the page (discs mid-transition) would record the page into
                    // itself; there it falls back to the frosted fill.
                    CompositionLocalProvider(LocalGlassSource provides null) {
                        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(sheetMotion.progress)) {
                            navigation.AnimatedContent(
                                modifier = Modifier.fillMaxSize(),
                                transitionSpec = { pageTransition() },
                                contentKey = { it.pageKey() },
                            ) { screen ->
                                val page = screen.pageKey()
                                CompositionLocalProvider(LocalGlassDiscPage provides page) {
                                    Box(Modifier.fillMaxSize()) {
                                        ZelefinScreen(screen, state, model, knownDetails) { detailCoversDock = it }
                                        // Mid-transition each page carries its own floating buttons (Home's
                                        // avatar and hero ⋯ included) so none blink out while it slides.
                                        if (navigation.currentState != navigation.targetState) {
                                            ZelefinGlassDiscs(hazeState, glassHost, page = page)
                                        }
                                    }
                                }
                            }
                            if (sheetUp) ZelefinSheetScrim(sheetMotion.progress)
                        }
                        if (sheetMotion.displayed != null) {
                            ZelefinSheetSurface(sheetMotion.progress) {
                                CompositionLocalProvider(LocalZelefinInSheet provides true) {
                                    ZelefinPush(sheetNavigation) { screen ->
                                        ZelefinScreen(screen, state, model, knownDetails) { detailCoversDock = it }
                                    }
                                }
                            }
                        }
                    }
                    }
                    if (showDock) {
                        ZelefinGlassDock(
                            chrome = dockChrome,
                            currentTab = state.tab,
                            currentRoomId = state.dockRoomId,
                            entries = app.zelefin.client.ui.TabPreferences.dockEntries(state.libraries),
                            showsNames = app.zelefin.client.ui.TabPreferences.showsNames,
                            nowPlaying = state.nowPlaying,
                            session = state.session,
                            onSelectEntry = { entry -> entry.room?.let(model::selectDockRoom) ?: model.selectTab(entry.tab) },
                            onOpenNowPlaying = { model.playNowPlaying() },
                            onStopNowPlaying = model::clearNowPlaying,
                            modifier = Modifier.align(Alignment.BottomCenter),
                        )
                    }
                    if (!sheetUp && navigation.currentState == navigation.targetState) {
                        ZelefinForeground(glassHost)
                        ZelefinGlassDiscs(hazeState, glassHost)
                        glassHost.content?.invoke()
                    }
                    // Settings pages live in the sheet; their dialogs still use the overlay host.
                    if (sheetUp) glassHost.content?.invoke()
                    app.zelefin.client.ui.DownloadNoticeAlert()
                    app.zelefin.client.ui.SessionMessageAlert()
                    if (state.busy && state.screen == Screen.Connect) {
                        CircularProgressIndicator(color = ZelefinCyan, modifier = Modifier.align(Alignment.Center))
                    }
                    state.siloPicker?.let { picker ->
                        SiloProfilePickerScreen(picker, onChoose = model::chooseSiloProfile, onCancel = model::cancelSiloPicker)
                    }
                    state.siloPin?.let { prompt ->
                        SiloPinDialog(prompt, onSubmit = model::submitSiloPin, onCancel = model::cancelSiloPin)
                    }
                    state.siloNotice?.let { notice ->
                        SiloNoticeDialog(notice, onDismiss = model::dismissSiloNotice, onSignInAgain = model::signInToSiloAgain)
                    }
                }
                }
            }
        }
    }
}

/** Opens tapped alerts once signed in, and asks for notification permission the first time the plugin is found. */
@Composable
private fun PushEffects(model: ZelefinModel, state: ZelefinUiState) {
    val context = LocalContext.current
    val pushItem by ZelefinPush.openItem.collectAsState()
    val accountId = state.session?.accountId
    LaunchedEffect(pushItem, accountId) {
        val id = pushItem ?: return@LaunchedEffect
        if (accountId == null) return@LaunchedEffect
        ZelefinPush.consumeOpenItem(id)
        model.openPushItem(id)
    }
    val plugins by model.plugins.state.collectAsState()
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        model.plugins.registerPush()
    }
    LaunchedEffect(plugins.companionAvailable, plugins.pushEnabled) {
        if (!plugins.companionAvailable || !plugins.pushEnabled) return@LaunchedEffect
        if (!ZelefinPush.needsRuntimePermission() || ZelefinPush.permissionGranted(context)) return@LaunchedEffect
        if (ZelefinPush.hasAskedPermission(context)) return@LaunchedEffect
        ZelefinPush.markAskedPermission(context)
        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}

@Composable
private fun ZelefinScreen(
    screen: Screen,
    state: ZelefinUiState,
    model: ZelefinModel,
    knownDetails: Map<String, TitleDetail>,
    onDetailCoversDock: (Boolean) -> Unit,
) {    when (screen) {
        Screen.Connect -> ConnectScreen(
            state = state,
            onTest = model::testConnection,
            onSignIn = model::signIn,
            onQuickConnect = model::startQuickConnect,
            onCancelQuickConnect = model::cancelQuickConnect,
            onGateway = model::saveGateway,
        )
        Screen.Library -> LibraryScreen(
            state = state,
            onTab = model::selectTab,
            onOpen = model::openItem,
            onPlay = model::play,
            onLibraryRoute = model::openLibraryRoute,
            onLibraryBack = model::back,
            onLibraryQuery = model::applyLibraryQuery,
            onLibraryRefresh = model::refreshLibraryGrid,
            onOverviewRefresh = model::refreshLibraryOverview,
            onLibraryFilters = model::loadLibraryFilters,
            onLibraryLayout = model::updateLibraryLayout,
            onResetLibraryLayout = model::resetLibraryLayout,
            onRefresh = model::refreshLibrary,
            onSignOut = model::signOut,
            onProfile = model::openProfile,
            onSettings = model::openSettings,
            onSessions = model::openSessions,
            onToggleWatched = model::toggleWatched,
            onToggleFavorite = model::toggleFavorite,
            onToggleWatchlist = model::toggleWatchlist,
            onRandom = model::pickRandomTitle,
            onCatalogQuery = model::applyCatalogQuery,
            onCatalogRefresh = model::refreshCatalog,
            onCatalogFilters = model::loadCatalogFilters,
            onCoversDock = onDetailCoversDock,
            onSearchTerm = model::updateSearchTerm,
            onSearchHit = model::openSearchHit,
            onSearchOpen = model::openSearchItem,
            onRemoveRecentSearch = model::removeRecentSearch,
            onClearRecentSearches = model::clearRecentSearches,
            plugins = model.plugins,
            onHideFromHome = model::hideFromHome,
            onSeeAll = { shelf -> model.openBrowse(BrowsePage.Home(shelf)) },
            onBrowse = model::openBrowse,
            onEnsureGrid = model::ensureBrowseGrid,
        )
        is Screen.Browse -> BrowseScreen(
            page = screen.page,
            state = state,
            onBack = model::back,
            onOpen = model::openItem,
            onPlay = model::play,
            onToggleWatched = model::toggleWatched,
            onToggleFavorite = model::toggleFavorite,
            onToggleWatchlist = model::toggleWatchlist,
            onBrowse = model::openBrowse,
            onEnsureGrid = model::ensureBrowseGrid,
            onGridQuery = model::applyLibraryQuery,
            onGridRefresh = model::refreshLibraryGrid,
            onGridFilters = model::loadLibraryFilters,
            onCoversDock = onDetailCoversDock,
            onProfile = model::openProfile,
            onSessions = model::openSessions,
            onSettings = model::openSettings,
            onSignOut = model::signOut,
        )
        is Screen.Detail -> DetailScreen(
            knownDetails[screen.id] ?: state.detail,
            state.busy,
            state,
            model::back,
            model::play,
            model::openItem,
            model::toggleWatched,
            model::toggleFavorite,
            onCoversDock = onDetailCoversDock,
            onLoadCollections = model::loadCollections,
            onSetCollectionMember = model::setCollectionMember,
            onCreateCollection = model::createCollection,
            plugins = model.plugins,
            actions = detailActions(model, state),
        )
        is Screen.Settings -> SettingsScreen(state, model::back, model::openProfile, model::openSettingsTopic, screen.settingsBar())
        is Screen.Profile -> ProfileScreen(state, model::back, screen.settingsBar())
        is Screen.SettingsTopic -> SettingsTopicScreen(screen.id, state, model.plugins, model::back, screen.settingsBar())
        is Screen.Player -> PlayerScreen(
            plan = screen.plan,
            plugins = model.plugins,
            onProgress = { position, paused -> model.playbackProgress(screen.plan, position, paused) },
            onStopped = { position -> model.playbackStopped(screen.plan, position) },
            onClose = model::closePlayer,
            onPlaybackReady = model::syncPlayPlayerReady,
            onUserTransport = model::forwardSyncPlay,
            onTrackPicked = { pick -> model.rememberTrack(screen.plan.item, pick) },
            directives = model.playerDirectives,
            session = state.session,
            onLoadNext = model::nextEpisode,
            onLoadItem = model::lookupItem,
            onPlayNext = { next, position -> model.playNext(screen.plan, position, next) },
            onReload = { position -> model.reloadPlayback(screen.plan, position) },
            onRecover = { position -> model.recoverPlayback(screen.plan, position) },
            onAdaptiveBitrate = { bitsPerSecond, position -> model.reloadPlaybackAtBitrate(screen.plan, position, bitsPerSecond) },
        )
    }
}

private fun detailActions(model: ZelefinModel, state: ZelefinUiState): DetailTitleActions {
    val tools = state.session?.hasServerTools == true
    return DetailTitleActions(
        onBrowse = model::openBrowse,
        onRefreshDetail = model::refreshDetail,
        remoteTargets = if (tools) model::remotePlayTargets else null,
        playOnRemote = model::playOnRemote,
        syncPlayGroups = if (state.hasJellyfinExtras) model::syncPlayGroups else null,
        playInSyncPlay = model::playInSyncPlay,
        refreshMetadata = if (tools) model::refreshMetadata else null,
        remoteArtwork = if (tools) model::remoteArtwork else null,
        applyArtwork = model::applyRemoteArtwork,
        deleteFromLibrary = if (tools) model::deleteFromLibrary else null,
        onToggleWatchlist = if (tools) model::toggleWatchlist else null,
        onToggleLike = if (state.hasJellyfinExtras) model::toggleLike else null,
        identifyHits = if (tools) model::identifyHits else null,
        applyIdentify = if (tools) model::applyIdentify else null,
        saveMetadata = if (tools) model::saveItemMetadata else null,
        downloadRelated = model::downloadRelated,
    )
}

private fun Screen.isPushedPage(): Boolean = this is Screen.Detail || this is Screen.Browse

private fun Screen.pushedReturn(): Screen? = when (this) {
    is Screen.Detail -> returnTo
    is Screen.Browse -> returnTo
    else -> null
}

/**
 * The player opens and closes like Vellum Music: a full-screen sheet that slides up from the bottom
 * and back down, using Vellum's springs. Translation only — the video SurfaceView can't be scaled,
 * but it slides fine — so the sheet stays on top (high z) while it moves and the page sits behind it.
 */
private fun AnimatedContentTransitionScope<Screen>.pageTransition(): ContentTransform {
    val from = initialState
    val to = targetState
    val spec = tween<IntOffset>(380, easing = CubicBezierEasing(0.32f, 0.72f, 0f, 1f))
    val pop = from.isPushedPage() && (to == from.pushedReturn() || !to.isPushedPage())
    val push = to.isPushedPage() && from !is Screen.Player && !pop
    return when {
        to is Screen.Player && from !is Screen.Player ->
            (slideInVertically(spring(dampingRatio = 0.92f, stiffness = Spring.StiffnessMediumLow)) { it } togetherWith ExitTransition.None)
                .apply { targetContentZIndex = 2f }
        from is Screen.Player && to !is Screen.Player ->
            (EnterTransition.None togetherWith slideOutVertically(spring(dampingRatio = 0.95f, stiffness = Spring.StiffnessMedium)) { it })
                .apply { targetContentZIndex = -1f }
        push -> (slideInHorizontally(spec) { it } togetherWith slideOutHorizontally(spec) { -it / 3 })
            .apply { targetContentZIndex = 1f }
        pop -> (slideInHorizontally(spec) { -it / 3 } togetherWith slideOutHorizontally(spec) { it })
            .apply { targetContentZIndex = 0f }
        else -> (EnterTransition.None togetherWith ExitTransition.None).apply { targetContentZIndex = 1f }
    }
}

private fun Screen.pageKey(): String = when (this) {
    is Screen.Detail -> "detail:$id"
    is Screen.Browse -> "browse:${page.title}:${page.hashCode()}"
    is Screen.Player -> "player:${plan.item.id}"
    is Screen.SettingsTopic -> "topic:$id"
    is Screen.Profile -> "profile"
    is Screen.Settings -> "settings"
    Screen.Connect -> "connect"
    Screen.Library -> "library"
}

private fun sheetPushRelation(from: Screen, to: Screen): ZelefinPushRelation = when {
    from == to -> ZelefinPushRelation.None
    from.isSheetAncestor(to) -> ZelefinPushRelation.Pop
    from.isPageSheet() && to.isPageSheet() -> ZelefinPushRelation.Push
    else -> ZelefinPushRelation.None
}

private fun Screen.isSheetAncestor(ancestor: Screen): Boolean {
    var current = this
    var guard = 0
    while (current.isPageSheet() && guard++ < 8) {
        val parent = current.sheetBackTarget() ?: return false
        if (parent == ancestor) return true
        current = parent
    }
    return false
}

private fun Screen.sheetBackTarget(): Screen? = when (this) {
    is Screen.Settings -> returnTo
    is Screen.Profile -> returnTo
    is Screen.SettingsTopic -> backTo
    else -> null
}

private fun Screen.settingsBar(): SettingsBarAction = when (this) {
    is Screen.Settings -> SettingsBarAction.Done
    is Screen.Profile -> if (returnTo.isPageSheet()) SettingsBarAction.Back else SettingsBarAction.Done
    is Screen.SettingsTopic -> when {
        !backTo.isPageSheet() && id == AddAccountTopicId -> SettingsBarAction.Cancel
        !backTo.isPageSheet() -> SettingsBarAction.Done
        else -> SettingsBarAction.Back
    }
    else -> SettingsBarAction.Back
}

private fun Screen.isPageSheet(): Boolean =
    this is Screen.Settings || this is Screen.Profile || this is Screen.SettingsTopic

private fun Screen.underSheet(): Screen {
    var current = this
    var guard = 0
    while (current.isPageSheet() && guard++ < 8) {
        current = when (current) {
            is Screen.Settings -> current.returnTo
            is Screen.Profile -> current.returnTo
            is Screen.SettingsTopic -> current.backTo
            else -> return current
        }
    }
    return current
}

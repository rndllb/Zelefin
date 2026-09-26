package app.zelefin.client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
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
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.updateTransition
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import app.zelefin.client.ui.ConnectScreen
import app.zelefin.client.ui.DetailScreen
import app.zelefin.client.ui.LibraryScreen
import app.zelefin.client.ui.PinScreen
import app.zelefin.client.ui.PlayerScreen
import app.zelefin.client.ui.ProfileScreen
import app.zelefin.client.ui.ProfilesScreen
import app.zelefin.client.ui.SettingsScreen
import app.zelefin.client.ui.SettingsTopicScreen
import app.zelefin.client.ui.LocalZelefinGlassHost
import app.zelefin.client.ui.LocalZelefinHaze
import app.zelefin.client.ui.ZelefinCyan
import app.zelefin.client.ui.ZelefinFloatingDock
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

class MainActivity : ComponentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ZelefinPush.handleLaunch(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) ZelefinPush.handleLaunch(intent)
        enableEdgeToEdge()
        setContent {
            val model: ZelefinModel = viewModel()
            val state by model.state.collectAsState()
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
                    Screen.Connect, is Screen.Profiles -> false
                    Screen.Library -> (state.tab == AppTab.Library && state.libraryPath.isNotEmpty()) ||
                        (state.tab == AppTab.Search && state.searchPath.isNotEmpty())
                    else -> true
                }
                BackHandler(enabled = handlesBack) { model.back() }
                var detailCoversDock by remember { mutableStateOf(false) }
                val pageSheet = state.screen.takeIf { it.isPageSheet() }
                val sheetMotion = rememberZelefinSheet(pageSheet)
                val backdrop = sheetMotion.displayed?.underSheet() ?: state.screen
                val sheetUp = sheetMotion.displayed != null
                val sheetNavigation = rememberZelefinPush(sheetMotion.displayed ?: backdrop, ::sheetPushRelation)
                val navigation = updateTransition(backdrop, label = "page")
                val knownDetails = remember { mutableMapOf<String, TitleDetail>() }
                state.detail?.let { knownDetails[it.item.id] = it }
                LaunchedEffect(backdrop) {
                    if (backdrop !is Screen.Detail && backdrop != Screen.Library) detailCoversDock = false
                }
                val showDock = state.session != null && !sheetUp && when (backdrop) {
                    Screen.Library -> !detailCoversDock
                    is Screen.Detail -> !detailCoversDock
                    else -> false
                }
                val hazeState = rememberZelefinHazeState()
                val glassHost = remember { ZelefinGlassHost() }
                CompositionLocalProvider(
                    LocalZelefinHaze provides hazeState,
                    LocalZelefinGlassHost provides glassHost,
                ) {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .zelefinHazeSource(hazeState),
                    ) {
                        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(sheetMotion.progress)) {
                            navigation.AnimatedContent(
                                modifier = Modifier.fillMaxSize(),
                                transitionSpec = { pageTransition() },
                                contentKey = { it.pageKey() },
                            ) { screen ->
                                Box(Modifier.fillMaxSize()) {
                                    ZelefinScreen(screen, state, model, knownDetails) { detailCoversDock = it }
                                    if (navigation.currentState != navigation.targetState && screen is Screen.Detail) {
                                        ZelefinGlassDiscs(hazeState, glassHost)
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
                    if (!sheetUp && navigation.currentState == navigation.targetState) {
                        ZelefinForeground(glassHost)
                        ZelefinGlassDiscs(hazeState, glassHost)
                        glassHost.content?.invoke()
                    }
                    if (showDock) {
                        ZelefinFloatingDock(
                            currentTab = state.tab,
                            hazeState = hazeState,
                            onSelect = model::selectTab,
                            modifier = Modifier.align(Alignment.BottomCenter),
                        )
                    }
                    if (state.busy && state.screen == Screen.Connect) {
                        CircularProgressIndicator(color = ZelefinCyan, modifier = Modifier.align(Alignment.Center))
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
            onBackend = model::setBackend,
            onTest = model::testConnection,
            onSignIn = model::signIn,
            onQuickConnect = model::startQuickConnect,
            onCancelQuickConnect = model::cancelQuickConnect,
            onGateway = model::saveGateway,
        )
        is Screen.Profiles -> ProfilesScreen(screen.pending, model::chooseProfile)
        is Screen.Pin -> PinScreen(screen.profile, state.busy, state.message, model::submitPin, model::back)
        Screen.Library -> LibraryScreen(
            state = state,
            onTab = model::selectTab,
            onOpen = model::openItem,
            onPlay = model::play,
            onLibraryRoute = model::openLibraryRoute,
            onLibraryBack = model::back,
            onLibraryQuery = model::applyLibraryQuery,
            onLibraryRefresh = model::refreshLibraryGrid,
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
        )
        is Screen.Settings -> SettingsScreen(state, model::back, model::openProfile, model::openSettingsTopic)
        is Screen.Profile -> ProfileScreen(state, model::back)
        is Screen.SettingsTopic -> SettingsTopicScreen(screen.id, state, model.plugins, model::back)
        is Screen.Player -> PlayerScreen(
            plan = screen.plan,
            plugins = model.plugins,
            onProgress = model::playbackProgress,
            onStopped = model::playbackStopped,
            onClose = model::back,
        )
    }
}

private fun AnimatedContentTransitionScope<Screen>.pageTransition(): ContentTransform {
    val from = initialState
    val to = targetState
    val spec = tween<IntOffset>(380, easing = CubicBezierEasing(0.32f, 0.72f, 0f, 1f))
    val pop = from is Screen.Detail && (to == from.returnTo || to !is Screen.Detail)
    val push = to is Screen.Detail && from !is Screen.Player && !pop
    return when {
        push -> (slideInHorizontally(spec) { it } togetherWith slideOutHorizontally(spec) { -it / 3 })
            .apply { targetContentZIndex = 1f }
        pop -> (slideInHorizontally(spec) { -it / 3 } togetherWith slideOutHorizontally(spec) { it })
            .apply { targetContentZIndex = 0f }
        else -> (EnterTransition.None togetherWith ExitTransition.None).apply { targetContentZIndex = 1f }
    }
}

private fun Screen.pageKey(): String = when (this) {
    is Screen.Detail -> "detail:$id"
    is Screen.Player -> "player:${plan.item.id}"
    is Screen.SettingsTopic -> "topic:$id"
    is Screen.Pin -> "pin:${profile.id}"
    is Screen.Profiles -> "profiles"
    is Screen.Profile -> "profile"
    is Screen.Settings -> "settings"
    Screen.Connect -> "connect"
    Screen.Library -> "library"
}

private fun sheetPushRelation(from: Screen, to: Screen): ZelefinPushRelation {
    val deeper = to is Screen.SettingsTopic || to is Screen.Profile
    val shallower = to is Screen.Settings
    return when {
        from is Screen.Settings && deeper -> ZelefinPushRelation.Push
        from is Screen.SettingsTopic && to is Screen.Profile -> ZelefinPushRelation.Push
        from is Screen.SettingsTopic && shallower -> ZelefinPushRelation.Pop
        from is Screen.Profile && (shallower || to is Screen.SettingsTopic) -> ZelefinPushRelation.Pop
        from is Screen.SettingsTopic && to is Screen.SettingsTopic && from.id != to.id -> ZelefinPushRelation.Push
        else -> ZelefinPushRelation.None
    }
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

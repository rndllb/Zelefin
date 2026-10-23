package app.zelefin.client.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.AppTab
import app.zelefin.client.BrowsePage
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.LibraryGridState
import app.zelefin.client.LibraryRoute
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind

/** The dock route a Collections, Favorites, or pinned-library tab opens at its root. */
fun dockRoute(state: ZelefinUiState): LibraryRoute? = when (state.tab) {
    AppTab.Collections -> LibraryRoute.AllCollections
    AppTab.Favorites -> LibraryRoute.Favorites
    AppTab.Room -> state.libraries.firstOrNull { it.id == state.dockRoomId }?.let { LibraryRoute.Room(it) }
    else -> null
}

/** Collections, Favorites, and pinned custom libraries in the dock (iOS `CatalogGridView` tabs). */
@Composable
fun DockRoutePage(
    state: ZelefinUiState,
    bottomInset: Dp,
    onOpen: (MediaItem) -> Unit,
    onBrowse: (BrowsePage) -> Unit,
    onEnsureGrid: (LibraryRoute) -> Unit,
    onQuery: (LibraryRoute, CatalogBrowseQuery) -> Unit,
    onRefresh: (LibraryRoute) -> Unit,
    onFilters: (LibraryRoute) -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val route = dockRoute(state)
    if (route == null) {
        Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
            Text("This library isn’t available right now.", color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 16.sp)
        }
        return
    }
    LaunchedEffect(route) { onEnsureGrid(route) }
    val grid = state.libraryGrids[route] ?: LibraryGridState()
    CatalogBrowsePage(
        title = route.title,
        items = grid.items,
        query = grid.query,
        options = grid.filters,
        session = state.session,
        refreshing = grid.refreshing,
        loading = grid.loading,
        bottomInset = bottomInset,
        onOpen = onOpen,
        onRefresh = { onRefresh(route) },
        onQuery = { onQuery(route, it) },
        onLoadFilters = { onFilters(route) },
        onCoversDock = onCoversDock,
        onProfile = onProfile,
        onSessions = onSessions,
        onSettings = onSettings,
        onSignOut = onSignOut,
        emptyMessage = when (route) {
            LibraryRoute.Favorites -> "Titles you favorite will show up here."
            LibraryRoute.AllCollections -> "Collections from this server will show up here."
            else -> "Titles from this library will show up here."
        },
    )
}

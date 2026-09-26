package app.zelefin.client.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.BrowsePage
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.HomeShelf
import app.zelefin.client.LibraryGridState
import app.zelefin.client.LibraryRoute
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.CreditPerson
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import app.zelefin.core.TitleTrailer
import kotlin.math.max

private val BrowseHeaderHeight = 59.dp
private val BrowseCaption = Color.White.copy(alpha = 0.55f)

/** Full list pages pushed from row chevrons on Home and title pages. */
@Composable
fun BrowseScreen(
    page: BrowsePage,
    state: ZelefinUiState,
    onBack: () -> Unit,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onBrowse: (BrowsePage) -> Unit,
    onEnsureGrid: (LibraryRoute) -> Unit,
    onGridQuery: (LibraryRoute, CatalogBrowseQuery) -> Unit,
    onGridRefresh: (LibraryRoute) -> Unit,
    onGridFilters: (LibraryRoute) -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val session = state.session
    Box(Modifier.fillMaxSize().background(ZelefinBlack)) {
        when (page) {
            is BrowsePage.Library -> {
                val route = page.route
                LaunchedEffect(route) { onEnsureGrid(route) }
                val grid = state.libraryGrids[route] ?: LibraryGridState()
                CatalogBrowsePage(
                    title = route.title,
                    items = grid.items,
                    query = grid.query,
                    options = grid.filters,
                    session = session,
                    refreshing = grid.refreshing,
                    loading = grid.loading,
                    bottomInset = DockContentReserve,
                    onOpen = onOpen,
                    onRefresh = { onGridRefresh(route) },
                    onQuery = { onGridQuery(route, it) },
                    onLoadFilters = { onGridFilters(route) },
                    onCoversDock = onCoversDock,
                    onProfile = onProfile,
                    onSessions = onSessions,
                    onSettings = onSettings,
                    onSignOut = onSignOut,
                    onBack = onBack,
                    emptyMessage = when (route) {
                        is LibraryRoute.Person -> "Titles with ${route.name} will show up here."
                        is LibraryRoute.Collection -> "Titles in this collection will show up here."
                        else -> null
                    },
                )
            }
            is BrowsePage.Home -> {
                val items = when (page.shelf) {
                    HomeShelf.ContinueWatching -> state.home.continueWatching
                    HomeShelf.NextUp -> state.home.nextUp
                    HomeShelf.RecentMovies -> state.home.recentMovies
                    HomeShelf.RecentShows -> state.home.recentShows
                }
                if (page.shelf.queue) {
                    QueueListPage(
                        title = page.title,
                        items = items,
                        context = if (page.shelf == HomeShelf.NextUp) TitleMenuContext.NextUp else TitleMenuContext.ContinueWatching,
                        session = session,
                        usesSilo = session?.usesSilo == true,
                        onBack = onBack,
                        onOpen = onOpen,
                        onPlay = onPlay,
                        onToggleWatched = onToggleWatched,
                        onToggleFavorite = onToggleFavorite,
                    )
                } else {
                    PosterGridPage(page.title, items, session, onBack, onOpen)
                }
            }
            is BrowsePage.Shelf -> PosterGridPage(page.title, page.items, session, onBack, onOpen)
            is BrowsePage.Trailers -> TrailerListPage(page.trailers, page.owner, session, onBack, onPlay)
            is BrowsePage.Cast -> CastListPage(page.people, session, onBack) { person ->
                if (session?.usesSilo != true && person.id.isNotBlank()) {
                    onBrowse(BrowsePage.Library(LibraryRoute.Person(person.id, person.name)))
                }
            }
        }
    }
}

@Composable
private fun BrowseHeader(title: String, onBack: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(ZelefinBlack, ZelefinBlack.copy(alpha = 0.85f), Color.Transparent)))
            .statusBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        GlassBackDisc("browse-back-$title", true, onBack)
        Spacer(Modifier.width(12.dp))
        Text(
            title,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun browseTop() = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + BrowseHeaderHeight

@Composable
private fun EmptyBrowse(message: String) {
    Text(
        message,
        color = ZelefinMuted,
        fontFamily = ZelefinFont,
        fontSize = 16.sp,
        modifier = Modifier.fillMaxWidth().padding(top = browseTop() + 40.dp, start = 32.dp, end = 32.dp),
    )
}

@Composable
private fun QueueListPage(
    title: String,
    items: List<MediaItem>,
    context: TitleMenuContext,
    session: SavedSession?,
    usesSilo: Boolean,
    onBack: () -> Unit,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
) {
    var more by remember { mutableStateOf<TitleMoreRequest?>(null) }
    val listState = rememberLazyListState()
    TrackHazeScroll(listState.isScrollInProgress)
    if (items.isEmpty()) {
        EmptyBrowse("Titles you start watching will show up here.")
    } else {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = browseTop(), bottom = DockContentReserve),
        ) {
            items(items, key = { it.id }) { item ->
                QueueRow(item, session, onClick = { onOpen(item) }) { anchor ->
                    more = TitleMoreRequest(item, context, anchor)
                }
            }
        }
    }
    BrowseHeader(title, onBack)
    TitleMoreOverlay(
        request = more,
        onDismiss = { more = null },
        onPlay = onPlay,
        onOpen = onOpen,
        onToggleWatched = onToggleWatched,
        onToggleFavorite = onToggleFavorite,
        usesSilo = usesSilo,
    )
}

@Composable
private fun QueueRow(item: MediaItem, session: SavedSession?, onClick: () -> Unit, onMore: (Rect) -> Unit) {
    val anchor = remember { mutableStateOf(Rect.Zero) }
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .width(118.dp)
                .height(66.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White.copy(alpha = 0.08f)),
        ) {
            CachedArtwork(
                urls = artworkCandidates(item, session, landscape = true),
                contentDescription = item.continueWatchingTitle,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            if (item.showsResumeProgress) {
                Box(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .padding(horizontal = 8.dp, vertical = 6.dp)
                        .fillMaxWidth()
                        .height(3.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.32f)),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(item.progress.toFloat().coerceIn(0f, 1f))
                            .height(3.dp)
                            .background(Color.White.copy(alpha = 0.85f)),
                    )
                }
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                item.continueWatchingTitle,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val subtitle = listOfNotNull(
                item.name.takeIf { it != item.continueWatchingTitle },
                item.continueWatchingCaption,
            ).joinToString(" · ")
            if (subtitle.isNotEmpty()) {
                Text(subtitle, color = BrowseCaption, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(
            Icons.Filled.MoreHoriz,
            contentDescription = "More",
            tint = Color.White.copy(alpha = 0.75f),
            modifier = Modifier
                .size(36.dp)
                .onGloballyPositioned { anchor.value = it.boundsInRoot() }
                .clickable { onMore(anchor.value) }
                .padding(6.dp),
        )
    }
}

@Composable
private fun PosterGridPage(
    title: String,
    items: List<MediaItem>,
    session: SavedSession?,
    onBack: () -> Unit,
    onOpen: (MediaItem) -> Unit,
) {
    if (items.isEmpty()) {
        EmptyBrowse("Titles will show up here.")
    } else {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val inset = 16.dp
            val spacing = 10.dp
            val count = max(3, ((maxWidth - inset * 2 + spacing) / (124.dp + spacing)).toInt())
            val gridState = rememberLazyGridState()
            TrackHazeScroll(gridState.isScrollInProgress)
            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Fixed(count),
                contentPadding = PaddingValues(start = inset, end = inset, top = browseTop(), bottom = DockContentReserve),
                horizontalArrangement = Arrangement.spacedBy(spacing),
                verticalArrangement = Arrangement.spacedBy(20.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(items, key = { it.id }) { item ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .aspectRatio(2f / 3f)
                            .clickable { onOpen(item) }
                            .posterChrome(),
                    ) {
                        CachedArtwork(
                            urls = artworkCandidates(item, session, landscape = false),
                            contentDescription = item.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
                        )
                        ItemPosterMarks(item, portrait = true)
                    }
                }
            }
        }
    }
    BrowseHeader(title, onBack)
}

@Composable
private fun TrailerListPage(
    trailers: List<TitleTrailer>,
    owner: MediaItem,
    session: SavedSession?,
    onBack: () -> Unit,
    onPlay: (MediaItem) -> Unit,
) {
    val context = LocalContext.current
    val listState = rememberLazyListState()
    TrackHazeScroll(listState.isScrollInProgress)
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = browseTop(), bottom = DockContentReserve),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(trailers, key = { it.id }) { trailer ->
            TrailerCard(trailer, owner, session, fillWidth = true) {
                val local = trailer.localItem
                if (local != null) {
                    onPlay(local)
                } else {
                    val url = trailer.watchUrl ?: return@TrailerCard
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }
            }
        }
    }
    BrowseHeader("Trailers", onBack)
}

@Composable
private fun CastListPage(
    people: List<CreditPerson>,
    session: SavedSession?,
    onBack: () -> Unit,
    onPerson: (CreditPerson) -> Unit,
) {
    val listState = rememberLazyListState()
    TrackHazeScroll(listState.isScrollInProgress)
    val tappable = session?.usesSilo != true
    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = browseTop(), bottom = DockContentReserve),
    ) {
        items(people, key = { it.id + it.roleLabel }) { person ->
            val photo = session?.serverUrl?.let { ArtworkUrls.person(it, person, session.accessToken) }
            Row(
                Modifier
                    .fillMaxWidth()
                    .then(if (tappable) Modifier.clickable { onPerson(person) } else Modifier)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(56.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        person.name.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp,
                    )
                    if (photo != null) {
                        CachedArtwork(url = photo, contentDescription = person.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(person.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1)
                    if (person.roleLabel.isNotBlank()) {
                        Text(person.roleLabel, color = BrowseCaption, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 1)
                    }
                }
                if (tappable) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color.White.copy(alpha = 0.35f))
                }
            }
        }
    }
    BrowseHeader("Cast & Crew", onBack)
}

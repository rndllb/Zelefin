package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.AppTab
import app.zelefin.client.LibraryRoom
import app.zelefin.client.Screen
import app.zelefin.client.ZelefinUiState
import app.zelefin.core.HouseholdProfile
import app.zelefin.core.MediaBackend
import app.zelefin.core.MediaItem
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.SiloPendingSignIn
import app.zelefin.core.TitleDetail

@Composable
fun ProfilesScreen(pending: SiloPendingSignIn, onChoose: (HouseholdProfile) -> Unit) {
    Column(Modifier.fillMaxSize().background(ZelefinBlack).padding(24.dp)) {
        Text("Who’s watching?", style = androidx.compose.material3.MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(24.dp))
        LazyVerticalGrid(columns = GridCells.Adaptive(140.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(pending.profiles.size) { index ->
                val profile = pending.profiles[index]
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickableNoRipple { onChoose(profile) }) {
                    CachedArtwork(
                        url = profile.avatarUrl,
                        contentDescription = profile.name,
                        modifier = Modifier.height(120.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)),
                        contentScale = ContentScale.Crop,
                    )
                    Text(profile.name, modifier = Modifier.padding(top = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (profile.hasPin) Text("PIN", color = ZelefinMuted, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
fun PinScreen(profile: HouseholdProfile, busy: Boolean, message: String?, onSubmit: (String) -> Unit, onBack: () -> Unit) {
    var pin by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().background(ZelefinBlack).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TextButton(onClick = onBack) { Text("Back") }
        Text(profile.name, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge)
        Text("Enter the profile PIN.", color = ZelefinMuted)
        Field("PIN", pin, password = true) { pin = it.filter { char -> char.isDigit() } }
        Button(onClick = { onSubmit(pin) }, enabled = pin.length >= 4 && !busy, colors = ButtonDefaults.buttonColors(containerColor = ZelefinCyan, contentColor = Color.Black)) {
            Text("Continue")
        }
        message?.let { Text(it, color = ZelefinMuted) }
    }
}

@Composable
fun LibraryScreen(
    state: ZelefinUiState,
    onTab: (AppTab) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpenLibrary: (LibraryRoom) -> Unit,
    onRefresh: () -> Unit,
    onSignOut: () -> Unit,
    onProfile: () -> Unit,
    onSettings: () -> Unit,
    onSessions: () -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
) {
    val contentBottom = DockContentReserve
    Box(Modifier.fillMaxSize().background(ZelefinBlack)) {
        Column(Modifier.fillMaxSize()) {
            if (state.tab != AppTab.Home) {
                Row(
                    Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        state.tab.name,
                        color = Color.White,
                        fontFamily = Outfit,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                        fontSize = 34.sp,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onRefresh) { Text("Refresh") }
                    AccountAvatarMenu(state.session, onProfile, onSessions, onSettings, onSignOut)
                }
            }
            state.message?.let { Text(it, color = ZelefinMuted, modifier = Modifier.padding(horizontal = 20.dp)) }
            when (state.tab) {
                AppTab.Home -> HomeFeedPage(
                    state.home,
                    state.session,
                    contentBottom,
                    onOpen,
                    onPlay,
                    state.homeRefreshing,
                    onRefresh,
                    onProfile,
                    onSessions,
                    onSettings,
                    onSignOut,
                    onToggleWatched,
                    onToggleFavorite,
                )
                AppTab.Movies -> PosterGrid(state.movies, state, contentBottom, onOpen)
                AppTab.Shows -> PosterGrid(state.shows, state, contentBottom, onOpen)
                AppTab.Library -> LibraryPane(state, contentBottom, onOpen, onOpenLibrary) { onTab(AppTab.Library) }
                AppTab.Search -> SearchPane(state, contentBottom, onOpen)
            }
        }
    }
}

@Composable
private fun PosterGrid(posters: List<MediaItem>, state: ZelefinUiState, bottomInset: androidx.compose.ui.unit.Dp, onOpen: (MediaItem) -> Unit) {
    if (posters.isEmpty() && state.busy) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = ZelefinCyan) }
        return
    }
    val gridState = rememberLazyGridState()
    TrackHazeScroll(gridState.isScrollInProgress)
    LazyVerticalGrid(
        state = gridState,
        columns = GridCells.Adaptive(132.dp),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = bottomInset),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(posters.size) { index ->
            PosterCard(posters[index], state.session, modifier = Modifier.fillMaxWidth()) { onOpen(posters[index]) }
        }
    }
}

@Composable
fun DetailScreen(
    detail: TitleDetail?,
    busy: Boolean,
    state: ZelefinUiState,
    onBack: () -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpen: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onCoversDock: (Boolean) -> Unit = {},
    onLoadCollections: suspend (String) -> app.zelefin.client.jellyfin.CollectionEditor = { app.zelefin.client.jellyfin.CollectionEditor(emptyList(), emptySet()) },
    onSetCollectionMember: suspend (String, String, Boolean) -> Unit = { _, _, _ -> },
    onCreateCollection: suspend (String, String) -> Unit = { _, _ -> },
) {
    DetailPage(
        detail,
        busy,
        state,
        onBack,
        onPlay,
        onOpen,
        onToggleWatched,
        onToggleFavorite,
        onCoversDock,
        onLoadCollections,
        onSetCollectionMember,
        onCreateCollection,
    )
}

@Composable
fun PlayerScreen(plan: PlaybackPlan, onProgress: (Double, Boolean) -> Unit, onStopped: (Double) -> Unit, onClose: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        PlayerSurface(plan, onProgress, onStopped)
        TextButton(onClick = onClose, modifier = Modifier.align(Alignment.TopStart).padding(8.dp)) { Text("Close", color = Color.White) }
    }
}

@Composable
private fun Field(label: String, value: String, password: Boolean = false, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password && label == "PIN") KeyboardType.NumberPassword else KeyboardType.Text),
        modifier = Modifier.fillMaxWidth(),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = ZelefinCyan,
            cursorColor = ZelefinCyan,
            focusedLabelColor = ZelefinCyan,
        ),
    )
}

@Composable
private fun LibraryPane(
    state: ZelefinUiState,
    bottomInset: androidx.compose.ui.unit.Dp,
    onOpen: (MediaItem) -> Unit,
    onOpenLibrary: (LibraryRoom) -> Unit,
    onBack: () -> Unit,
) {
    var heldItems by remember { mutableStateOf(state.libraryItems) }
    if (state.openLibraryId != null && state.libraryItems.isNotEmpty()) heldItems = state.libraryItems
    val rooms = rememberZelefinPush(state.openLibraryId) { from, to ->
        when {
            from == null && to != null -> ZelefinPushRelation.Push
            from != null && to == null -> ZelefinPushRelation.Pop
            from != to && to != null -> ZelefinPushRelation.Push
            else -> ZelefinPushRelation.None
        }
    }
    ZelefinPush(rooms) { libraryId ->
        if (libraryId != null) {
            val posters = if (state.openLibraryId == libraryId) state.libraryItems else heldItems
            Column(Modifier.fillMaxSize()) {
                TextButton(onClick = onBack, modifier = Modifier.padding(horizontal = 12.dp)) { Text("Libraries") }
                PosterGrid(posters, state, bottomInset, onOpen)
            }
        } else if (state.libraries.isEmpty() && state.busy) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = ZelefinCyan) }
        } else {
            val listState = rememberLazyListState()
            TrackHazeScroll(listState.isScrollInProgress)
            LazyColumn(state = listState, contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(state.libraries, key = { it.id }) { room ->
                    Text(
                        room.name,
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        modifier = Modifier.fillMaxWidth().clickable { onOpenLibrary(room) }.padding(vertical = 14.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SearchPane(state: ZelefinUiState, bottomInset: androidx.compose.ui.unit.Dp, onOpen: (MediaItem) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val results = androidx.compose.runtime.remember(query, state.movies, state.shows, state.home) {
        val needle = query.trim()
        if (needle.isEmpty()) {
            emptyList()
        } else {
            (state.movies + state.shows + state.home.featured + state.home.continueWatching + state.home.nextUp + state.home.recentMovies + state.home.recentShows)
                .distinctBy { it.id }
                .filter { item ->
                    item.name.contains(needle, ignoreCase = true) ||
                        item.seriesName?.contains(needle, ignoreCase = true) == true
                }
        }
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Field("Movies, shows, people", query) { query = it }
        if (query.isBlank()) {
            Text("Search your libraries.", color = ZelefinMuted)
        } else if (results.isEmpty()) {
            Text("No titles match.", color = ZelefinMuted)
        } else {
            val gridState = rememberLazyGridState()
            TrackHazeScroll(gridState.isScrollInProgress)
            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Adaptive(132.dp),
                contentPadding = PaddingValues(bottom = bottomInset),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                items(results.size) { index ->
                    PosterCard(results[index], state.session, modifier = Modifier.fillMaxWidth()) { onOpen(results[index]) }
                }
            }
        }
    }
}

private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)

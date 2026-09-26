package app.zelefin.client.ui

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.DiscoverGridState
import app.zelefin.client.DiscoverUiState
import app.zelefin.client.PluginsController
import app.zelefin.client.PluginsUiState
import app.zelefin.client.SearchMinimumLength
import app.zelefin.client.plugins.DiscoverBrand
import app.zelefin.client.plugins.DiscoverBrandKind
import app.zelefin.client.plugins.DiscoverQuery
import app.zelefin.client.plugins.DiscoverSection
import app.zelefin.client.plugins.SeerrMediaSeason
import app.zelefin.client.plugins.SeerrRequestDefaults
import app.zelefin.client.plugins.SeerrRequestDraft
import app.zelefin.client.plugins.SeerrSeason
import app.zelefin.client.plugins.SeerrSeasonSelection
import app.zelefin.client.plugins.SeerrServiceDetails
import app.zelefin.client.plugins.SeerrServiceServer
import app.zelefin.client.plugins.SeerrTitle
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

private val PosterWidth = 124.dp
private val PosterHeight = 186.dp
private val LogoBackdrop = Color(0xFF2E2E2E)
internal val SheetGroupFill = Color.White.copy(alpha = 0.08f)
internal val SheetGroupShape = RoundedCornerShape(16.dp)
private val Faint = Color.White.copy(alpha = 0.45f)
private val Soft = Color.White.copy(alpha = 0.55f)

/** The Discover scope under the search field: shelves when idle, request rows while searching. */
@Composable
internal fun DiscoverPane(
    discover: DiscoverUiState,
    plugins: PluginsUiState,
    term: String,
    topInset: Dp,
    bottomInset: Dp,
    onSearch: (String) -> Unit,
    onLoadHome: () -> Unit,
    onOpenQuery: (DiscoverQuery) -> Unit,
    onSelect: (SeerrTitle) -> Unit,
    onDrag: () -> Unit,
) {
    LaunchedEffect(Unit) { onLoadHome() }
    LaunchedEffect(term) { onSearch(term) }
    if (term.length >= SearchMinimumLength) {
        when {
            discover.hits.isEmpty() && (discover.searching || discover.term != term) -> Box(
                Modifier.fillMaxWidth().padding(top = topInset + 40.dp),
                contentAlignment = Alignment.TopCenter,
            ) { CircularProgressIndicator(color = ZelefinCyan) }
            discover.hits.isEmpty() -> DiscoverEmpty("No Results for “$term”", "Check the spelling or try a new search.", topInset)
            else -> {
                val listState = rememberLazyListState()
                TrackHazeScroll(listState.isScrollInProgress)
                LaunchedEffect(listState.isScrollInProgress) { if (listState.isScrollInProgress) onDrag() }
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(top = topInset, bottom = bottomInset + 32.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(discover.hits, key = { it.id }) { hit ->
                        SeerrRequestRow(discover.resolved(hit), discover, plugins) { onSelect(hit) }
                    }
                }
            }
        }
        return
    }
    when {
        discover.sections.isEmpty() && discover.loading -> Box(
            Modifier.fillMaxWidth().padding(top = topInset + 40.dp),
            contentAlignment = Alignment.TopCenter,
        ) { CircularProgressIndicator(color = ZelefinCyan) }
        discover.sections.isEmpty() && discover.message != null ->
            DiscoverEmpty("Couldn’t Load Discover", discover.message, topInset)
        else -> {
            val listState = rememberLazyListState()
            TrackHazeScroll(listState.isScrollInProgress)
            LaunchedEffect(listState.isScrollInProgress) { if (listState.isScrollInProgress) onDrag() }
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(top = topInset + 8.dp, bottom = bottomInset + 32.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(discover.sections, key = { it.id }) { section ->
                    DiscoverShelf(section, discover, onOpenQuery, onSelect)
                }
            }
        }
    }
}

@Composable
private fun DiscoverShelf(
    section: DiscoverSection,
    discover: DiscoverUiState,
    onOpenQuery: (DiscoverQuery) -> Unit,
    onSelect: (SeerrTitle) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val query = section.query
        Row(
            Modifier
                .padding(horizontal = 16.dp)
                .then(if (query != null) Modifier.clickable { onOpenQuery(query) } else Modifier),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(section.title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
            if (query != null) {
                Icon(Icons.Filled.KeyboardArrowRight, contentDescription = null, tint = Faint, modifier = Modifier.size(16.dp))
            }
        }
        val rowState = rememberLazyListState()
        TrackHazeScroll(rowState.isScrollInProgress)
        LazyRow(
            state = rowState,
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (section.isBrandRow) {
                items(section.brands, key = { it.id }) { brand ->
                    DiscoverBrandCard(brand) { onOpenQuery(brand.query) }
                }
            } else {
                items(section.titles, key = { section.id + it.id }) { title ->
                    SeerrPoster(discover.resolved(title), Modifier.width(PosterWidth).height(PosterHeight)) { onSelect(title) }
                }
            }
        }
    }
}

@Composable
private fun DiscoverBrandCard(brand: DiscoverBrand, onClick: () -> Unit) {
    if (brand.kind == DiscoverBrandKind.Genre) {
        Box(Modifier.width(PosterWidth)) { GenreCard(brand.name, onClick = onClick) }
        return
    }
    Box(
        Modifier
            .width(174.dp)
            .height(114.dp)
            .posterChrome()
            .background(LogoBackdrop)
            .clickable(onClick = onClick)
            .padding(18.dp),
        contentAlignment = Alignment.Center,
    ) {
        CachedArtwork(
            urls = listOfNotNull(brand.imageUrl),
            contentDescription = brand.name,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun SeerrPoster(title: SeerrTitle, modifier: Modifier, onClick: () -> Unit) {
    val locked = title.availability.isOnServer
    Box(
        modifier
            .posterChrome()
            .background(SheetGroupFill)
            .then(if (locked) Modifier else Modifier.clickable(onClick = onClick)),
    ) {
        CachedArtwork(
            urls = listOfNotNull(title.posterUrl),
            contentDescription = title.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        if (!locked) {
            Box(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(6.dp)
                    .size(24.dp)
                    .shadow(3.dp, CircleShape)
                    .background(Color.White, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (title.kind == SeerrTitle.Kind.Movie) Icons.Filled.Movie else Icons.Filled.Tv,
                    contentDescription = null,
                    tint = Color.Black,
                    modifier = Modifier.size(13.dp),
                )
            }
        }
        if (locked) LibraryMark(Modifier.align(Alignment.TopEnd).padding(6.dp), 20.dp)
        val requester = title.requestedByName
        if (!locked && requester != null) {
            Text(
                requester,
                color = Color.Black,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(6.dp)
                    .shadow(3.dp, CircleShape)
                    .background(Color.White, CircleShape)
                    .padding(horizontal = 8.dp, vertical = 5.dp),
            )
        }
    }
}

@Composable
private fun LibraryMark(modifier: Modifier, side: Dp) {
    Box(modifier.size(side).shadow(4.dp, CircleShape).background(Color.Black, CircleShape), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.CheckCircle, contentDescription = "In Library", tint = Color.White, modifier = Modifier.size(side))
    }
}

@Composable
private fun SeerrRequestRow(title: SeerrTitle, discover: DiscoverUiState, plugins: PluginsUiState, onRequest: () -> Unit) {
    val onServer = title.availability.isOnServer
    val fullyOnServer = title.availability == SeerrTitle.Availability.Available ||
        (title.kind == SeerrTitle.Kind.Movie && onServer)
    val requesting = title.id in discover.requesting
    val canRequest = title.canRequest && !fullyOnServer && !requesting
    val label = when {
        fullyOnServer -> "In Library"
        requesting -> "Requesting…"
        title.review == SeerrTitle.Review.PendingApproval -> "Pending"
        else -> title.buttonTitle
    }
    val tappable = !fullyOnServer && (canRequest || (!plugins.oneTapRequests && title.requestId != null))
    Column(Modifier.fillMaxWidth().then(if (tappable) Modifier.clickable(onClick = onRequest) else Modifier)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(Modifier.size(width = 52.dp, height = 78.dp).posterChrome(6.dp).background(SheetGroupFill)) {
                CachedArtwork(
                    urls = listOfNotNull(title.posterUrl),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                if (onServer) LibraryMark(Modifier.align(Alignment.TopEnd).padding(3.dp), 16.dp)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title.name,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 17.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    listOfNotNull(if (title.kind == SeerrTitle.Kind.Movie) "Movie" else "Show", title.year?.toString()).joinToString(" · "),
                    color = Faint,
                    fontFamily = ZelefinFont,
                    fontSize = 15.sp,
                    maxLines = 1,
                )
            }
            Box(
                Modifier
                    .height(28.dp)
                    .clip(CircleShape)
                    .background(if (canRequest) Color.White else Color.White.copy(alpha = 0.18f))
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    color = if (canRequest) Color.Black else Color.White.copy(alpha = 0.7f),
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    maxLines = 1,
                )
            }
        }
        Box(Modifier.fillMaxWidth().padding(start = 82.dp).height(0.5.dp).background(SheetGroupFill))
    }
}

@Composable
private fun DiscoverEmpty(title: String, message: String, topInset: Dp) {
    Column(
        Modifier.fillMaxWidth().padding(top = topInset + 24.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 22.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(message, color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

/** "See All" for a Discover row, a genre, a studio, or a network. Pages in as it scrolls. */
@Composable
internal fun DiscoverGridPage(
    query: DiscoverQuery,
    grid: DiscoverGridState,
    discover: DiscoverUiState,
    bottomInset: Dp,
    onBack: () -> Unit,
    onLoadMore: () -> Unit,
    onSelect: (SeerrTitle) -> Unit,
) {
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val headerHeight = statusTop + 59.dp
    Box(Modifier.fillMaxSize()) {
        when {
            grid.titles.isEmpty() && grid.loading -> Box(
                Modifier.fillMaxWidth().padding(top = headerHeight + 40.dp),
                contentAlignment = Alignment.TopCenter,
            ) { CircularProgressIndicator(color = ZelefinCyan) }
            grid.titles.isEmpty() && grid.message != null ->
                DiscoverEmpty("Couldn’t Load ${query.title}", grid.message, headerHeight)
            else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                val columns = max(3, ((maxWidth - 32.dp + 10.dp) / (PosterWidth + 10.dp)).toInt())
                val gridState = rememberLazyGridState()
                TrackHazeScroll(gridState.isScrollInProgress)
                LaunchedEffect(gridState, grid.titles.size) {
                    snapshotFlow { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
                        .collect { last -> if (last >= grid.titles.size - 4) onLoadMore() }
                }
                LazyVerticalGrid(
                    state = gridState,
                    columns = GridCells.Fixed(columns),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = headerHeight, bottom = bottomInset + 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(grid.titles, key = { _, title -> title.id }) { _, title ->
                        SeerrPoster(
                            discover.resolved(title),
                            Modifier.fillMaxWidth().height(((maxWidth - 32.dp - 10.dp * (columns - 1)) / columns) * 1.5f),
                        ) { onSelect(title) }
                    }
                }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GlassBackDisc("discover-back-${query.key}", shown = true, onBack = onBack)
            Spacer(Modifier.width(12.dp))
            Text(
                query.title,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Seerr request and review options, the same fields iOS shows. */
@Composable
internal fun SeerrRequestSheet(
    title: SeerrTitle,
    plugins: PluginsController,
    canManage: Boolean,
    onClose: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val client = remember { plugins.seerr() }
    var servers by remember { mutableStateOf<List<SeerrServiceServer>>(emptyList()) }
    var details by remember { mutableStateOf<SeerrServiceDetails?>(null) }
    var seasons by remember { mutableStateOf<List<SeerrSeason>>(emptyList()) }
    var mediaSeasons by remember { mutableStateOf<List<SeerrMediaSeason>>(emptyList()) }
    var selected by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var is4k by remember { mutableStateOf(false) }
    var serverId by remember { mutableStateOf<Int?>(null) }
    var profileId by remember { mutableStateOf<Int?>(null) }
    var rootFolder by remember { mutableStateOf("") }
    var languageId by remember { mutableStateOf<Int?>(null) }
    var loading by remember { mutableStateOf(true) }
    var submitting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var openPicker by remember { mutableStateOf<String?>(null) }

    val awaitingApproval = title.review == SeerrTitle.Review.PendingApproval && title.requestId != null
    val regular = seasons.filterNot { it.isSpecials }
    val specials = seasons.filter { it.isSpecials }
    val occupied = mediaSeasons.filter { it.isOccupied(is4k) }.map { it.seasonNumber }.toSet()
    val requestable = regular.map { it.seasonNumber }.filterNot { it in occupied }.toSet()
    val canSubmit = !submitting && serverId != null && profileId != null && rootFolder.isNotEmpty() &&
        !(title.kind == SeerrTitle.Kind.Movie && title.availability == SeerrTitle.Availability.Available && !is4k) &&
        (title.kind != SeerrTitle.Kind.Tv || (selected - occupied).isNotEmpty())

    fun draft() = SeerrRequestDraft(
        kind = title.kind,
        tmdbId = title.tmdbId,
        seasons = if (title.kind == SeerrTitle.Kind.Tv) SeerrSeasonSelection.Numbers((selected - occupied).sorted()) else null,
        is4k = is4k,
        serverId = serverId,
        profileId = profileId,
        rootFolder = rootFolder,
        languageProfileId = languageId,
    )

    suspend fun loadDetails() {
        val id = serverId ?: return
        val seerr = client ?: return
        runCatching {
            if (title.kind == SeerrTitle.Kind.Movie) seerr.radarrDetails(id) else seerr.sonarrDetails(id)
        }.onSuccess { loaded ->
            details = loaded
            val server = loaded.server
            profileId = if (loaded.profiles.any { it.id == server.activeProfileId }) server.activeProfileId else loaded.profiles.firstOrNull()?.id
            rootFolder = if (loaded.rootFolders.any { it.path == server.activeDirectory }) {
                server.activeDirectory ?: loaded.rootFolders.firstOrNull()?.path.orEmpty()
            } else {
                loaded.rootFolders.firstOrNull()?.path ?: server.activeDirectory.orEmpty()
            }
            languageId = loaded.languageProfiles?.takeIf { it.isNotEmpty() }?.let { server.activeLanguageProfileId ?: it.first().id }
        }.onFailure { if (it is CancellationException) throw it else error = it.message }
    }

    fun applySeasonDefaults(occupiedNow: Set<Int>) {
        selected = regular.map { it.seasonNumber }.filterNot { it in occupiedNow }.toSet()
    }

    LaunchedEffect(Unit) {
        val seerr = client
        if (seerr == null) {
            error = "Sign in to Seerr in Settings."
            loading = false
            return@LaunchedEffect
        }
        runCatching {
            if (title.kind == SeerrTitle.Kind.Movie) {
                servers = seerr.radarrServers()
            } else {
                val fetched = async { seerr.sonarrServers() }
                val show = async { seerr.tvDetails(title.tmdbId) }
                servers = fetched.await()
                val tv = show.await()
                seasons = tv.seasons
                mediaSeasons = tv.mediaInfo?.seasons.orEmpty()
                selected = tv.seasons.filterNot { it.isSpecials }.map { it.seasonNumber }
                    .filterNot { number -> mediaSeasons.any { it.seasonNumber == number && it.isOccupied(false) } }.toSet()
            }
            serverId = SeerrRequestDefaults.preferredServer(servers, is4k)?.id
            loadDetails()
            val requestId = title.requestId
            if (requestId != null && awaitingApproval) {
                runCatching { seerr.requestDetails(requestId) }.getOrNull()?.let { stored ->
                    if (stored.is4k == true) is4k = true
                    stored.serverId?.let { serverId = it }
                    loadDetails()
                    stored.profileId?.let { profileId = it }
                    stored.rootFolder?.takeIf { it.isNotEmpty() }?.let { rootFolder = it }
                    stored.languageProfileId?.let { languageId = it }
                    stored.seasons?.map { it.seasonNumber }?.takeIf { it.isNotEmpty() }?.let { numbers ->
                        selected = numbers.toSet() - occupied
                    }
                }
            }
        }.onFailure { if (it is CancellationException) throw it else error = it.message }
        loading = false
    }

    fun submit(action: suspend () -> Unit) {
        submitting = true
        error = null
        scope.launch {
            runCatching { action() }
                .onSuccess { onClose() }
                .onFailure { if (it is CancellationException) throw it else error = it.message }
            submitting = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        SheetBar(title = if (awaitingApproval) "Review" else "Request", leading = "Close", onLeading = onClose)
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            RequestHeader(title)
            when {
                title.availability == SeerrTitle.Availability.Available -> Unit
                loading -> Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ZelefinCyan)
                }
                awaitingApproval && !canManage -> Text("Waiting for approval.", color = Color.White.copy(alpha = 0.7f), fontFamily = ZelefinFont, fontSize = 15.sp)
                else -> {
                    val showOptions = !awaitingApproval || editing
                    if (showOptions) {
                        DestinationSection(
                            kind = title.kind,
                            servers = servers,
                            details = details,
                            is4k = is4k,
                            serverId = serverId,
                            profileId = profileId,
                            rootFolder = rootFolder,
                            languageId = languageId,
                            openPicker = openPicker,
                            onPicker = { openPicker = if (openPicker == it) null else it },
                            on4k = { value ->
                                is4k = value
                                val nowOccupied = mediaSeasons.filter { it.isOccupied(value) }.map { it.seasonNumber }.toSet()
                                applySeasonDefaults(nowOccupied)
                                serverId = SeerrRequestDefaults.preferredServer(servers, value)?.id
                                scope.launch { loadDetails() }
                            },
                            onServer = {
                                serverId = it
                                openPicker = null
                                scope.launch { loadDetails() }
                            },
                            onProfile = { profileId = it; openPicker = null },
                            onRootFolder = { rootFolder = it; openPicker = null },
                            onLanguage = { languageId = it; openPicker = null },
                        )
                        if (title.kind == SeerrTitle.Kind.Tv) {
                            SeasonSection(regular, specials, occupied, requestable, selected) { selected = it }
                        }
                    } else {
                        RequestSummary(
                            server = servers.firstOrNull { it.id == serverId }?.name ?: "Default",
                            quality = details?.profiles?.firstOrNull { it.id == profileId }?.name ?: "Default",
                            drive = rootFolder.ifEmpty { "Default" },
                            seasons = if (title.kind == SeerrTitle.Kind.Tv) {
                                (selected - occupied).sorted().takeIf { it.isNotEmpty() }?.joinToString(", ") { "Season $it" } ?: "None"
                            } else {
                                null
                            },
                        )
                    }
                    if (awaitingApproval) {
                        val requestId = title.requestId ?: 0
                        DecisionButton(if (submitting) "Approving…" else "Approve", filled = true, enabled = !submitting && (!editing || canSubmit)) {
                            submit { plugins.approveSeerr(requestId, draft()) }
                        }
                        DecisionButton("Decline", destructive = true, enabled = !submitting) {
                            submit { plugins.declineSeerr(requestId) }
                        }
                        DecisionButton(if (editing) "Done Editing" else "Edit Request", enabled = !submitting) { editing = !editing }
                    } else {
                        DecisionButton(if (submitting) "Requesting…" else "Request", filled = true, enabled = canSubmit) {
                            submit { plugins.submitSeerr(title, draft()) }
                        }
                    }
                }
            }
            error?.let { Text(it, color = Color(0xFFFF453A), fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 4.dp)) }
        }
    }
}

@Composable
private fun RequestHeader(title: SeerrTitle) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(width = 84.dp, height = 126.dp).posterChrome(10.dp).background(SheetGroupFill)) {
            CachedArtwork(
                urls = listOfNotNull(title.posterUrl),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 20.sp)
            Text(
                listOfNotNull(if (title.kind == SeerrTitle.Kind.Movie) "Movie" else "Show", title.year?.toString(), title.buttonTitle)
                    .joinToString(" · "),
                color = Soft,
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            title.requestedByName?.let {
                Text("Requested by $it", color = Color.White.copy(alpha = 0.7f), fontFamily = ZelefinFont, fontSize = 15.sp)
            }
            title.overview?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = Color.White.copy(alpha = 0.7f), fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun DestinationSection(
    kind: SeerrTitle.Kind,
    servers: List<SeerrServiceServer>,
    details: SeerrServiceDetails?,
    is4k: Boolean,
    serverId: Int?,
    profileId: Int?,
    rootFolder: String,
    languageId: Int?,
    openPicker: String?,
    onPicker: (String) -> Unit,
    on4k: (Boolean) -> Unit,
    onServer: (Int) -> Unit,
    onProfile: (Int) -> Unit,
    onRootFolder: (String) -> Unit,
    onLanguage: (Int) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Download", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        if (servers.isEmpty()) {
            Text(
                if (kind == SeerrTitle.Kind.Movie) "No Radarr server is set up in Seerr." else "No Sonarr server is set up in Seerr.",
                color = Color.White.copy(alpha = 0.7f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
            )
            return
        }
        val visible = servers.filter { it.uses4K == is4k }.ifEmpty { servers }
        Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
            if (servers.any { it.uses4K }) {
                SheetToggleRow("4K", is4k, enabled = true, onChange = on4k)
                SheetGroupDivider()
            }
            SheetPickerRow(
                label = "Server",
                value = servers.firstOrNull { it.id == serverId }?.name ?: "Default",
                open = openPicker == "server",
                options = visible.map { it.id.toString() to it.name },
                selected = serverId?.toString(),
                onToggle = { onPicker("server") },
                onChoose = { onServer(it.toInt()) },
            )
            details?.profiles?.takeIf { it.isNotEmpty() }?.let { profiles ->
                SheetGroupDivider()
                SheetPickerRow(
                    label = "Quality",
                    value = profiles.firstOrNull { it.id == profileId }?.name ?: "Default",
                    open = openPicker == "quality",
                    options = profiles.map { it.id.toString() to it.name },
                    selected = profileId?.toString(),
                    onToggle = { onPicker("quality") },
                    onChoose = { onProfile(it.toInt()) },
                )
            }
            details?.rootFolders?.takeIf { it.isNotEmpty() }?.let { folders ->
                SheetGroupDivider()
                SheetPickerRow(
                    label = "Drive",
                    value = rootFolder.ifEmpty { "Default" },
                    open = openPicker == "drive",
                    options = folders.map { it.path to it.pickerTitle },
                    selected = rootFolder,
                    onToggle = { onPicker("drive") },
                    onChoose = onRootFolder,
                )
            }
            details?.languageProfiles?.takeIf { it.isNotEmpty() }?.let { languages ->
                SheetGroupDivider()
                SheetPickerRow(
                    label = "Language",
                    value = languages.firstOrNull { it.id == languageId }?.name ?: "Default",
                    open = openPicker == "language",
                    options = languages.map { it.id.toString() to it.name },
                    selected = languageId?.toString(),
                    onToggle = { onPicker("language") },
                    onChoose = { onLanguage(it.toInt()) },
                )
            }
        }
    }
}

@Composable
private fun SeasonSection(
    regular: List<SeerrSeason>,
    specials: List<SeerrSeason>,
    occupied: Set<Int>,
    requestable: Set<Int>,
    selected: Set<Int>,
    onChange: (Set<Int>) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Seasons", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.weight(1f))
            if (requestable.isNotEmpty()) {
                val all = selected.containsAll(requestable)
                Text(
                    if (all) "Deselect All" else "Select All",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { onChange(if (all) selected - requestable else selected + requestable) }
                        .padding(4.dp),
                )
            }
        }
        Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
            (regular + specials).forEachIndexed { index, season ->
                if (index > 0) SheetGroupDivider()
                val taken = season.seasonNumber in occupied
                SheetToggleRow(season.title, taken || season.seasonNumber in selected, enabled = !taken) { on ->
                    onChange(if (on) selected + season.seasonNumber else selected - season.seasonNumber)
                }
            }
        }
        Text(
            "Already requested or available seasons stay off. Specials stay off unless you turn them on.",
            color = Faint,
            fontFamily = ZelefinFont,
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun RequestSummary(server: String, quality: String, drive: String, seasons: String?) {
    Column(Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill)) {
        SummaryRow("Server", server)
        SummaryRow("Quality", quality)
        SummaryRow("Drive", drive)
        seasons?.let { SummaryRow("Seasons", it) }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp)) {
        Text(label, color = Soft, fontFamily = ZelefinFont, fontSize = 17.sp)
        Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
        Text(value, color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp, textAlign = TextAlign.End)
    }
}

@Composable
internal fun SheetToggleRow(label: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            color = if (enabled) Color.White else Color.White.copy(alpha = 0.45f),
            fontFamily = ZelefinFont,
            fontSize = 17.sp,
            modifier = Modifier.weight(1f),
        )
        Switch(
            checked = checked,
            enabled = enabled,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Color.White,
                checkedThumbColor = Color.Black,
                disabledCheckedTrackColor = Color.White.copy(alpha = 0.35f),
                disabledCheckedThumbColor = Color.Black.copy(alpha = 0.6f),
            ),
        )
    }
}

@Composable
internal fun SheetPickerRow(
    label: String,
    value: String,
    open: Boolean,
    options: List<Pair<String, String>>,
    selected: String?,
    onToggle: () -> Unit,
    onChoose: (String) -> Unit,
) {
    Column {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp)
            Spacer(Modifier.width(12.dp))
            Text(
                value,
                color = Soft,
                fontFamily = ZelefinFont,
                fontSize = 17.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f),
            )
            Icon(Icons.Filled.UnfoldMore, contentDescription = null, tint = Faint, modifier = Modifier.padding(start = 4.dp).size(16.dp))
        }
        if (open) {
            options.forEach { (id, name) ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onChoose(id) }
                        .background(Color.White.copy(alpha = 0.04f))
                        .padding(start = 32.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(name, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    if (id == selected) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

@Composable
internal fun SheetGroupDivider() {
    Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(SheetGroupFill))
}

@Composable
private fun DecisionButton(
    label: String,
    filled: Boolean = false,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val fill = when {
        filled -> Color.White
        destructive -> Color(0xFFFF453A).copy(alpha = 0.16f)
        else -> Color.White.copy(alpha = 0.14f)
    }
    val text = when {
        filled -> Color.Black
        destructive -> Color(0xFFFF453A)
        else -> Color.White
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(CircleShape)
            .background(fill.copy(alpha = fill.alpha * if (enabled) 1f else 0.4f))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = text.copy(alpha = if (enabled) 1f else 0.5f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
    }
}

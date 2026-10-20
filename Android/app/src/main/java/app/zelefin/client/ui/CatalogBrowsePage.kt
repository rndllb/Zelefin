package app.zelefin.client.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.snapshotFlow
import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.CatalogFeatureFilter
import app.zelefin.client.CatalogFilterChoice
import app.zelefin.client.CatalogFilterOptions
import app.zelefin.client.CatalogSortField
import app.zelefin.client.CatalogStatusFilter
import app.zelefin.client.CatalogVideoKind
import app.zelefin.client.orderedForCatalog
import app.zelefin.client.toggled
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import kotlin.math.max

private val HeaderRowHeight = 59.dp
private val PillHeight = 45.dp
private val PillSegmentWidth = 46.dp
private val GridInset = 16.dp
private val GridColumnSpacing = 10.dp
private val GridRowSpacing = 20.dp

private enum class CatalogSheet { Sort, Filters }

private sealed interface FilterRoute {
    data object Root : FilterRoute
    data class Choices(val title: String) : FilterRoute
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogBrowsePage(
    title: String,
    items: List<MediaItem>,
    query: CatalogBrowseQuery,
    options: CatalogFilterOptions,
    session: SavedSession?,
    refreshing: Boolean,
    loading: Boolean,
    bottomInset: Dp,
    onOpen: (MediaItem) -> Unit,
    onRefresh: () -> Unit,
    onQuery: (CatalogBrowseQuery) -> Unit,
    onLoadFilters: () -> Unit,
    onCoversDock: (Boolean) -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
    onBack: (() -> Unit)? = null,
    emptyMessage: String? = null,
) {
    var sheet by remember { mutableStateOf<CatalogSheet?>(null) }
    var draft by remember { mutableStateOf(query) }
    var filterRoute by remember { mutableStateOf<FilterRoute>(FilterRoute.Root) }
    val motion = rememberZelefinSheet(sheet)
    val shown = remember(items, query) { items.orderedForCatalog(query) }
    var headerVisible by remember { mutableStateOf(true) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val headerHeight = statusTop + HeaderRowHeight

    DisposableEffect(Unit) {
        onDispose { onCoversDock(false) }
    }
    LaunchedEffect(motion.displayed) { onCoversDock(motion.displayed != null) }
    LaunchedEffect(Unit) { onLoadFilters() }
    LaunchedEffect(query) {
        if (sheet == null) draft = query
    }
    LaunchedEffect(shown.isEmpty()) {
        if (shown.isEmpty()) headerVisible = true
    }
    BackHandler(enabled = motion.displayed != null) {
        if (sheet == CatalogSheet.Filters && filterRoute != FilterRoute.Root) {
            filterRoute = FilterRoute.Root
        } else {
            sheet = null
            onQuery(draft)
        }
    }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().zelefinSheetBackdrop(motion.progress)) {
            CatalogGrid(
                title = title,
                items = shown,
                query = query,
                session = session,
                refreshing = refreshing,
                loading = loading,
                headerHeight = headerHeight,
                bottomInset = bottomInset,
                onOpen = onOpen,
                onRefresh = onRefresh,
                onHeaderVisible = { headerVisible = it },
                emptyMessage = emptyMessage,
            )
            CatalogHeader(
                title = title,
                onBack = onBack,
                visible = headerVisible,
                pillShown = motion.displayed == null,
                query = query,
                session = session,
                onSort = {
                    draft = query
                    sheet = CatalogSheet.Sort
                },
                onFilter = {
                    draft = query
                    filterRoute = FilterRoute.Root
                    sheet = CatalogSheet.Filters
                },
                onProfile = onProfile,
                onSessions = onSessions,
                onSettings = onSettings,
                onSignOut = onSignOut,
            )
            if (motion.displayed != null) ZelefinSheetScrim(motion.progress)
        }
        if (motion.displayed != null) {
            ZelefinSheetSurface(motion.progress, canvas = ZelefinBlack) {
                when (val page = motion.displayed) {
                    CatalogSheet.Sort -> SortSheet(
                        query = draft,
                        onChange = { draft = it },
                        onDone = {
                            sheet = null
                            onQuery(draft)
                        },
                    )
                    CatalogSheet.Filters -> FilterSheet(
                        query = draft,
                        options = options,
                        route = filterRoute,
                        onRoute = { filterRoute = it },
                        onChange = { draft = it },
                        onDone = {
                            sheet = null
                            onQuery(draft)
                        },
                    )
                    null -> Unit
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CatalogGrid(
    title: String,
    items: List<MediaItem>,
    query: CatalogBrowseQuery,
    session: SavedSession?,
    refreshing: Boolean,
    loading: Boolean,
    headerHeight: Dp,
    bottomInset: Dp,
    onOpen: (MediaItem) -> Unit,
    onRefresh: () -> Unit,
    onHeaderVisible: (Boolean) -> Unit,
    emptyMessage: String?,
) {
    val refreshState = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = onRefresh,
        state = refreshState,
        modifier = Modifier.fillMaxSize(),
        indicator = {
            PullToRefreshDefaults.Indicator(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = headerHeight - 36.dp),
                isRefreshing = refreshing,
                state = refreshState,
                containerColor = Color(0xFF1C1C1E),
                color = ZelefinCyan,
            )
        },
    ) {
        when {
            items.isEmpty() && loading -> {
                Box(Modifier.fillMaxSize().padding(top = headerHeight), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ZelefinCyan)
                }
            }
            items.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(top = headerHeight + 40.dp, start = 32.dp, end = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (query.isDefault) "No Titles Yet" else "No Matches",
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        if (query.isDefault) {
                            emptyMessage ?: if (title == "Shows") "Shows from this server will show up here." else "Movies from this server will show up here."
                        } else {
                            "No titles match these filters."
                        },
                        color = ZelefinMuted,
                        fontSize = 16.sp,
                    )
                }
            }
            else -> {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val inner = maxWidth - GridInset * 2
                    val count = max(3, ((inner + GridColumnSpacing) / (124.dp + GridColumnSpacing)).toInt())
                    val gridState = rememberLazyGridState()
                    var previousOffset by remember { mutableIntStateOf(0) }
                    var showingHeader by remember { mutableStateOf(true) }
                    LaunchedEffect(gridState) {
                        snapshotFlow {
                            gridState.firstVisibleItemIndex * 100_000 + gridState.firstVisibleItemScrollOffset
                        }.collect { offset ->
                            val delta = offset - previousOffset
                            previousOffset = offset
                            showingHeader = when {
                                offset <= 40 -> true
                                delta > 12 -> false
                                delta < -12 -> true
                                else -> showingHeader
                            }
                            onHeaderVisible(showingHeader)
                        }
                    }
                    Box(Modifier.fillMaxSize()) {
                        LazyVerticalGrid(
                            state = gridState,
                            columns = GridCells.Fixed(count),
                            contentPadding = PaddingValues(start = GridInset, end = GridInset, top = headerHeight, bottom = bottomInset),
                            horizontalArrangement = Arrangement.spacedBy(GridColumnSpacing),
                            verticalArrangement = Arrangement.spacedBy(GridRowSpacing),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            items(items, key = { it.id }) { item ->
                                CatalogPoster(item, session) { onOpen(item) }
                            }
                        }
                        CatalogAlphabetRail(
                            items = items,
                            gridState = gridState,
                            modifier = Modifier.align(Alignment.CenterEnd).padding(top = headerHeight),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CatalogPoster(item: MediaItem, session: SavedSession?, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(2f / 3f)
            .clickable(onClick = onClick)
            .posterChrome(),
    ) {
        if (item.usesGeneratedCollage()) {
            CollectionArtwork(item, session, item.name, Modifier.fillMaxSize())
        } else {
            CachedArtwork(
                urls = artworkCandidates(item, session, landscape = false),
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
            )
        }
        ItemPosterMarks(item, portrait = true)
    }
}

@Composable
private fun CatalogHeader(
    title: String,
    onBack: (() -> Unit)?,
    visible: Boolean,
    pillShown: Boolean,
    query: CatalogBrowseQuery,
    session: SavedSession?,
    onSort: () -> Unit,
    onFilter: () -> Unit,
    onProfile: () -> Unit,
    onSessions: () -> Unit,
    onSettings: () -> Unit,
    onSignOut: () -> Unit,
) {
    val alpha by animateFloatAsState(if (visible) 1f else 0f, tween(180), label = "header")
    val shift by animateDpAsState(if (visible) 0.dp else (-120).dp, tween(180), label = "headerShift")
    Row(
        Modifier
            .fillMaxWidth()
            .offset(y = shift)
            .graphicsLayer { this.alpha = alpha }
            .statusBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            GlassBackDisc("catalog-back-$title", visible, onBack)
            Spacer(Modifier.width(12.dp))
        }
        Text(
            title,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = if (onBack != null) FontWeight.SemiBold else FontWeight.Bold,
            fontSize = if (onBack != null) 22.sp else 34.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        CatalogSortFilterPill("catalog-sort-filter-$title", query.activeFilterCount, visible && pillShown, onSort, onFilter)
        if (onBack == null) {
            Spacer(Modifier.width(12.dp))
            AccountAvatarMenu(session, onProfile, onSessions, onSettings, onSignOut)
        }
    }
}

@Composable
fun GlassBackDisc(key: String, shown: Boolean, onBack: () -> Unit) {
    Box(
        Modifier
            .size(PillHeight)
            .then(
                if (shown) {
                    Modifier.zelefinGlassDisc(key, "Back", Icons.AutoMirrored.Outlined.ArrowBack, onBack)
                } else {
                    Modifier
                },
            ),
    )
}

@Composable
private fun CatalogSortFilterPill(key: String, filterCount: Int, shown: Boolean, onSort: () -> Unit, onFilter: () -> Unit) {
    Box(
        Modifier
            .size(width = PillSegmentWidth * 2 + 1.dp, height = PillHeight)
            .then(
                if (shown) {
                    Modifier.zelefinGlassSplit(
                        key = key,
                        leadingDescription = "Sort",
                        leadingIcon = Icons.Filled.SwapVert,
                        trailingDescription = "Filters",
                        trailingIcon = Icons.Filled.FilterList,
                        onLeading = onSort,
                        onTrailing = onFilter,
                        badge = filterCount,
                    )
                } else {
                    Modifier
                },
            ),
    )
}

@Composable
private fun SortSheet(query: CatalogBrowseQuery, onChange: (CatalogBrowseQuery) -> Unit, onDone: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        SheetBar(title = "Sort", leading = null, onDone = onDone)
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item { SectionLabel("Sort By") }
            item {
                SectionGroup {
                    CatalogSortField.entries.forEach { field ->
                        CheckRow(field.title, selected = query.sort == field) {
                            onChange(
                                query.copy(
                                    sort = field,
                                    sortAscending = if (field.allowsDirection) query.sortAscending else true,
                                ),
                            )
                        }
                    }
                }
            }
            if (query.sort.allowsDirection) {
                item { SectionLabel("Order") }
                item {
                    SectionGroup {
                        CheckRow("Ascending", selected = query.sortAscending) { onChange(query.copy(sortAscending = true)) }
                        CheckRow("Descending", selected = !query.sortAscending) { onChange(query.copy(sortAscending = false)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun FilterSheet(
    query: CatalogBrowseQuery,
    options: CatalogFilterOptions,
    route: FilterRoute,
    onRoute: (FilterRoute) -> Unit,
    onChange: (CatalogBrowseQuery) -> Unit,
    onDone: () -> Unit,
) {
    val motion = rememberZelefinPush(route) { from, to ->
        when {
            from == FilterRoute.Root && to is FilterRoute.Choices -> ZelefinPushRelation.Push
            from is FilterRoute.Choices && to == FilterRoute.Root -> ZelefinPushRelation.Pop
            else -> ZelefinPushRelation.None
        }
    }
    ZelefinPush(motion) { page ->
        when (page) {
            FilterRoute.Root -> FilterRoot(query, options, onChange, onRoute, onDone)
            is FilterRoute.Choices -> FilterChoices(page.title, query, options, onChange) { onRoute(FilterRoute.Root) }
        }
    }
}

@Composable
private fun FilterRoot(
    query: CatalogBrowseQuery,
    options: CatalogFilterOptions,
    onChange: (CatalogBrowseQuery) -> Unit,
    onRoute: (FilterRoute) -> Unit,
    onDone: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        SheetBar(
            title = "Filters",
            leading = "Clear",
            leadingEnabled = query.activeFilterCount > 0,
            onLeading = { onChange(query.cleared()) },
            onDone = onDone,
        )
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item { SectionLabel("Filters") }
            item {
                SectionGroup {
                    CatalogStatusFilter.entries.forEach { value ->
                        CheckRow(value.title, selected = value in query.statuses) {
                            onChange(query.copy(statuses = query.statuses.toggled(value)))
                        }
                    }
                }
            }
            item { SectionLabel("Features") }
            item {
                SectionGroup {
                    CatalogFeatureFilter.entries.forEach { value ->
                        CheckRow(value.title, selected = value in query.features) {
                            onChange(query.copy(features = query.features.toggled(value)))
                        }
                    }
                }
            }
            item { SectionLabel("Video Type") }
            item {
                SectionGroup {
                    CatalogVideoKind.entries.forEach { value ->
                        CheckRow(value.title, selected = value in query.videoKinds) {
                            onChange(query.copy(videoKinds = query.videoKinds.toggled(value)))
                        }
                    }
                }
            }
            item {
                ChoiceLinks(query, options, onRoute)
            }
        }
    }
}

@Composable
private fun ChoiceLinks(query: CatalogBrowseQuery, options: CatalogFilterOptions, onRoute: (FilterRoute) -> Unit) {
    val rows = buildList {
        if (options.genres.isNotEmpty()) add("Genres" to summary(query.genres, options.genres))
        if (options.officialRatings.isNotEmpty()) add("Parental Ratings" to summary(query.officialRatings, options.officialRatings))
        if (options.tags.isNotEmpty()) add("Tags" to summary(query.tags, options.tags))
        if (options.years.isNotEmpty()) add("Years" to yearSummary(query))
        if (options.studios.isNotEmpty()) add("Studios" to summary(query.studios, options.studios))
        if (options.languages.isNotEmpty()) {
            add("Audio Languages" to summary(query.audioLanguages, options.languages))
            add("Subtitle Languages" to summary(query.subtitleLanguages, options.languages))
        }
    }
    rows.forEach { (title, value) ->
        Spacer(Modifier.height(10.dp))
        SectionGroup {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { onRoute(FilterRoute.Choices(title)) }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, color = Color.White, fontSize = 17.sp, modifier = Modifier.weight(1f))
                Text(value, color = ZelefinMuted, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun FilterChoices(
    title: String,
    query: CatalogBrowseQuery,
    options: CatalogFilterOptions,
    onChange: (CatalogBrowseQuery) -> Unit,
    onBack: () -> Unit,
) {
    var search by remember { mutableStateOf("") }
    val choices = when (title) {
        "Genres" -> options.genres
        "Parental Ratings" -> options.officialRatings
        "Tags" -> options.tags
        "Years" -> options.years
        "Studios" -> options.studios
        else -> options.languages
    }
    val selected = when (title) {
        "Genres" -> query.genres
        "Parental Ratings" -> query.officialRatings
        "Tags" -> query.tags
        "Years" -> query.years.map { it.toString() }.toSet()
        "Studios" -> query.studios
        "Audio Languages" -> query.audioLanguages
        else -> query.subtitleLanguages
    }
    val visible = choices.filter { search.isBlank() || it.name.contains(search, ignoreCase = true) }
    Column(Modifier.fillMaxSize()) {
        SheetBar(
            title = title,
            leading = "Back",
            trailing = "Clear",
            trailingEnabled = selected.isNotEmpty(),
            onLeading = onBack,
            onTrailing = { onChange(query.withSelection(title, emptySet())) },
        )
        BasicTextField(
            value = search,
            onValueChange = { search = it },
            textStyle = TextStyle(color = Color.White, fontSize = 17.sp),
            cursorBrush = SolidColor(ZelefinCyan),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            decorationBox = { inner ->
                if (search.isEmpty()) Text("Search", color = ZelefinMuted, fontSize = 17.sp)
                inner()
            },
        )
        LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
            item {
                SectionGroup {
                    visible.forEach { choice ->
                        CheckRow(choice.name, selected = choice.id in selected) {
                            onChange(query.withSelection(title, selected.toggled(choice.id)))
                        }
                    }
                }
            }
        }
    }
}

private fun CatalogBrowseQuery.withSelection(title: String, selected: Set<String>): CatalogBrowseQuery = when (title) {
    "Genres" -> copy(genres = selected)
    "Parental Ratings" -> copy(officialRatings = selected)
    "Tags" -> copy(tags = selected)
    "Years" -> copy(years = selected.mapNotNull { it.toIntOrNull() }.toSet())
    "Studios" -> copy(studios = selected)
    "Audio Languages" -> copy(audioLanguages = selected)
    else -> copy(subtitleLanguages = selected)
}

private fun summary(selected: Set<String>, choices: List<CatalogFilterChoice>): String {
    if (selected.isEmpty()) return "Any"
    val names = choices.filter { it.id in selected }.map { it.name }
    if (names.size <= 2) return names.joinToString(", ")
    return "${names.size} selected"
}

private fun yearSummary(query: CatalogBrowseQuery): String {
    if (query.years.isEmpty()) return "Any"
    val years = query.years.sortedDescending().map { it.toString() }
    if (years.size <= 2) return years.joinToString(", ")
    return "${years.size} selected"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SheetBar(
    title: String,
    leading: String? = null,
    leadingEnabled: Boolean = true,
    trailing: String = "Done",
    trailingEnabled: Boolean = true,
    onLeading: (() -> Unit)? = null,
    onTrailing: (() -> Unit)? = null,
    onDone: (() -> Unit)? = null,
) {
    val leadingIcon = when (leading) {
        "Cancel", "Close" -> Icons.Outlined.Close
        "Back" -> Icons.AutoMirrored.Outlined.ArrowBack
        else -> null
    }
    val action = onTrailing ?: onDone
    val label = if (onTrailing != null) trailing else "Done"
    val enabled = if (onTrailing != null) trailingEnabled else true
    TopAppBar(
        title = { Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1) },
        navigationIcon = {
            when {
                leading == null -> Unit
                leadingIcon != null -> IconButton(onClick = { onLeading?.invoke() }, enabled = leadingEnabled) {
                    Icon(leadingIcon, contentDescription = leading)
                }
                else -> TextButton(onClick = { onLeading?.invoke() }, enabled = leadingEnabled) { Text(leading) }
            }
        },
        actions = {
            if (action != null) {
                if (label == "Refresh") {
                    IconButton(onClick = action, enabled = enabled) { Icon(Icons.Outlined.Refresh, contentDescription = label) }
                } else {
                    TextButton(onClick = action, enabled = enabled) { Text(label) }
                }
            }
        },
        windowInsets = WindowInsets(0, 0, 0, 0),
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
            navigationIconContentColor = MaterialTheme.colorScheme.onSurface,
            actionIconContentColor = MaterialTheme.colorScheme.onSurface,
        ),
    )
}

@Composable
internal fun SectionLabel(text: String) {
    SettingsSectionLabel(text)
}

@Composable
private fun SectionGroup(content: @Composable () -> Unit) {
    Column(
        Modifier
            .padding(horizontal = SettingsGroupMargin)
            .clip(SettingsGroupShape)
            .background(MaterialTheme.colorScheme.surfaceContainer),
    ) {
        content()
    }
}

@Composable
private fun CheckRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = SettingsContentInset, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
        }
    }
}

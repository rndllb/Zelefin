package app.zelefin.client.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.DiscoverUiState
import app.zelefin.client.PluginsController
import app.zelefin.client.plugins.RequestCastMember
import app.zelefin.client.plugins.RequestTitleDetails
import app.zelefin.client.plugins.RequestVideo
import app.zelefin.client.plugins.SeerrTitle
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * Mirrors iOS `RequestTitleDetailView`: a Discover title laid out like a library title, with the
 * request button where Play would be, then trailers, cast, similar titles, and Seerr's or Ombi's facts.
 */
@Composable
internal fun DiscoverTitlePage(
    title: SeerrTitle,
    discover: DiscoverUiState,
    plugins: PluginsController,
    canManage: Boolean,
    requestRevision: Int,
    onBack: () -> Unit,
    onRequest: (SeerrTitle) -> Unit,
    onOpen: (SeerrTitle) -> Unit,
    onOpenLibraryItem: (MediaItem) -> Unit,
) {
    val context = LocalContext.current
    var current by remember(title.id) { mutableStateOf(title) }
    var details by remember(title.id) { mutableStateOf<RequestTitleDetails?>(null) }
    var loading by remember(title.id) { mutableStateOf(true) }
    var error by remember(title.id) { mutableStateOf<String?>(null) }
    var menuAnchor by remember { mutableStateOf<Rect?>(null) }
    val client = remember { plugins.requests() }

    fun keepArtwork(refreshed: SeerrTitle) = refreshed.copy(
        posterUrl = refreshed.posterUrl ?: title.posterUrl,
        year = refreshed.year ?: title.year,
    )

    LaunchedEffect(title.id) {
        val requests = client
        if (requests == null) {
            error = "Sign in to ${plugins.state.value.requestService.title} in Settings."
            loading = false
            return@LaunchedEffect
        }
        coroutineScope {
            val status = async { runCatching { requests.requestStatus(title) }.getOrNull() }
            runCatching { requests.titleDetails(title) }
                .onSuccess { details = it }
                .onFailure { if (it is CancellationException) throw it else error = it.message }
            status.await()?.let { current = keepArtwork(it) }
        }
        loading = false
    }
    LaunchedEffect(requestRevision) {
        if (requestRevision == 0) return@LaunchedEffect
        runCatching { client?.requestStatus(title) }.getOrNull()?.let { current = keepArtwork(it) }
    }

    val shown = discover.resolved(current)
    val loaded = details
    // The title's own library page, when the library has it.
    val libraryItem = discover.catalog.itemId(shown)?.let { id ->
        MediaItem(id = id, name = shown.name, kind = if (shown.kind == SeerrTitle.Kind.Movie) MediaKind.Movie else MediaKind.Series)
    }
    val fullyOnServer = shown.availability == SeerrTitle.Availability.Available ||
        (shown.kind == SeerrTitle.Kind.Movie && shown.availability.isOnServer)
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = dockContentReserve()),
        ) {
            item(key = "hero") {
                DiscoverTitleHero(
                    shown,
                    loaded,
                    canManage,
                    onRequest = { onRequest(shown) },
                    onViewInLibrary = libraryItem?.takeIf { fullyOnServer }?.let { item -> { onOpenLibraryItem(item) } },
                )
            }
            when {
                loaded != null -> {
                    if (loaded.trailers.isNotEmpty()) {
                        item(key = "trailers") {
                            RowHeader("Trailers")
                            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                items(loaded.trailers, key = { it.key }) { video ->
                                    DiscoverVideoCard(video) { context.openUrl(video.watchUrl) }
                                }
                            }
                            Spacer(Modifier.height(20.dp))
                        }
                    }
                    if (loaded.cast.isNotEmpty()) {
                        item(key = "cast") {
                            RowHeader("Cast")
                            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                items(loaded.cast, key = { it.id.toString() + it.role }) { DiscoverCastCard(it) }
                            }
                            Spacer(Modifier.height(20.dp))
                        }
                    }
                    if (loaded.related.isNotEmpty()) {
                        item(key = "related") {
                            RowHeader("More Like This")
                            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                items(loaded.related, key = { it.id }) { related ->
                                    SeerrPoster(discover.resolved(related), Modifier.width(124.dp).height(186.dp)) { onOpen(related) }
                                }
                            }
                            Spacer(Modifier.height(20.dp))
                        }
                    }
                    item(key = "information") { FactsBlock("Information", loaded.facts) }
                }
                loading -> item(key = "loading") {
                    Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = ZelefinCyan)
                    }
                }
                else -> error?.let { message ->
                    item(key = "error") {
                        Text(message, color = ZelefinMuted, fontFamily = ZelefinFont, fontSize = 15.sp, modifier = Modifier.padding(16.dp))
                    }
                }
            }
        }
        GlassBack(onBack, Modifier.align(Alignment.TopStart))
        GlassMore(
            Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(end = 12.dp, top = 8.dp),
        ) { menuAnchor = it }
    }

    BackHandler(enabled = menuAnchor != null) { menuAnchor = null }
    val haze = LocalZelefinHaze.current
    PresentZelefinOverlay(visible = menuAnchor != null && haze != null) {
        val hazeState = haze ?: return@PresentZelefinOverlay
        val anchor = menuAnchor ?: return@PresentZelefinOverlay
        AnchoredMenuFrame(anchor, alignTrailing = true, onDismiss = { menuAnchor = null }, clearBottom = dockContentReserve()) {
            Column(
                Modifier
                    .zelefinGlassChrome(hazeState, ZelefinMenuShape)
                    .zelefinMenuWidth()
                    .padding(vertical = 4.dp),
            ) {
                if (libraryItem != null && !fullyOnServer) {
                    MoreRow("View in Library", Icons.Outlined.VideoLibrary, { onOpenLibraryItem(libraryItem) })
                }
                loaded?.trailers?.firstOrNull()?.let { trailer ->
                    MoreRow("Watch Trailer", Icons.Outlined.PlayCircle, { context.openUrl(trailer.watchUrl) })
                }
                client?.webUrl(shown)?.let { url ->
                    MoreRow("Open in ${client.service.title}", Icons.Outlined.OpenInBrowser, { context.openUrl(url) })
                }
                loaded?.imdbId?.let { imdb ->
                    MoreRow("Open in IMDb", Icons.Outlined.Movie, { context.openUrl("https://www.imdb.com/title/$imdb") })
                }
                loaded?.homepage?.let { homepage ->
                    MoreRow("Official Website", Icons.Outlined.Language, { context.openUrl(homepage) })
                }
                MenuHairline()
                MoreRow("Share", Icons.Outlined.Share, { context.shareTitle(shown) })
            }
        }
    }
}

@Composable
private fun DiscoverTitleHero(
    title: SeerrTitle,
    details: RequestTitleDetails?,
    canManage: Boolean,
    onRequest: () -> Unit,
    onViewInLibrary: (() -> Unit)?,
) {
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    val heroHeight = (screenHeight * 0.82f).coerceAtLeast(560.dp).coerceAtMost(screenHeight)
    var expanded by remember(title.id) { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().heightIn(min = heroHeight)) {
        CachedArtwork(
            urls = listOfNotNull(details?.backdropUrl ?: details?.posterUrl ?: title.posterUrl),
            contentDescription = title.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize(),
        )
        Box(
            Modifier
                .fillMaxWidth()
                .height(heroHeight / 2)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.5f), Color.Transparent))),
        )
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0.28f to Color.Transparent,
                        0.58f to Color.Black.copy(alpha = 0.55f),
                        0.86f to Color.Black.copy(alpha = 0.94f),
                        1f to Color.Black,
                    ),
                ),
        )
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 32.dp)
                .padding(top = heroHeight * 0.3f, bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                title.name,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 34.sp,
                lineHeight = 38.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            Text(
                metadataLine(title, details),
                color = Color.White.copy(alpha = 0.92f),
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            RequestActionButton(title, canManage, onRequest, onViewInLibrary)
            title.requestedByName?.let { requester ->
                Text(
                    "Requested by $requester",
                    color = Color.White.copy(alpha = 0.7f),
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 13.sp,
                )
            }
            val overview = (details?.overview ?: title.overview)?.takeIf { it.isNotBlank() }
            if (overview != null) {
                val showMore = overview.length > 90 && !expanded
                Box(Modifier.fillMaxWidth()) {
                    Text(
                        overview,
                        color = Color.White.copy(alpha = 0.88f),
                        fontFamily = ZelefinFont,
                        fontSize = 15.sp,
                        maxLines = if (expanded) Int.MAX_VALUE else 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(end = if (showMore) 72.dp else 0.dp),
                    )
                    if (showMore) MoreCapsule(Modifier.align(Alignment.BottomEnd)) { expanded = true }
                }
            }
        }
    }
}

private fun metadataLine(title: SeerrTitle, details: RequestTitleDetails?): String =
    (listOfNotNull(if (title.kind == SeerrTitle.Kind.Movie) "Movie" else "Show", title.year?.toString()) +
        details?.genres.orEmpty().take(2)).joinToString("  ·  ")

/** Where Play sits on a library title: request, review, or where the request stands. */
@Composable
private fun RequestActionButton(title: SeerrTitle, canManage: Boolean, onRequest: () -> Unit, onViewInLibrary: (() -> Unit)?) {
    if (onViewInLibrary != null) {
        ActionCapsule("View in Library", Icons.Rounded.PlayArrow, enabled = true, onClick = onViewInLibrary)
        return
    }
    val fullyOnServer = title.availability == SeerrTitle.Availability.Available ||
        (title.kind == SeerrTitle.Kind.Movie && title.availability.isOnServer)
    val awaitsReview = canManage && title.review == SeerrTitle.Review.PendingApproval && title.requestId != null
    val canRequest = title.canRequest && title.review != SeerrTitle.Review.PendingApproval
    val approved = title.review == SeerrTitle.Review.Approved || title.availability == SeerrTitle.Availability.Processing
    val (label, icon, enabled) = when {
        fullyOnServer -> Triple("In Library", Icons.Rounded.Check, false)
        awaitsReview -> Triple("Review", Icons.Rounded.Verified, true)
        canRequest -> Triple(title.buttonTitle, Icons.Rounded.Add, true)
        else -> Triple(if (approved) "Approved" else "Requested", Icons.Rounded.Schedule, false)
    }
    ActionCapsule(label, icon, enabled, onRequest)
}

@Composable
private fun ActionCapsule(label: String, icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    val tint = if (enabled) Color.Black else Color.White.copy(alpha = 0.8f)
    Row(
        Modifier
            .widthIn(min = 175.dp)
            .height(45.dp)
            .clip(RoundedCornerShape(50))
            .background(if (enabled) Color.White else Color.White.copy(alpha = 0.18f))
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(label, color = tint, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1)
    }
}

@Composable
private fun RowHeader(title: String) {
    Text(
        title,
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

@Composable
private fun DiscoverVideoCard(video: RequestVideo, onClick: () -> Unit) {
    Box(
        Modifier
            .width(280.dp)
            .height(158.dp)
            .posterChrome()
            .clickable(onClick = onClick),
    ) {
        CachedArtwork(
            url = video.thumbnailUrl,
            contentDescription = video.name,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.08f)),
        )
        Box(
            Modifier
                .align(Alignment.Center)
                .size(44.dp)
                .background(Color.Black.copy(alpha = 0.48f), CircleShape)
                .border(0.8.dp, Color.White.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(62.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f)))),
        )
        Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 12.dp, vertical = 10.dp)) {
            Text(video.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(video.type ?: "Video", color = Color.White.copy(alpha = 0.78f), fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 11.sp, maxLines = 1)
        }
    }
}

@Composable
private fun DiscoverCastCard(person: RequestCastMember) {
    Column(Modifier.width(116.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(110.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                person.name.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 28.sp,
            )
            if (person.imageUrl != null) {
                CachedArtwork(url = person.imageUrl, contentDescription = person.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(person.name, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        Text(person.role.orEmpty(), color = Color.White.copy(alpha = 0.55f), fontFamily = ZelefinFont, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

private fun android.content.Context.openUrl(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

private fun android.content.Context.shareTitle(title: SeerrTitle) {
    val url = "https://www.themoviedb.org/${title.kind.raw}/${title.tmdbId}"
    val headline = title.year?.let { "${title.name} ($it)" } ?: title.name
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, headline)
        putExtra(Intent.EXTRA_TEXT, "$headline\n$url")
    }
    startActivity(Intent.createChooser(send, "Share"))
}

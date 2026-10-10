package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.core.AudioFormat
import app.zelefin.core.VideoRange
import app.zelefin.core.VideoResolution
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import app.zelefin.core.ArtworkDiskKey
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.SavedSession
import coil.compose.AsyncImage
import coil.request.ImageRequest

@Composable
fun PosterCard(
    item: MediaItem,
    session: SavedSession?,
    modifier: Modifier = Modifier,
    landscape: Boolean = false,
    onClick: () -> Unit,
) {
    val width = if (landscape) 280.dp else 132.dp
    Column(modifier.width(width).clickable(onClick = onClick)) {
        Box {
            CachedArtwork(
                urls = artworkCandidates(item, session, landscape),
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(if (landscape) 16f / 9f else 2f / 3f)
                    .posterChrome()
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            )
            ItemPosterMarks(item, portrait = !landscape)
            if (item.progress > 0.02 && item.progress < 0.98) {
                LinearProgressIndicator(
                    progress = { item.progress.toFloat() },
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(8.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.45f),
                )
            }
        }
        Text(
            if (landscape) item.continueWatchingTitle else item.name,
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
        val caption = if (landscape) item.continueWatchingCaption ?: item.episodeLabel else item.year?.toString()
        if (!caption.isNullOrBlank()) {
            Text(caption, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
        }
    }
}

fun artwork(item: MediaItem, session: SavedSession?, landscape: Boolean): String? =
    artworkCandidates(item, session, landscape).firstOrNull()

fun artworkCandidates(item: MediaItem, session: SavedSession?, landscape: Boolean): List<String> {
    val base = session?.serverUrl
    val token = session?.accessToken
    val urls = LinkedHashSet<String>()
    if (landscape) {
        if (base != null) {
            ArtworkUrls.thumb(base, item, token, 640)?.let { urls += it }
            ArtworkUrls.backdrop(base, item, token, 960, allowPosterFallback = false)?.let { urls += it }
            ArtworkUrls.primary(base, item, token)?.let { urls += it }
        }
        item.backdropUrl?.let { urls += it }
        item.posterUrl?.let { urls += it }
    } else {
        item.posterUrl?.let { urls += it }
        if (base != null) {
            ArtworkUrls.primary(base, item, token)?.let { urls += it }
            ArtworkUrls.thumb(base, item, token, 640)?.let { urls += it }
            ArtworkUrls.backdrop(base, item, token, 640, allowPosterFallback = false)?.let { urls += it }
        }
        item.backdropUrl?.let { urls += it }
    }
    return urls.toList()
}

/** Untagged box sets use Jellyfin’s generated 2×2, which leaves a grey cell for a child with no poster. */
fun MediaItem.usesGeneratedCollage(): Boolean =
    kind == MediaKind.Collection && primaryImageTag.isNullOrBlank() && posterUrl.isNullOrBlank()

val LocalCollectionPosters = staticCompositionLocalOf<suspend (String) -> List<MediaItem>> {
    { _ -> emptyList() }
}

@Composable
fun CollectionArtwork(
    item: MediaItem,
    session: SavedSession?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
) {
    val load = LocalCollectionPosters.current
    var members by remember(item.id) { mutableStateOf<List<MediaItem>?>(null) }
    LaunchedEffect(item.id) {
        members = load(item.id)
    }
    val posters = members.orEmpty().filter { !it.primaryImageTag.isNullOrBlank() }.take(4)
    when {
        members == null -> Box(modifier.background(Color(0xFF1C1C1E)))
        posters.isEmpty() -> CachedArtwork(
            urls = artworkCandidates(item, session, landscape = false),
            contentDescription = contentDescription,
            contentScale = ContentScale.Crop,
            modifier = modifier.background(Color(0xFF1C1C1E)),
        )
        else -> CollectionCollage(posters, session, modifier)
    }
}

@Composable
private fun CollectionCollage(posters: List<MediaItem>, session: SavedSession?, modifier: Modifier) {
    val rows = if (posters.size <= 2) listOf(posters) else listOf(posters.take(2), posters.drop(2).take(2))
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        rows.forEach { row ->
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                row.forEach { poster ->
                    CachedArtwork(
                        urls = artworkCandidates(poster, session, landscape = false),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.weight(1f).fillMaxHeight().background(Color(0xFF1C1C1E)),
                    )
                }
            }
        }
    }
}

/** Same hairline as Vellum Android `LyraArtwork`: clip, then a 0.5dp white edge at 10%. */
fun Modifier.posterChrome(corner: androidx.compose.ui.unit.Dp = 10.dp): Modifier {
    val shape = RoundedCornerShape(corner)
    return clip(shape).border(width = 0.5.dp, color = Color.White.copy(alpha = 0.10f), shape = shape)
}

fun heroArtwork(item: MediaItem, session: SavedSession?): String? =
    heroArtworkCandidates(item, session).firstOrNull()

fun heroArtworkCandidates(item: MediaItem, session: SavedSession?): List<String> {
    val urls = LinkedHashSet<String>()
    val base = session?.serverUrl
    val token = session?.accessToken
    item.backdropUrl?.let { urls += it }
    if (base != null) {
        ArtworkUrls.backdrop(base, item, token, 1600, allowPosterFallback = false)?.let { urls += it }
        ArtworkUrls.thumb(base, item, token, 960)?.let { urls += it }
        ArtworkUrls.primary(base, item, token)?.let { urls += it }
    }
    item.posterUrl?.let { urls += it }
    return urls.toList()
}

@Composable
fun CachedArtwork(
    url: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
) {
    CachedArtwork(urls = listOfNotNull(url), contentDescription = contentDescription, modifier = modifier, contentScale = contentScale)
}

@Composable
fun CachedArtwork(
    urls: List<String>,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    crossfade: Boolean = false,
) {
    val context = LocalContext.current
    val key = urls.joinToString("\n")
    var index by remember(key) { mutableIntStateOf(0) }
    val url = urls.getOrNull(index)
    if (url.isNullOrBlank()) {
        Box(modifier.background(Color(0xFF1C1C1E)))
        return
    }
    val request = remember(url, crossfade) {
        val cacheKey = ArtworkDiskKey.key(url)
        ImageRequest.Builder(context)
            .data(url)
            .diskCacheKey(cacheKey)
            .memoryCacheKey(cacheKey)
            // Drawn before the size resolves, so artwork already in memory never flashes blank on re-entry.
            .placeholderMemoryCacheKey(cacheKey)
            .crossfade(crossfade)
            .build()
    }
    AsyncImage(
        model = request,
        contentDescription = contentDescription,
        contentScale = contentScale,
        modifier = modifier,
        onError = {
            if (index < urls.lastIndex) index += 1
        },
    )
}

@Composable
fun BoxScope.ItemPosterMarks(item: MediaItem, portrait: Boolean) {
    if (portrait) {
        QualityBadgeRow(item, compact = false, Modifier.align(Alignment.BottomStart).padding(7.dp))
        posterStarScore(item.communityRating)?.let { score ->
            RatingBadge(score, Modifier.align(Alignment.TopStart).padding(6.dp))
        }
        if (item.isWatched) WatchedMark(Modifier.align(Alignment.TopEnd).padding(6.dp))
    } else {
        QualityBadgeRow(item, compact = true, Modifier.align(Alignment.TopStart).padding(6.dp))
    }
    DownloadPosterMark(item, portrait)
}

@Composable
fun WatchedMark(modifier: Modifier = Modifier, size: androidx.compose.ui.unit.Dp = 22.dp) {
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.size(size * 0.72f).background(Color.Black.copy(alpha = 0.78f), CircleShape))
        Icon(Icons.Filled.CheckCircle, contentDescription = "Watched", tint = Color.White, modifier = Modifier.size(size))
    }
}

@Composable
private fun RatingBadge(score: Double, modifier: Modifier = Modifier) {
    Row(
        modifier
            .background(Color.Black.copy(alpha = 0.78f), RoundedCornerShape(3.dp))
            .padding(horizontal = 5.dp, vertical = 2.5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Icon(Icons.Filled.Star, contentDescription = null, tint = Color(0xFFFFD60A), modifier = Modifier.size(8.dp))
        Text(String.format("%.1f", score), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.Bold, fontSize = 10.sp)
    }
}

@Composable
private fun QualityBadgeRow(item: MediaItem, compact: Boolean, modifier: Modifier = Modifier) {
    val badges = qualityBadges(item)
    if (badges.isEmpty()) return
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 5.dp)) {
        badges.forEach { title ->
            Text(
                title,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = if (compact) 10.sp else 11.sp,
                modifier = Modifier
                    .background(Color.Black.copy(alpha = 0.78f), RoundedCornerShape(3.dp))
                    .padding(horizontal = if (compact) 5.dp else 6.dp, vertical = if (compact) 2.5.dp else 3.dp),
            )
        }
    }
}

private fun posterStarScore(rating: Double?): Double? = rating?.takeIf { it > 0.0 && it <= 10.0 }

private fun qualityBadges(item: MediaItem): List<String> {
    val badges = mutableListOf<String>()
    when (item.videoResolution) {
        VideoResolution.FourK -> badges += "4K"
        VideoResolution.Hd -> badges += "HD"
        VideoResolution.Sd, VideoResolution.Unknown -> Unit
    }
    when (item.videoRange) {
        VideoRange.DolbyVision -> badges += "DV"
        VideoRange.Hdr10Plus -> badges += "HDR10+"
        VideoRange.Hdr10, VideoRange.Hlg -> badges += "HDR"
        VideoRange.Sdr -> Unit
    }
    if (item.audioFormat == AudioFormat.Atmos) badges += "Atmos"
    return badges
}

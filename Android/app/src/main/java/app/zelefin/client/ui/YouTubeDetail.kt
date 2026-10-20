package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.text.HtmlCompat
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import app.zelefin.core.TitleDetail
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit

private val YouTubeRed = Color(0xFFFF0033)
private val ChipFill = Color.White.copy(alpha = 0.12f)

enum class YouTubeVideoSort(val label: String) { Latest("Latest"), Oldest("Oldest"), Unwatched("Unwatched") }

/** Channel page body: banner, avatar header, Favorite, sort chips, and a full-width video feed. */
internal fun LazyListScope.youTubeChannelItems(
    detail: TitleDetail,
    session: SavedSession?,
    sort: YouTubeVideoSort,
    onSort: (YouTubeVideoSort) -> Unit,
    onPlay: (MediaItem) -> Unit,
    onOpenVideo: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onMore: (MediaItem, Rect) -> Unit,
) {
    val channel = detail.item
    val videos = detail.channelVideos
    item(key = "yt-header") {
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(top = 60.dp)) {
            channelBannerUrl(channel, session)?.let { banner ->
                CachedArtwork(
                    url = banner,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .fillMaxWidth()
                        .aspectRatio(6.2f)
                        .clip(RoundedCornerShape(12.dp)),
                )
                Spacer(Modifier.height(16.dp))
            }
            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                ChannelAvatar(channel, session, 80.dp)
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        channel.name,
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.Bold,
                        fontSize = 24.sp,
                        lineHeight = 28.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(videoCountLabel(videos.size), color = ZelefinMuted, fontSize = 14.sp)
                }
            }
            channel.overview?.let(::plainDescription)?.let { about ->
                var expanded by remember(channel.id) { mutableStateOf(false) }
                Row(
                    Modifier
                        .padding(horizontal = 16.dp)
                        .padding(top = 12.dp)
                        .fillMaxWidth()
                        .clickable { expanded = !expanded },
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Text(
                        about,
                        color = ZelefinMuted,
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                        maxLines = if (expanded) Int.MAX_VALUE else 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        if (expanded) "less" else "more",
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(start = 6.dp),
                    )
                }
            }
            Row(
                Modifier.padding(horizontal = 16.dp).padding(top = 16.dp).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                val resume = videos.firstOrNull { it.showsResumeProgress }
                val latest = videos.firstOrNull()
                val target = resume ?: latest
                if (target != null) {
                    YouTubePill(
                        label = if (resume != null) "Resume" else "Play latest",
                        icon = Icons.Filled.PlayArrow,
                        filled = true,
                        modifier = Modifier.weight(1f),
                    ) { onPlay(target) }
                }
                YouTubePill(
                    label = if (channel.isFavorite) "Favorited" else "Favorite",
                    icon = if (channel.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    filled = !channel.isFavorite,
                    red = !channel.isFavorite,
                    modifier = Modifier.weight(1f),
                ) { onToggleFavorite(channel) }
            }
            Row(
                Modifier
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(top = 20.dp, bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                YouTubeVideoSort.entries.forEach { option ->
                    SortChip(option.label, selected = option == sort) { onSort(option) }
                }
            }
        }
    }
    val sorted = when (sort) {
        YouTubeVideoSort.Latest -> videos
        YouTubeVideoSort.Oldest -> videos.reversed()
        YouTubeVideoSort.Unwatched -> videos.filter { !it.isWatched }
    }
    if (sorted.isEmpty()) {
        item(key = "yt-empty") {
            Text(
                if (sort == YouTubeVideoSort.Unwatched) "You’ve watched every video." else "No videos yet.",
                color = ZelefinMuted,
                fontSize = 15.sp,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 32.dp),
            )
        }
    }
    items(sorted, key = { "yt-video-${it.id}" }) { video ->
        YouTubeVideoRow(video, channel, session, onOpen = { onOpenVideo(video) }, onMore = { onMore(video, it) })
    }
}

/** Video page body: 16:9 thumbnail with play, title, channel row, actions, description, and more from the channel. */
internal fun LazyListScope.youTubeVideoItems(
    detail: TitleDetail,
    session: SavedSession?,
    onPlay: (MediaItem) -> Unit,
    onOpenVideo: (MediaItem) -> Unit,
    onOpenChannel: (MediaItem) -> Unit,
    onToggleWatched: (MediaItem) -> Unit,
    onToggleFavorite: (MediaItem) -> Unit,
    onMore: (MediaItem, Rect) -> Unit,
) {
    val video = detail.item
    val channel = detail.channel
    item(key = "yt-player") {
        Box(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(top = 60.dp)
                .aspectRatio(16f / 9f)
                .background(Color(0xFF0F0F0F))
                .clickable { onPlay(video) },
        ) {
            CachedArtwork(
                urls = videoThumbnailUrls(video, session),
                contentDescription = video.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                Modifier
                    .align(Alignment.Center)
                    .size(68.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = "Play", tint = Color.White, modifier = Modifier.size(40.dp))
            }
            if (video.showsResumeProgress) VideoProgressBar(video.progress, Modifier.align(Alignment.BottomStart))
        }
    }
    item(key = "yt-title") {
        var expanded by remember(video.id) { mutableStateOf(false) }
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 14.dp)) {
            Text(
                video.name,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 19.sp,
                lineHeight = 24.sp,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                listOfNotNull(publishedAgo(video.premiereDate), video.runtimeLabel, "Watched".takeIf { video.isWatched }).joinToString(" · "),
                color = ZelefinMuted,
                fontSize = 13.sp,
            )
            if (channel != null) {
                Row(
                    Modifier
                        .padding(top = 16.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { onOpenChannel(channel) }
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ChannelAvatar(channel, session, 40.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(channel.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(videoCountLabel(detail.channelVideos.size), color = ZelefinMuted, fontSize = 12.sp)
                    }
                    YouTubePill(
                        label = if (channel.isFavorite) "Favorited" else "Favorite",
                        icon = if (channel.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        filled = !channel.isFavorite,
                        red = !channel.isFavorite,
                        compact = true,
                    ) { onToggleFavorite(channel) }
                }
            }
            Row(
                Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                YouTubePill(
                    label = if (video.showsResumeProgress) "Resume" else "Play",
                    icon = Icons.Filled.PlayArrow,
                    filled = true,
                    compact = true,
                ) { onPlay(video) }
                YouTubePill(
                    label = if (video.isWatched) "Watched" else "Mark watched",
                    icon = if (video.isWatched) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
                    filled = false,
                    compact = true,
                ) { onToggleWatched(video) }
                YouTubePill(
                    label = if (video.isFavorite) "Favorited" else "Favorite",
                    icon = if (video.isFavorite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    filled = false,
                    compact = true,
                ) { onToggleFavorite(video) }
            }
            video.overview?.let(::plainDescription)?.let { about ->
                Column(
                    Modifier
                        .padding(top = 14.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(ChipFill)
                        .clickable { expanded = !expanded }
                        .padding(12.dp),
                ) {
                    Text(
                        about,
                        color = Color.White.copy(alpha = 0.88f),
                        fontSize = 14.sp,
                        lineHeight = 19.sp,
                        maxLines = if (expanded) Int.MAX_VALUE else 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        if (expanded) "Show less" else "more",
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            }
        }
    }
    val others = detail.channelVideos.filter { it.id != video.id }
    if (others.isNotEmpty() && channel != null) {
        item(key = "yt-more-title") {
            Text(
                "More from ${channel.name}",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 18.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 16.dp).padding(top = 24.dp, bottom = 8.dp),
            )
        }
        items(others, key = { "yt-video-${it.id}" }) { other ->
            YouTubeVideoRow(other, channel, session, onOpen = { onOpenVideo(other) }, onMore = { onMore(other, it) })
        }
    }
}

@Composable
private fun YouTubeVideoRow(
    video: MediaItem,
    channel: MediaItem,
    session: SavedSession?,
    onOpen: () -> Unit,
    onMore: (Rect) -> Unit,
) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(bottom = 20.dp)) {
        Box(
            Modifier
                .padding(horizontal = 12.dp)
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF1C1C1E)),
        ) {
            CachedArtwork(
                urls = videoThumbnailUrls(video, session),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            videoLengthLabel(video.runtime)?.let { length ->
                Text(
                    length,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color.Black.copy(alpha = 0.8f))
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                )
            }
            when {
                video.showsResumeProgress -> VideoProgressBar(video.progress, Modifier.align(Alignment.BottomStart))
                video.isWatched -> VideoProgressBar(1.0, Modifier.align(Alignment.BottomStart))
            }
        }
        Row(Modifier.padding(start = 12.dp, top = 12.dp), verticalAlignment = Alignment.Top) {
            ChannelAvatar(channel, session, 36.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    video.name,
                    color = Color.White,
                    fontWeight = FontWeight.Medium,
                    fontSize = 15.sp,
                    lineHeight = 20.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    listOfNotNull(channel.name, publishedAgo(video.premiereDate)).joinToString(" · "),
                    color = ZelefinMuted,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            var anchor by remember { mutableStateOf(Rect.Zero) }
            Box(
                Modifier
                    .size(44.dp)
                    .onGloballyPositioned { anchor = it.boundsInRoot() }
                    .clip(CircleShape)
                    .clickable { onMore(anchor) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.MoreVert, contentDescription = "More", tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
private fun ChannelAvatar(channel: MediaItem, session: SavedSession?, size: androidx.compose.ui.unit.Dp) {
    val base = session?.serverUrl
    val url = base?.let { ArtworkUrls.primary(it, channel, session.accessToken, maxHeight = 240) }
    Box(Modifier.size(size).clip(CircleShape).background(Color(0xFF2A2A2E)), contentAlignment = Alignment.Center) {
        if (url != null) {
            CachedArtwork(url = url, contentDescription = channel.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Text(channel.name.take(1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.4f).sp)
        }
    }
}

@Composable
private fun YouTubePill(
    label: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    filled: Boolean,
    compact: Boolean = false,
    red: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier
            .height(if (compact) 36.dp else 42.dp)
            .clip(CircleShape)
            .background(
                when {
                    red -> YouTubeRed
                    filled -> Color.White
                    else -> ChipFill
                },
            )
            .clickable(onClick = onClick)
            .padding(horizontal = if (compact) 14.dp else 18.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val tint = if (filled && !red) Color.Black else Color.White
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(if (compact) 18.dp else 22.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(label, color = tint, fontWeight = FontWeight.SemiBold, fontSize = if (compact) 13.sp else 15.sp, maxLines = 1)
    }
}

@Composable
private fun SortChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(34.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) Color.White else ChipFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = if (selected) Color.Black else Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
    }
}

@Composable
private fun VideoProgressBar(progress: Double, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.35f))) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(progress.toFloat().coerceIn(0f, 1f)).background(YouTubeRed))
    }
}

private fun channelBannerUrl(channel: MediaItem, session: SavedSession?): String? {
    val base = session?.serverUrl ?: return null
    val tag = channel.bannerImageTag ?: return null
    return ArtworkUrls.image(base, channel.id, "Banner", tag, session.accessToken, maxWidth = 1600, format = "jpg")
}

private fun videoThumbnailUrls(video: MediaItem, session: SavedSession?): List<String> {
    val base = session?.serverUrl ?: return emptyList()
    val token = session.accessToken
    return listOfNotNull(
        ArtworkUrls.primary(base, video, token, maxHeight = 720),
        ArtworkUrls.thumb(base, video, token, 1280),
    )
}

/** TubeArchivist descriptions arrive as HTML with `<br>` line breaks. */
private fun plainDescription(html: String): String? =
    HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_COMPACT).toString().trim().takeIf { it.isNotEmpty() }

private fun videoCountLabel(count: Int): String = if (count == 1) "1 video" else "$count videos"

/** `12:34` or `1:02:03`, like the YouTube length badge. */
internal fun videoLengthLabel(seconds: Double?): String? {
    val total = seconds?.toLong()?.takeIf { it > 0 } ?: return null
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/** YouTube-style age: “3 days ago”, “2 weeks ago”, “1 year ago”. */
internal fun publishedAgo(iso: String?, today: LocalDate = LocalDate.now()): String? {
    val raw = iso?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val date = runCatching { LocalDateTime.parse(raw).toLocalDate() }
        .recoverCatching { OffsetDateTime.parse(raw).toLocalDate() }
        .recoverCatching { LocalDate.parse(raw.take(10)) }
        .getOrNull() ?: return null
    val days = ChronoUnit.DAYS.between(date, today)
    fun unit(value: Long, name: String) = "$value $name${if (value == 1L) "" else "s"} ago"
    return when {
        days < 1 -> "Today"
        days < 7 -> unit(days, "day")
        days < 30 -> unit(days / 7, "week")
        days < 365 -> unit(ChronoUnit.MONTHS.between(date, today).coerceAtLeast(1), "month")
        else -> unit(ChronoUnit.YEARS.between(date, today).coerceAtLeast(1), "year")
    }
}

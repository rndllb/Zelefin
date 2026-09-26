package app.zelefin.client.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.StarHalf
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarOutline
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.EnhancedExtras
import app.zelefin.client.plugins.JellyfinEnhancedAwards
import app.zelefin.client.plugins.JellyfinEnhancedReview
import app.zelefin.client.plugins.JellyfinEnhancedReviewPayload
import app.zelefin.client.plugins.TmdbUserReview

private val ExtrasMuted = Color.White.copy(alpha = 0.55f)
private val ExtrasFaint = Color.White.copy(alpha = 0.48f)
private val Destructive = Color(0xFFFF453A)

/** Jellyfin Enhanced awards, TMDB reviews, and server reviews on the title page. */
@Composable
internal fun TitleEnhancedExtras(
    extras: EnhancedExtras,
    isAdministrator: Boolean,
    isOwn: (JellyfinEnhancedReview) -> Boolean,
    onWrite: () -> Unit,
    onDelete: (JellyfinEnhancedReview) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        extras.awards?.let { AwardsSection(it) }
        if (extras.tmdbReviews.isNotEmpty()) TmdbReviewsSection(extras.tmdbReviews)
        ReviewsSection(extras.reviews, isAdministrator, isOwn, onWrite, onDelete)
    }
}

@Composable
private fun CollapsibleHeader(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    summary: String,
    expanded: Boolean,
    trailing: @Composable () -> Unit = {},
    onToggle: () -> Unit,
) {
    val turn by animateFloatAsState(if (expanded) 180f else 0f, label = "extras-chevron")
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle)
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp)
            Text(summary, color = ExtrasMuted, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
        }
        trailing()
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = if (expanded) "Collapse" else "Expand",
            tint = Color.White.copy(alpha = 0.45f),
            modifier = Modifier.size(20.dp).rotate(turn),
        )
    }
}

@Composable
private fun AwardsSection(awards: JellyfinEnhancedAwards) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        CollapsibleHeader(Icons.Filled.EmojiEvents, "Awards", awards.summary, expanded) { expanded = !expanded }
        if (expanded) {
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                awards.awards.forEach { award ->
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(award.name, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp, modifier = Modifier.weight(1f))
                            Spacer(Modifier.width(8.dp))
                            Text(
                                if (award.isWin) "Won" else "Nominated",
                                color = ExtrasMuted,
                                fontFamily = ZelefinFont,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 12.sp,
                            )
                        }
                        val line = listOfNotNull(award.year?.toString(), award.detailLine).joinToString("  ")
                        if (line.isNotEmpty()) {
                            Text(line, color = ExtrasFaint, fontFamily = ZelefinFont, fontSize = 13.sp, maxLines = 2)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TmdbReviewsSection(reviews: List<TmdbUserReview>) {
    var expanded by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf(emptySet<String>()) }
    val summary = if (reviews.size == 1) "1 review" else "${reviews.size} reviews"
    Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        CollapsibleHeader(
            Icons.Filled.FormatQuote,
            "TMDB Reviews",
            summary,
            expanded,
            trailing = { TmdbUserReview.averageStars(reviews)?.let { StarRating(it, 12.dp) } },
        ) {
            expanded = !expanded
            if (!expanded) open = emptySet()
        }
        if (expanded) {
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                reviews.forEach { review ->
                    val isOpen = review.id in open
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clickable { open = if (isOpen) open - review.id else open + review.id },
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(review.author, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, modifier = Modifier.weight(1f))
                            review.starsOutOfFive?.let { StarRating(it, 11.dp) }
                        }
                        Text(
                            review.content,
                            color = Color.White.copy(alpha = 0.78f),
                            fontFamily = ZelefinFont,
                            fontSize = 13.sp,
                            maxLines = if (isOpen) Int.MAX_VALUE else 2,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ReviewsSection(
    reviews: List<JellyfinEnhancedReview>,
    isAdministrator: Boolean,
    isOwn: (JellyfinEnhancedReview) -> Boolean,
    onWrite: () -> Unit,
    onDelete: (JellyfinEnhancedReview) -> Unit,
) {
    val mine = reviews.firstOrNull(isOwn)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            "Reviews",
            color = Color.White,
            fontFamily = ZelefinFont,
            fontWeight = FontWeight.SemiBold,
            fontSize = 20.sp,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val average = JellyfinEnhancedReview.averageRating(reviews)
            when {
                average != null -> {
                    StarRating(average, 14.dp)
                    Text(String.format("%.1f", average), color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Text(if (reviews.size == 1) "1 rating" else "${reviews.size} ratings", color = ExtrasFaint, fontFamily = ZelefinFont, fontSize = 13.sp)
                }
                reviews.isNotEmpty() ->
                    Text(if (reviews.size == 1) "1 review" else "${reviews.size} reviews", color = ExtrasFaint, fontFamily = ZelefinFont, fontSize = 13.sp)
                else -> Text("No reviews yet", color = ExtrasFaint, fontFamily = ZelefinFont, fontSize = 13.sp)
            }
            Spacer(Modifier.weight(1f))
            Text(
                if (mine == null) "Write a Review" else "Edit Your Review",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 13.sp,
                modifier = Modifier.clip(androidx.compose.foundation.shape.RoundedCornerShape(8.dp)).clickable(onClick = onWrite).padding(4.dp),
            )
        }
        if (reviews.isNotEmpty()) {
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                reviews.forEach { review ->
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(review.userName, color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, modifier = Modifier.weight(1f))
                            review.rating?.let { StarRating(it, 11.dp) }
                        }
                        if (review.hasText) {
                            Text(review.content, color = Color.White.copy(alpha = 0.86f), fontFamily = ZelefinFont, fontSize = 16.sp)
                        }
                        if (isOwn(review) || isAdministrator) {
                            Text(
                                "Delete",
                                color = Destructive,
                                fontFamily = ZelefinFont,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 13.sp,
                                modifier = Modifier.clickable { onDelete(review) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StarRating(rating: Double, size: Dp) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (star in 1..5) {
            val filled = rating + 0.001
            val icon = when {
                filled >= star -> Icons.Filled.Star
                filled >= star - 0.5 -> Icons.AutoMirrored.Filled.StarHalf
                else -> Icons.Outlined.StarOutline
            }
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(size + 2.dp))
        }
    }
}

/** Write or edit this account's review. Tapping the same star again drops half a star. */
@Composable
internal fun TitleReviewEditor(
    existing: JellyfinEnhancedReview?,
    busy: Boolean,
    error: String?,
    onSave: (String, Double?) -> Unit,
    onDelete: (() -> Unit)?,
    onClose: () -> Unit,
) {
    var content by remember(existing) { mutableStateOf(existing?.content.orEmpty()) }
    var rating by remember(existing) { mutableStateOf(existing?.rating) }
    val valid = JellyfinEnhancedReviewPayload.isValid(content, rating)
    Column(Modifier.fillMaxSize()) {
        SheetBar(
            title = if (existing == null) "Write a Review" else "Edit Review",
            leading = "Cancel",
            onLeading = onClose,
            trailing = "Save",
            trailingEnabled = valid && !busy,
            onTrailing = { onSave(content, rating) },
        )
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            EditorLabel("Rating")
            Row(
                Modifier.fillMaxWidth().clip(SheetGroupShape).background(SheetGroupFill).padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for (star in 1..5) {
                    val current = rating
                    val icon = when {
                        current == null -> Icons.Outlined.StarOutline
                        current + 0.001 >= star -> Icons.Filled.Star
                        current + 0.001 >= star - 0.5 -> Icons.AutoMirrored.Filled.StarHalf
                        else -> Icons.Outlined.StarOutline
                    }
                    Icon(
                        icon,
                        contentDescription = "$star stars",
                        tint = Color.White,
                        modifier = Modifier
                            .size(28.dp)
                            .clickable {
                                val value = star.toDouble()
                                rating = if (rating == value && star > 1) value - 0.5 else value
                            },
                    )
                }
                Spacer(Modifier.weight(1f))
                rating?.let { value ->
                    Text(
                        if (value % 1.0 == 0.0) value.toInt().toString() else String.format("%.1f", value),
                        color = ExtrasMuted,
                        fontFamily = ZelefinFont,
                        fontSize = 16.sp,
                    )
                }
            }
            EditorLabel("Review")
            val style = TextStyle(color = Color.White, fontFamily = ZelefinFont, fontSize = 17.sp)
            BasicTextField(
                value = content,
                onValueChange = { content = it },
                textStyle = style,
                cursorBrush = SolidColor(ZelefinCyan),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(SheetGroupShape)
                    .background(SheetGroupFill)
                    .padding(16.dp)
                    .defaultMinSize(minHeight = 110.dp),
                decorationBox = { inner ->
                    Box {
                        if (content.isEmpty()) Text("What did you think?", style = style, color = ExtrasFaint)
                        inner()
                    }
                },
            )
            if (existing != null && onDelete != null) {
                Box(
                    Modifier
                        .padding(top = 18.dp)
                        .fillMaxWidth()
                        .clip(SheetGroupShape)
                        .background(SheetGroupFill)
                        .clickable(enabled = !busy, onClick = onDelete)
                        .padding(16.dp),
                ) {
                    Text("Delete Review", color = Destructive, fontFamily = ZelefinFont, fontSize = 17.sp)
                }
            }
            error?.let {
                Text(it, color = Destructive, fontFamily = ZelefinFont, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

@Composable
private fun EditorLabel(text: String) {
    Text(
        text,
        color = ExtrasMuted,
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(start = 8.dp, top = 14.dp),
    )
}

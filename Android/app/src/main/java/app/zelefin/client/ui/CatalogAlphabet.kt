package app.zelefin.client.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.core.MediaItem
import java.text.Normalizer
import kotlinx.coroutines.launch

fun catalogSectionLetter(name: String): Char {
    val first = name.trim().firstOrNull() ?: return '#'
    if (first.isDigit()) return '#'
    if (!first.isLetter()) return '#'
    val folded = Normalizer.normalize(first.toString(), Normalizer.Form.NFD)
        .replace("\\p{M}+".toRegex(), "")
        .uppercase()
        .firstOrNull() ?: return '#'
    return if (folded in 'A'..'Z') folded else '#'
}

fun catalogLetterIndex(items: List<MediaItem>): Map<Char, Int> {
    val index = linkedMapOf<Char, Int>()
    items.forEachIndexed { position, item ->
        index.putIfAbsent(catalogSectionLetter(item.name), position)
    }
    return index
}

fun catalogScrubberLetters(items: List<MediaItem>): List<Char> {
    val present = items.mapTo(mutableSetOf()) { catalogSectionLetter(it.name) }
    return ('A'..'Z').filter { it in present } + if ('#' in present) listOf('#') else emptyList()
}

@Composable
fun CatalogAlphabetRail(
    items: List<MediaItem>,
    gridState: LazyGridState,
    modifier: Modifier = Modifier,
) {
    val letters = remember(items) { catalogScrubberLetters(items) }
    val index = remember(items) { catalogLetterIndex(items) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    var selected by remember { mutableStateOf<Char?>(null) }
    var lastReported by remember { mutableStateOf<Char?>(null) }
    var stackHeight by remember { mutableStateOf(0) }
    if (letters.isEmpty()) return

    // Match iOS: a wide drag target, but the visible letters hug the trailing edge
    // (their column center sits ~8dp in) instead of floating in the middle of the lane.
    val hitWidth = 40.dp
    val letterWidth = 18.dp
    val trailingCenter = 8.dp

    fun selectAt(y: Float) {
        if (stackHeight <= 0 || letters.isEmpty()) return
        val slot = stackHeight.toFloat() / letters.size
        val letter = letters[(y / slot).toInt().coerceIn(0, letters.lastIndex)]
        if (letter == lastReported) return
        lastReported = letter
        selected = letter
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        val target = index[letter] ?: return
        scope.launch { gridState.scrollToItem(target) }
    }

    Box(
        modifier
            .fillMaxHeight()
            .width(hitWidth)
            // Shove the lane toward the edge so the centered letters land ~8dp from it;
            // the extra hit width spills harmlessly off-screen, like iOS's overshoot.
            .offset(x = hitWidth / 2 - trailingCenter),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .width(hitWidth)
                .onSizeChanged { stackHeight = it.height }
                .pointerInput(letters, items) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        selectAt(down.position.y)
                        drag(down.id) { change ->
                            change.consume()
                            selectAt(change.position.y)
                        }
                        lastReported = null
                        selected = null
                    }
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            letters.forEach { letter ->
                val active = selected == letter
                Text(
                    letter.toString(),
                    color = if (active) ZelefinCyan else ZelefinCyan.copy(alpha = 0.88f),
                    fontFamily = ZelefinFont,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold,
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.width(letterWidth).height(14.dp),
                )
            }
        }
    }
}

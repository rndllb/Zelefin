package app.zelefin.client.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import app.zelefin.client.R

/** Solid white genre mark, in the style of the genre icon sheet. */
@Composable
fun GenreIcon(title: String, side: Dp, modifier: Modifier = Modifier) {
    val kind = remember(title) { GenreIconKind.matching(title) }
    val asset = kind.asset
    if (asset != null) {
        Image(
            painter = painterResource(asset),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            colorFilter = ColorFilter.tint(Color.White),
            modifier = modifier.size(side),
        )
    } else {
        val glyph = remember(kind) { kind.glyph() }
        Canvas(modifier.size(side)) {
            val factor = minOf(size.width, size.height) / 24f
            scale(factor, pivot = Offset.Zero) { drawPath(glyph, Color.White) }
        }
    }
}

private enum class GenreIconKind(@DrawableRes val asset: Int? = null) {
    Action(R.drawable.genre_party_popper),
    Adventure(R.drawable.genre_zipline),
    Animation(R.drawable.genre_animation),
    Anime(R.drawable.genre_anime),
    Comedy(R.drawable.genre_comedy),
    Crime(R.drawable.genre_crime),
    Documentary(R.drawable.genre_document_text),
    Drama(R.drawable.genre_drama),
    Family(R.drawable.genre_people),
    Fantasy(R.drawable.genre_magic),
    Food(R.drawable.genre_serving_dome),
    GameShow(R.drawable.genre_gameboy),
    Historical(R.drawable.genre_edit),
    Holiday,
    Horror(R.drawable.genre_ghost),
    Music(R.drawable.genre_music_square),
    Mystery(R.drawable.genre_mystery),
    Nature,
    News,
    Reality(R.drawable.genre_video),
    Romance(R.drawable.genre_lovely),
    ScienceFiction(R.drawable.genre_telescope),
    SciFiFantasy(R.drawable.genre_moon),
    Sport,
    Superhero,
    Supernatural,
    Suspense,
    Thriller,
    War,
    Western,
    Children(R.drawable.genre_kids),
    Biography,
    MiniSeries(R.drawable.genre_mini_series),
    Soap(R.drawable.genre_soap),
    Generic;

    fun glyph(): Path = Path().apply {
        fillType = PathFillType.EvenOdd
        when (this@GenreIconKind) {
            Action -> {
                roundRect(1.5f, 8.5f, 13f, 5.2f, 1.2f)
                roundRect(14.4f, 9.8f, 8f, 2.2f, 0.6f)
                roundRect(4.2f, 13.2f, 4.2f, 7f, 1f)
            }
            Adventure -> {
                roundRect(5f, 2f, 14f, 18f, 1.2f)
                polygon(8f to 6f, 12f to 9f, 10f to 13f, 15f to 16f, 15f to 16.8f, 9f to 13.4f, 11.2f to 9.2f, 7.2f to 6.6f)
            }
            Animation, GameShow, MiniSeries, Soap, Generic -> {
                oval(3f, 3f, 18f, 18f)
                oval(7.2f, 7.2f, 9.6f, 9.6f)
                oval(10.2f, 10.2f, 3.6f, 3.6f)
            }
            Anime -> polygon(12f to 2f, 14.2f to 9f, 22f to 12f, 14.2f to 15f, 12f to 22f, 9.8f to 15f, 2f to 12f, 9.8f to 9f)
            Comedy -> mask(smile = true)
            Drama -> mask(smile = false)
            Crime -> {
                oval(1.5f, 7.5f, 8f, 8f)
                oval(3.7f, 9.7f, 3.6f, 3.6f)
                oval(14.5f, 7.5f, 8f, 8f)
                oval(16.7f, 9.7f, 3.6f, 3.6f)
                roundRect(9.2f, 10.2f, 5.6f, 2.6f, 0.6f)
            }
            Documentary -> {
                roundRect(4f, 3f, 16f, 18f, 1.4f)
                rect(4f, 7.2f, 16f, 2.2f)
                rect(7f, 12f, 10f, 1.6f)
                rect(7f, 15.4f, 7f, 1.6f)
            }
            Family, Children -> {
                oval(2f, 4f, 6f, 6f)
                oval(9f, 3f, 6f, 6f)
                oval(16f, 4.4f, 5.2f, 5.2f)
                roundRect(1f, 12f, 8f, 9f, 3f)
                roundRect(8f, 11f, 8f, 10f, 3f)
                roundRect(15.2f, 12.2f, 7f, 8.6f, 3f)
            }
            Fantasy, Historical -> {
                rect(3f, 12f, 18f, 9f)
                rect(2f, 8f, 4f, 13f)
                rect(10f, 6f, 4f, 15f)
                rect(18f, 8f, 4f, 13f)
                polygon(2f to 8f, 4f to 3f, 6f to 8f)
                polygon(10f to 6f, 12f to 1.5f, 14f to 6f)
                polygon(18f to 8f, 20f to 3f, 22f to 8f)
            }
            Food -> {
                roundRect(4f, 4.2f, 2.2f, 17.5f, 1f)
                roundRect(8.2f, 4.2f, 2.2f, 17.5f, 1f)
                roundRect(12.4f, 4.2f, 2.2f, 17.5f, 1f)
                roundRect(3.2f, 2f, 12.2f, 2.2f, 1f)
            }
            Holiday -> {
                roundRect(3f, 8f, 18f, 13f, 1.5f)
                rect(10.6f, 8f, 2.8f, 13f)
                rect(3f, 12.4f, 18f, 2.8f)
                oval(8f, 3f, 4f, 4f)
                oval(12f, 3f, 4f, 4f)
            }
            Horror, Supernatural -> {
                moveTo(4f, 12f)
                quadraticTo(4f, 3f, 12f, 3f)
                quadraticTo(20f, 3f, 20f, 12f)
                lineTo(20f, 20f)
                lineTo(16.5f, 16.5f)
                lineTo(13.5f, 21f)
                lineTo(10.5f, 16.5f)
                lineTo(7.5f, 21f)
                lineTo(4f, 16.5f)
                close()
            }
            Music -> {
                oval(3f, 14f, 6f, 5f)
                oval(13f, 12f, 6f, 5f)
                rect(8f, 4f, 1.8f, 12f)
                rect(18f, 3f, 1.8f, 11f)
                roundRect(8f, 3f, 12f, 2.4f, 0.6f)
            }
            Mystery -> {
                oval(2f, 10f, 14f, 8f)
                roundRect(4f, 3f, 12f, 4f, 1f)
                rect(15f, 6f, 7f, 1.6f)
                oval(15f, 15f, 6.5f, 6.5f)
                oval(16.6f, 16.6f, 3.3f, 3.3f)
            }
            Nature -> {
                oval(8f, 2f, 8f, 8f)
                oval(2f, 12f, 9f, 7f)
                oval(8f, 10f, 10f, 9f)
                oval(14f, 13f, 8f, 6f)
            }
            News -> {
                roundRect(3f, 4f, 18f, 16f, 1.2f)
                rect(6f, 7f, 12f, 2f)
                rect(6f, 11f, 12f, 1.6f)
                rect(6f, 14.4f, 8f, 1.6f)
            }
            Reality -> {
                roundRect(2f, 7f, 13f, 10f, 1.5f)
                polygon(15f to 9f, 22f to 6f, 22f to 18f, 15f to 15f)
            }
            Romance -> {
                moveTo(12f, 20.5f)
                quadraticTo(2f, 16f, 2f, 9f)
                quadraticTo(2f, 4f, 7.5f, 4f)
                quadraticTo(10f, 4f, 12f, 8f)
                quadraticTo(14f, 4f, 16.5f, 4f)
                quadraticTo(22f, 4f, 22f, 9f)
                quadraticTo(22f, 16f, 12f, 20.5f)
                close()
            }
            ScienceFiction, SciFiFantasy -> {
                oval(4f, 9f, 16f, 6f)
                oval(9f, 4f, 6f, 6f)
                rect(11.2f, 15f, 1.6f, 4f)
                oval(6f, 18f, 3f, 2f)
                oval(15f, 18f, 3f, 2f)
            }
            Sport -> oval(3f, 3f, 18f, 18f)
            Superhero, War -> {
                moveTo(12f, 2f)
                lineTo(21f, 6f)
                lineTo(21f, 12f)
                quadraticTo(21f, 18f, 12f, 22f)
                quadraticTo(3f, 18f, 3f, 12f)
                lineTo(3f, 6f)
                close()
            }
            Suspense, Biography -> {
                oval(6f, 2f, 12f, 12f)
                roundRect(3f, 15f, 18f, 7f, 3f)
                oval(9.5f, 6f, 5f, 5f)
            }
            Thriller -> {
                polygon(14f to 2f, 18f to 2f, 11f to 16f, 7f to 16f)
                roundRect(6f, 16f, 6f, 5f, 1f)
            }
            Western -> polygon(
                7f to 2f, 16f to 2f, 16f to 8f, 20f to 12f, 16f to 16f,
                14f to 22f, 8f to 22f, 7f to 14f, 4f to 12f, 7f to 8f,
            )
        }
    }

    companion object {
        private val pairs = listOf(
            "sci-fi & fantasy" to SciFiFantasy,
            "sci-fi and fantasy" to SciFiFantasy,
            "scifi & fantasy" to SciFiFantasy,
            "scifi and fantasy" to SciFiFantasy,
            "science fiction & fantasy" to SciFiFantasy,
            "science fiction and fantasy" to SciFiFantasy,
            "science fiction" to ScienceFiction,
            "sci-fi" to ScienceFiction,
            "scifi" to ScienceFiction,
            "historical" to Historical,
            "history" to Historical,
            "young adult" to Drama,
            "superhero" to Superhero,
            "supernatural" to Supernatural,
            "suspense" to Suspense,
            "animation" to Animation,
            "anime" to Anime,
            "adventure" to Adventure,
            "action" to Action,
            "biography" to Biography,
            "children" to Children,
            "kids" to Children,
            "kid" to Children,
            "comedy" to Comedy,
            "crime" to Crime,
            "documentary" to Documentary,
            "drama" to Drama,
            "family" to Family,
            "fantasy" to Fantasy,
            "game-show" to GameShow,
            "game show" to GameShow,
            "food" to Food,
            "holiday" to Holiday,
            "horror" to Horror,
            "musical" to Music,
            "music" to Music,
            "mini-series" to MiniSeries,
            "mini series" to MiniSeries,
            "miniseries" to MiniSeries,
            "mystery" to Mystery,
            "nature" to Nature,
            "news" to News,
            "reality" to Reality,
            "romance" to Romance,
            "soap" to Soap,
            "sport" to Sport,
            "thriller" to Thriller,
            "western" to Western,
            "war" to War,
        )

        fun matching(title: String): GenreIconKind {
            val key = title.lowercase()
            return pairs.firstOrNull { key.contains(it.first) }?.second ?: Generic
        }
    }
}

private fun Path.rect(x: Float, y: Float, w: Float, h: Float) = addRect(Rect(x, y, x + w, y + h))

private fun Path.oval(x: Float, y: Float, w: Float, h: Float) = addOval(Rect(x, y, x + w, y + h))

private fun Path.roundRect(x: Float, y: Float, w: Float, h: Float, r: Float) =
    addRoundRect(RoundRect(x, y, x + w, y + h, CornerRadius(r, r)))

private fun Path.polygon(vararg points: Pair<Float, Float>) {
    moveTo(points[0].first, points[0].second)
    points.drop(1).forEach { (x, y) -> lineTo(x, y) }
    close()
}

private fun Path.mask(smile: Boolean) {
    oval(3f, 2f, 18f, 20f)
    oval(7.2f, 8f, 2.4f, 3f)
    oval(14.4f, 8f, 2.4f, 3f)
    if (smile) {
        moveTo(8f, 14f)
        quadraticTo(12f, 18f, 16f, 14f)
        quadraticTo(12f, 15f, 8f, 14f)
    } else {
        moveTo(8f, 16f)
        quadraticTo(12f, 12f, 16f, 16f)
        quadraticTo(12f, 15f, 8f, 16f)
    }
}

package app.zelefin.client.ui

import android.content.Context
import androidx.annotation.DrawableRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.client.R
import app.zelefin.client.looksLikeRecordings

/**
 * Mirrors iOS `LibraryIcon`: the dock and Interface settings icon for a library. YouTube and recordings
 * libraries get their own, and a library with "Anime" in its name shows the anime icon or one of the anime characters.
 */
object LibraryIcons {
    data class Choice(val key: String, val title: String, @param:DrawableRes val res: Int)

    /** PlainIcon's Anime characters pack (CC BY 4.0). Keys match the iOS asset names. */
    val animeChoices = listOf(
        Choice("AnimeBoySmiling", "Boy Smiling", R.drawable.anime_boy_smiling),
        Choice("AnimeBoyWithBigEyes", "Boy with Big Eyes", R.drawable.anime_boy_with_big_eyes),
        Choice("AnimeBoyWithHeadphones", "Boy with Headphones", R.drawable.anime_boy_with_headphones),
        Choice("AnimeBoyWithHood", "Boy with Hood", R.drawable.anime_boy_with_hood),
        Choice("AnimeBoyWithShirt", "Boy with Shirt", R.drawable.anime_boy_with_shirt),
        Choice("AnimeBoyWithShirtAndBigEyes", "Boy with Shirt and Big Eyes", R.drawable.anime_boy_with_shirt_and_big_eyes),
        Choice("AnimeBoyWithShortTrousers", "Boy with Short Trousers", R.drawable.anime_boy_with_short_trousers),
        Choice("AnimeBoyWithSummerClothes", "Boy with Summer Clothes", R.drawable.anime_boy_with_summer_clothes),
        Choice("AnimeBoyWithTShirt", "Boy with T-Shirt", R.drawable.anime_boy_with_t_shirt),
        Choice("AnimeBoyWithTShirt2", "Boy with T-Shirt 2", R.drawable.anime_boy_with_t_shirt2),
        Choice("AnimeBoyWithTie", "Boy with Tie", R.drawable.anime_boy_with_tie),
        Choice("AnimeBoyWithTie2", "Boy with Tie 2", R.drawable.anime_boy_with_tie2),
        Choice("AnimeBoyWithWildHair", "Boy with Wild Hair", R.drawable.anime_boy_with_wild_hair),
        Choice("AnimeCharacter", "Character", R.drawable.anime_character),
        Choice("AnimeCharacterWithHairUp", "Character with Hair Up", R.drawable.anime_character_with_hair_up),
        Choice("AnimeFeminineCharacterSmiling", "Character Smiling", R.drawable.anime_feminine_character_smiling),
        Choice("AnimeFeminineCharacterWithSkirt", "Character with Skirt", R.drawable.anime_feminine_character_with_skirt),
        Choice("AnimeGirlWithLongHair", "Girl with Long Hair", R.drawable.anime_girl_with_long_hair),
        Choice("AnimeGirlWithLongHair2", "Girl with Long Hair 2", R.drawable.anime_girl_with_long_hair2),
        Choice("AnimeGirlWithPonytail", "Girl with Ponytail", R.drawable.anime_girl_with_ponytail),
        Choice("AnimeGirlWithSkirt", "Girl with Skirt", R.drawable.anime_girl_with_skirt),
        Choice("AnimeGirlWithTwoPonyTails", "Girl with Two Ponytails", R.drawable.anime_girl_with_two_pony_tails),
    )

    /** Library ID to the picked anime icon's key. */
    var choices by mutableStateOf(emptyMap<String, String>())
        private set

    fun load(context: Context) {
        choices = parse(prefs(context).getString(KEY, "").orEmpty())
    }

    fun canChoose(room: LibraryRoom): Boolean = room.name.contains("anime", ignoreCase = true)

    /** The picked icon, or null when the library keeps its default. */
    fun chosen(room: LibraryRoom, picks: Map<String, String> = choices): Choice? {
        if (!canChoose(room)) return null
        val key = picks[room.id] ?: return null
        return animeChoices.firstOrNull { it.key == key }
    }

    fun setChoice(context: Context, roomId: String, key: String?) {
        choices = if (key == null) choices - roomId else choices + (roomId to key)
        prefs(context).edit().putString(KEY, raw(choices)).apply()
    }

    /** The anime characters have no filled version, so they look the same selected. */
    @DrawableRes
    fun icon(room: LibraryRoom, selected: Boolean, picks: Map<String, String> = choices): Int =
        chosen(room, picks)?.res ?: defaultIcon(room, selected)

    @DrawableRes
    fun defaultIcon(room: LibraryRoom, selected: Boolean): Int = when {
        canChoose(room) -> R.drawable.anime_library
        room.looksLikeRecordings -> if (selected) R.drawable.iconsax_recording_filled else R.drawable.iconsax_recording
        room.kind == LibraryKind.YouTube -> if (selected) R.drawable.iconsax_youtube_filled else R.drawable.iconsax_youtube
        else -> if (selected) R.drawable.iconsax_library_filled else R.drawable.iconsax_library
    }

    /** `libraryID=key` pairs separated by commas, as on iOS. */
    fun parse(raw: String): Map<String, String> =
        raw.split(',').mapNotNull { pair ->
            val parts = pair.split('=', limit = 2)
            if (parts.size == 2 && parts[0].isNotEmpty() && parts[1].isNotEmpty()) parts[0] to parts[1] else null
        }.toMap()

    fun raw(picks: Map<String, String>): String =
        picks.entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }

    private fun prefs(context: Context) = context.getSharedPreferences("zelefin.interface", Context.MODE_PRIVATE)

    private const val KEY = "zelefin.library-icons"
}

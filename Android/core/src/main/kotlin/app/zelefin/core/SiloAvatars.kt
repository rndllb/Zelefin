package app.zelefin.core

import java.net.URI
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** The DiceBear styles Silo's web app offers, in its order. */
enum class SiloAvatarStyle(val id: String, val title: String) {
    Identicon("identicon", "Identicon"),
    Initials("initials", "Initials"),
    Robots("bottts-neutral", "Robots"),
    Emoji("fun-emoji", "Emoji"),
    Pixel("pixel-art-neutral", "Pixel"),
}

data class SiloAvatarPreset(val style: SiloAvatarStyle, val seed: String) {
    /** What Silo stores after `preset:`. */
    val id: String get() = "dicebear:${style.id}:$seed"

    val label: String get() = seed.split('-').joinToString(" ") { part -> part.replaceFirstChar(Char::uppercaseChar) }

    val previewUrl: String
        get() = "https://api.dicebear.com/9.x/${style.id}/png?seed=$seed&size=256&radius=24&backgroundType=gradientLinear"
}

/** Same seeds as Silo's `buildProfileAvatarPresetBatch`, so a pick here matches the web app. */
object SiloAvatarPresets {
    const val BatchSize = 18

    private val adjectives = listOf(
        "cosmic", "jelly", "starlight", "mango", "bubble", "neon", "marble", "comet", "snappy", "pepper", "glimmer",
        "ripple", "pocket", "candy", "ember", "mochi", "sprout", "twinkle", "whiz", "plasma", "mint", "velvet",
        "crunchy", "sunbeam", "toffee", "splash", "boomer", "lunar", "fizzy", "biscuit", "rocket", "cobalt",
    )

    private val nouns = listOf(
        "otter", "rocket", "fox", "cookie", "gecko", "bunny", "penguin", "puffin", "tiger", "panda", "saturn",
        "wizard", "skater", "nebula", "robot", "pirate", "meteor", "sprite", "pebble", "nova", "dragon", "donut",
        "parrot", "panther", "goblin", "muffin", "laser", "pickle", "falcon", "sunset", "toaster", "bandit",
    )

    fun batch(style: SiloAvatarStyle, batch: Int = 0): List<SiloAvatarPreset> {
        val length = style.id.length
        return List(BatchSize) { index ->
            val adjective = adjectives[Math.floorMod(batch * 7 + index * 3 + length, adjectives.size)]
            val noun = nouns[Math.floorMod(batch * 11 + index * 5 + length * 2, nouns.size)]
            SiloAvatarPreset(style, "$adjective-$noun")
        }
    }

    /** The preset id a profile's `avatar` names, without Silo's `preset:` prefix. */
    fun selectedId(avatar: String?): String? = avatar?.trim()?.removePrefix("preset:")?.takeIf { it.isNotEmpty() }

    /** The style of a DiceBear preset id, so the picker opens on the style already in use. */
    fun style(presetId: String?): SiloAvatarStyle? {
        val parts = presetId?.split(':') ?: return null
        if (parts.size != 3 || parts[0] != "dicebear") return null
        return SiloAvatarStyle.entries.firstOrNull { it.id == parts[1] }
    }

    /** `PATCH /api/v2/profiles/{id}` body; a null [presetId] clears the preset. */
    fun patchBody(presetId: String?): String = buildJsonObject {
        put("avatar", presetId?.let { JsonPrimitive("preset:$it") } ?: JsonNull)
    }.toString()
}

object SiloAvatarUrl {
    /**
     * Android cannot draw SVG avatars, so DiceBear's `/svg` endpoint becomes `/png` and any other
     * `.svg` path becomes `.png` (Silo's bundled legacy SVGs then 404 and show initials).
     */
    fun displayable(url: String): String {
        val uri = runCatching { URI(url) }.getOrNull() ?: return url
        val path = uri.rawPath ?: return url
        val host = uri.host?.lowercase().orEmpty()
        val rewritten = when {
            (host == "dicebear.com" || host.endsWith(".dicebear.com")) && path.endsWith("/svg") -> path.removeSuffix("/svg") + "/png"
            path.endsWith(".svg", ignoreCase = true) -> path.dropLast(4) + ".png"
            else -> return url
        }
        val query = uri.rawQuery?.let { "?$it" }.orEmpty()
        val fragment = uri.rawFragment?.let { "#$it" }.orEmpty()
        val authority = uri.rawAuthority?.let { "//$it" }.orEmpty()
        val scheme = uri.scheme?.let { "$it:" }.orEmpty()
        return "$scheme$authority$rewritten$query$fragment"
    }
}

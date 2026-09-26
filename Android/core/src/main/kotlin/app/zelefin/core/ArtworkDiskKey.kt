package app.zelefin.core

import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest

/**
 * Disk identity for artwork. Matches iOS `ArtworkCache.diskKey` plus `ArtworkImageKind`:
 * the key ignores `api_key` and cache-busting `v`, so a new access token still hits the same file.
 */
object ArtworkDiskKey {
    fun key(url: String): String {
        val parsed = runCatching { URI(url) }.getOrNull()
        val path = parsed?.path ?: url
        val canonical = "$path?${canonicalQuery(parsed?.rawQuery)}"
        return "${kind(path)}-${sha256(canonical)}"
    }

    fun kind(path: String): String = when {
        path.contains("/Images/Backdrop") -> "backdrop"
        path.contains("/Images/Logo") -> "logo"
        path.contains("/Images/Primary") ||
            path.contains("/Images/Thumb") ||
            path.contains("/Images/Banner") -> "poster"
        else -> "other"
    }

    private fun canonicalQuery(raw: String?): String {
        if (raw.isNullOrEmpty()) return ""
        return raw.split("&")
            .mapNotNull { pair ->
                if (pair.isEmpty()) return@mapNotNull null
                val name = pair.substringBefore("=")
                if (name == "api_key" || name == "v") return@mapNotNull null
                val value = runCatching {
                    URLDecoder.decode(pair.substringAfter("=", ""), Charsets.UTF_8.name())
                }.getOrDefault(pair.substringAfter("=", ""))
                name to value
            }
            .sortedBy { it.first }
            .joinToString("&") { "${it.first}=${it.second}" }
    }

    private fun sha256(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}

package app.zelefin.core

import java.net.URI

object TrailerLinks {
    fun remote(url: String?, name: String?): TitleTrailer? {
        val raw = url?.trim()?.replace("&amp;", "&").orEmpty()
        if (raw.isEmpty()) return null
        val title = name?.trim()?.ifEmpty { null } ?: "Trailer"
        youtubeId(raw)?.let { id ->
            return TitleTrailer(
                id = "yt-$id",
                title = title,
                caption = "Trailer",
                watchUrl = "https://www.youtube.com/watch?v=$id",
                thumbnailUrl = "https://i.ytimg.com/vi/$id/mqdefault.jpg",
            )
        }
        vimeoId(raw)?.let { id ->
            return TitleTrailer(
                id = "vimeo-$id",
                title = title,
                caption = "Trailer",
                watchUrl = "https://vimeo.com/$id",
            )
        }
        val parsed = runCatching { URI(raw) }.getOrNull() ?: return null
        val scheme = parsed.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return null
        return TitleTrailer(id = "web-$raw", title = title, caption = "Trailer", watchUrl = raw)
    }

    fun youtube(id: String, title: String): TitleTrailer? {
        val video = validatedYouTube(id) ?: return null
        return TitleTrailer(
            id = "yt-$video",
            title = title.ifBlank { "Trailer" },
            caption = "Trailer",
            watchUrl = "https://www.youtube.com/watch?v=$video",
            thumbnailUrl = "https://i.ytimg.com/vi/$video/mqdefault.jpg",
        )
    }

    fun youtubeId(raw: String): String? {
        val trimmed = raw.trim().replace("&amp;", "&")
        if (isYouTubeId(trimmed)) return trimmed
        if (trimmed.lowercase().startsWith("plugin://plugin.video.youtube")) {
            return queryValue(trimmed, "videoid") ?: queryValue(trimmed, "video_id") ?: queryValue(trimmed, "v")
        }
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        val host = uri.host?.lowercase().orEmpty()
        if (host == "youtu.be" || host.endsWith(".youtu.be")) {
            return validatedYouTube(uri.path.trim('/').substringBefore('/'))
        }
        val youtube = host == "youtube.com" || host.endsWith(".youtube.com") ||
            host == "youtube-nocookie.com" || host.endsWith(".youtube-nocookie.com")
        if (!youtube) return null
        queryValue(trimmed, "v")?.let { return it }
        val parts = uri.path.trim('/').split('/').filter { it.isNotEmpty() }
        val marker = parts.indexOfFirst { it.lowercase() in setOf("embed", "v", "shorts", "live", "e") }
        if (marker >= 0 && marker + 1 < parts.size) return validatedYouTube(parts[marker + 1])
        return null
    }

    private fun vimeoId(raw: String): String? {
        val uri = runCatching { URI(raw.trim()) }.getOrNull() ?: return null
        val host = uri.host?.lowercase().orEmpty()
        if (host != "vimeo.com" && !host.endsWith(".vimeo.com")) return null
        val parts = uri.path.trim('/').split('/').filter { it.isNotEmpty() }
        val marker = parts.indexOfFirst { it.equals("video", true) }
        if (marker >= 0 && marker + 1 < parts.size && isVimeoId(parts[marker + 1])) return parts[marker + 1]
        val last = parts.lastOrNull()
        return if (last != null && isVimeoId(last)) last else null
    }

    private fun queryValue(raw: String, name: String): String? {
        val query = raw.substringAfter('?', "")
        val value = query.split('&').firstNotNullOfOrNull { part ->
            val key = part.substringBefore('=')
            if (key.equals(name, true)) part.substringAfter('=', "") else null
        } ?: return null
        return validatedYouTube(value.substringBefore('&'))
    }

    private fun validatedYouTube(value: String?): String? {
        val id = value?.substringBefore('?')?.substringBefore('&')?.trim().orEmpty()
        return if (isYouTubeId(id)) id else null
    }

    private fun isYouTubeId(value: String): Boolean =
        value.length == 11 && value.all { it.isLetterOrDigit() || it == '_' || it == '-' }

    private fun isVimeoId(value: String): Boolean =
        value.length in 5..12 && value.all { it.isDigit() }
}

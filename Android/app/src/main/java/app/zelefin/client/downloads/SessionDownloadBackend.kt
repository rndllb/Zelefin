package app.zelefin.client.downloads

import app.zelefin.client.network.GatewayCredentials
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException

/** Jellyfin serves the original file directly. */
class SessionDownloadBackend : DownloadBackend {
    /** Silo names each version by its own source id and accepts it in the item position; Jellyfin's equals the item id. */
    override suspend fun prepare(item: MediaItem, session: SavedSession): DownloadAsset {
        val token = session.accessToken
        val fileId = item.mediaSourceId?.takeIf { it.isNotBlank() } ?: item.id
        val url = ServerUrl.resolve(session.serverUrl, "/Items/$fileId/Download", token)
            ?: throw ZelefinException.missingStreamUrl()
        val headers = buildMap {
            put("X-Emby-Token", token)
            put("Authorization", "MediaBrowser Token=\"$token\"")
            putAll(GatewayCredentials.headers())
        }
        return DownloadAsset(url = url, headers = headers)
    }

    override suspend fun artworkUrls(item: MediaItem, session: SavedSession): Pair<String?, String?> {
        val seriesId = item.seriesId?.takeIf { it.isNotBlank() }
        val base = session.serverUrl
        val token = session.accessToken
        val poster = item.posterUrl
            ?: ArtworkUrls.primary(base, item, token, maxHeight = 900)
            ?: ServerUrl.resolve(base, "/Items/${item.artworkItemId}/Images/Primary?maxHeight=900&quality=90", token)
        val show = seriesId?.let { ServerUrl.resolve(base, "/Items/$it/Images/Primary?maxHeight=900&quality=90", token) }
        return poster to show
    }
}

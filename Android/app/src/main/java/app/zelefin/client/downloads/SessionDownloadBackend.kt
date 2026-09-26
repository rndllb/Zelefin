package app.zelefin.client.downloads

import app.zelefin.client.network.GatewayCredentials
import app.zelefin.client.silo.SiloClient
import app.zelefin.core.ArtworkUrls
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import kotlinx.coroutines.delay

/** Jellyfin serves the original file directly; Silo registers a managed download and prepares it first. */
class SessionDownloadBackend(private val silo: () -> SiloClient?) : DownloadBackend {
    override suspend fun available(session: SavedSession): Boolean {
        if (!session.usesSilo) return true
        return silo()?.downloadCapability()?.first ?: false
    }

    override suspend fun prepare(item: MediaItem, session: SavedSession): DownloadAsset =
        if (session.usesSilo) prepareSilo(item) else prepareJellyfin(item, session)

    private fun prepareJellyfin(item: MediaItem, session: SavedSession): DownloadAsset {
        val token = session.accessToken
        val url = ServerUrl.resolve(session.serverUrl, "/Items/${item.id}/Download", token)
            ?: throw ZelefinException.missingStreamUrl()
        val headers = buildMap {
            put("X-Emby-Token", token)
            put("Authorization", "MediaBrowser Token=\"$token\"")
            putAll(GatewayCredentials.headers())
        }
        return DownloadAsset(url = url, headers = headers)
    }

    private suspend fun prepareSilo(item: MediaItem): DownloadAsset {
        val client = silo() ?: throw ZelefinException.missingUser()
        val (usable, quality) = client.downloadCapability()
        if (!usable) throw ZelefinException.server("Downloads are not enabled for your Silo profile.")
        val fileId = runCatching { client.downloadFileId(item) }.getOrNull()
        val created = client.createDownload(item.id, fileId, quality)
        val rowId = created.firstOrNull { it.contentId == item.id }?.id
            ?: created.firstOrNull()?.id
            ?: runCatching { client.downloadRows() }.getOrDefault(emptyList()).firstOrNull { it.contentId == item.id }?.id
            ?: throw ZelefinException.server("The Silo server did not accept this download.")
        var ready: SiloClient.ManagedDownload? = null
        for (attempt in 0 until 90) {
            val row = runCatching { client.downloadRows() }.getOrDefault(emptyList()).firstOrNull { it.id == rowId }
            if (row != null) {
                if (row.isReady) {
                    ready = row
                    break
                }
                if (row.isRevoked) throw ZelefinException.server("The Silo server could not prepare this download.")
            }
            delay(if (attempt < 5) 1_000 else 2_000)
        }
        val row = ready ?: throw ZelefinException.server("Timed out waiting for Silo to prepare this download.")
        val url = client.downloadFileUrl(row.id) ?: throw ZelefinException.server("Could not resolve the Silo download URL.")
        return DownloadAsset(url = url, headers = client.mediaHeaders(), knownSize = row.fileSize ?: 0, serverDownloadId = row.id)
    }

    override suspend fun finalize(session: SavedSession, serverDownloadId: String) {
        if (session.usesSilo) silo()?.completeDownload(serverDownloadId)
    }

    override suspend fun deleteServer(session: SavedSession, serverDownloadId: String) {
        if (session.usesSilo) silo()?.deleteDownload(serverDownloadId)
    }

    override suspend fun artworkUrls(item: MediaItem, session: SavedSession): Pair<String?, String?> {
        val seriesId = item.seriesId?.takeIf { it.isNotBlank() }
        if (session.usesSilo) {
            val show = seriesId?.let { id -> runCatching { silo()?.itemPosterUrl(id) }.getOrNull() }
            return item.posterUrl to show
        }
        val base = session.serverUrl
        val token = session.accessToken
        val poster = item.posterUrl
            ?: ArtworkUrls.primary(base, item, token, maxHeight = 900)
            ?: ServerUrl.resolve(base, "/Items/${item.artworkItemId}/Images/Primary?maxHeight=900&quality=90", token)
        val show = seriesId?.let { ServerUrl.resolve(base, "/Items/$it/Images/Primary?maxHeight=900&quality=90", token) }
        return poster to show
    }
}

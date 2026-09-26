package app.zelefin.client.session

import android.content.Context
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.core.HomeFeed
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import app.zelefin.core.TitleDetail
import java.io.File
import java.net.URI
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * On-disk home, catalog, and title snapshots.
 * Layout matches iOS `SnapshotCoding`: `Caches/Zelefin/{Home,Catalog,ItemDetail}Snapshots`,
 * file name `{host}-{userId}[-kind|-itemId].json`, dropped when the version changes.
 */
class SnapshotStore(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val root = File(context.cacheDir, "Zelefin")

    fun loadHome(session: SavedSession): Pair<HomeFeed, List<LibraryRoom>>? {
        val file = file(HOME, session.userId, host(session.serverUrl))
        val snapshot = read<HomeSnapshotFile>(file) ?: return null
        if (snapshot.version != HOME_VERSION || snapshot.userID != session.userId) {
            file.delete()
            return null
        }
        return snapshot.home to snapshot.libraries.map { LibraryRoom(it.id, it.name, LibraryKind.stored(it.kind)) }
    }

    fun saveHome(session: SavedSession, home: HomeFeed, libraries: List<LibraryRoom>) {
        if (home.featured.isEmpty() && home.continueWatching.isEmpty() &&
            home.nextUp.isEmpty() && home.recentMovies.isEmpty() && home.recentShows.isEmpty()
        ) {
            return
        }
        write(
            HOME,
            file(HOME, session.userId, host(session.serverUrl)),
            HomeSnapshotFile(
                version = HOME_VERSION,
                userID = session.userId,
                serverHost = host(session.serverUrl),
                savedAt = Instant.now().toString(),
                home = home,
                libraries = libraries.map { StoredLibrary(it.id, it.name, it.kind.name) },
            ),
        )
    }

    fun loadCatalog(session: SavedSession, kind: String): List<MediaItem>? {
        val file = file(CATALOG, session.userId, host(session.serverUrl), kind)
        val snapshot = read<CatalogSnapshotFile>(file) ?: return null
        if (snapshot.version != CATALOG_VERSION || snapshot.userID != session.userId || snapshot.libraryKind != kind) {
            file.delete()
            return null
        }
        return snapshot.items
    }

    fun saveCatalog(session: SavedSession, kind: String, items: List<MediaItem>) {
        write(
            CATALOG,
            file(CATALOG, session.userId, host(session.serverUrl), kind),
            CatalogSnapshotFile(
                version = CATALOG_VERSION,
                userID = session.userId,
                serverHost = host(session.serverUrl),
                libraryKind = kind,
                savedAt = Instant.now().toString(),
                items = items,
            ),
        )
    }

    fun loadDetail(session: SavedSession, itemId: String): TitleDetail? {
        val file = file(DETAIL, session.userId, host(session.serverUrl), itemId)
        val snapshot = read<ItemDetailSnapshotFile>(file) ?: return null
        if (snapshot.version != DETAIL_VERSION || snapshot.userID != session.userId || snapshot.itemID != itemId) {
            file.delete()
            return null
        }
        return snapshot.detail
    }

    fun saveDetail(session: SavedSession, detail: TitleDetail) {
        write(
            DETAIL,
            file(DETAIL, session.userId, host(session.serverUrl), detail.item.id),
            ItemDetailSnapshotFile(
                version = DETAIL_VERSION,
                userID = session.userId,
                serverHost = host(session.serverUrl),
                itemID = detail.item.id,
                savedAt = Instant.now().toString(),
                detail = detail,
            ),
        )
        pruneDetails()
    }

    private fun pruneDetails() {
        val directory = File(root, DETAIL)
        val files = directory.listFiles()?.filter { it.isFile && it.name.endsWith(".json") } ?: return
        if (files.size <= DETAIL_LIMIT) return
        files.sortedBy { it.lastModified() }
            .take(files.size - DETAIL_LIMIT)
            .forEach { it.delete() }
    }

    private inline fun <reified T> read(file: File): T? {
        if (!file.exists()) return null
        return runCatching { json.decodeFromString<T>(file.readText()) }.getOrElse {
            file.delete()
            null
        }
    }

    private inline fun <reified T> write(folder: String, file: File, value: T) {
        runCatching {
            val directory = File(root, folder)
            directory.mkdirs()
            val data = json.encodeToString(value)
            val temporary = File(directory, "${file.name}.tmp")
            temporary.writeText(data)
            if (!temporary.renameTo(file)) {
                file.writeText(data)
                temporary.delete()
            }
        }
    }

    private fun file(folder: String, userId: String, serverHost: String, extra: String? = null): File {
        val parts = listOfNotNull(serverHost, userId, extra)
        val name = parts.joinToString("-").replace("/", "_").replace(":", "_") + ".json"
        return File(File(root, folder), name)
    }

    private fun host(serverUrl: String): String =
        runCatching { URI(serverUrl).host }.getOrNull()?.takeIf { it.isNotBlank() } ?: serverUrl

    @Serializable
    private data class StoredLibrary(val id: String, val name: String, val kind: String? = null)

    @Serializable
    private data class HomeSnapshotFile(
        val version: Int,
        val userID: String,
        val serverHost: String,
        val savedAt: String,
        val home: HomeFeed,
        val libraries: List<StoredLibrary> = emptyList(),
    )

    @Serializable
    private data class CatalogSnapshotFile(
        val version: Int,
        val userID: String,
        val serverHost: String,
        val libraryKind: String,
        val savedAt: String,
        val items: List<MediaItem>,
    )

    @Serializable
    private data class ItemDetailSnapshotFile(
        val version: Int,
        val userID: String,
        val serverHost: String,
        val itemID: String,
        val savedAt: String,
        val detail: TitleDetail,
    )

    private companion object {
        const val HOME = "HomeSnapshots"
        const val CATALOG = "CatalogSnapshots"
        const val DETAIL = "ItemDetailSnapshots"
        const val HOME_VERSION = 6
        const val CATALOG_VERSION = 2
        const val DETAIL_VERSION = 4
        const val DETAIL_LIMIT = 48
    }
}

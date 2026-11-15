package app.zelefin.client.session

import android.content.Context
import app.zelefin.core.ArtworkImageKind
import app.zelefin.core.CacheInventory
import app.zelefin.core.MetadataCacheFolder
import coil.imageLoader
import java.io.File

/** Artwork disk cache under `cache/Zelefin/Artwork`, with the same buckets as iOS `ArtworkCache`. */
object ArtworkCacheStore {
    private val coilFile = Regex("""[0-9a-f]{64}\.[01]""")

    fun directory(context: Context): File = File(context.cacheDir, "Zelefin/Artwork")

    fun usage(context: Context) = CacheInventory.artworkUsage(
        directory(context),
        ArtworkKindIndex.file(context),
        snapshotDirectories(context),
    )

    fun clear(context: Context, kind: ArtworkImageKind?) {
        val directory = directory(context)
        val index = ArtworkKindIndex.file(context)
        val disk = context.imageLoader.diskCache
        val memory = context.imageLoader.memoryCache
        if (kind == null) {
            disk?.clear()
            memory?.clear()
            ArtworkKindIndex.clear(index)
            directory.listFiles()?.forEach { file ->
                if (file.name == "journal" || file.name.startsWith("journal.")) return@forEach
                file.delete()
            }
            return
        }
        val known = CacheInventory.cachedKeys(directory, index, snapshotDirectories(context))
        val drop = known.filter { ArtworkImageKind.classify(it) == kind }
        val keep = known
            .filter { ArtworkImageKind.classify(it) != kind }
            .map(CacheInventory::coilFileHash)
            .toSet()
        drop.forEach { disk?.remove(it) }
        ArtworkKindIndex.remove(index, drop)
        directory.listFiles()?.forEach { file ->
            if (!file.isFile) return@forEach
            val name = file.name
            if (name == "journal" || name.startsWith("journal.")) return@forEach
            if (coilFile.matches(name)) {
                if (kind == ArtworkImageKind.Other && name.substringBefore('.') !in keep) file.delete()
                return@forEach
            }
            if (ArtworkImageKind.classify(name) == kind) file.delete()
        }
        memory?.keys?.toList()?.forEach { cacheKey ->
            if (ArtworkImageKind.classify(cacheKey.key) == kind) memory.remove(cacheKey)
        }
    }

    private fun snapshotDirectories(context: Context): List<File> {
        val root = File(context.cacheDir, "Zelefin")
        return MetadataCacheFolder.entries.map { File(root, it.directoryName) }
    }
}

package app.zelefin.core

import java.io.File
import java.security.MessageDigest
import java.util.Locale

/** Image buckets. Titles and file prefixes match iOS `ArtworkImageKind`. */
enum class ArtworkImageKind(val title: String, val filePrefix: String) {
    Poster("Posters", "poster-"),
    Backdrop("Backdrops", "backdrop-"),
    Logo("Logos", "logo-"),
    Other("Other", "other-"),
    ;

    companion object {
        fun classify(fileName: String): ArtworkImageKind {
            val name = if (fileName.endsWith(".missing")) fileName.removeSuffix(".missing") else fileName
            return entries.firstOrNull { it != Other && name.startsWith(it.filePrefix) } ?: Other
        }
    }
}

/** Saved-home folders. Titles match iOS `MetadataCacheFolder`. */
enum class MetadataCacheFolder(val directoryName: String, val title: String) {
    Home("HomeSnapshots", "Home"),
    Catalog("CatalogSnapshots", "Catalogs"),
    ItemDetail("ItemDetailSnapshots", "Title details"),
}

data class CacheBucket(val bytes: Long = 0, val fileCount: Int = 0) {
    val isEmpty: Boolean get() = bytes == 0L && fileCount == 0

    fun adding(bytes: Long): CacheBucket = CacheBucket(this.bytes + bytes, fileCount + 1)
}

data class ArtworkCacheUsage(
    val posters: CacheBucket = CacheBucket(),
    val backdrops: CacheBucket = CacheBucket(),
    val logos: CacheBucket = CacheBucket(),
    val other: CacheBucket = CacheBucket(),
) {
    val total: CacheBucket
        get() = CacheBucket(
            bytes = posters.bytes + backdrops.bytes + logos.bytes + other.bytes,
            fileCount = posters.fileCount + backdrops.fileCount + logos.fileCount + other.fileCount,
        )

    fun bucket(kind: ArtworkImageKind): CacheBucket = when (kind) {
        ArtworkImageKind.Poster -> posters
        ArtworkImageKind.Backdrop -> backdrops
        ArtworkImageKind.Logo -> logos
        ArtworkImageKind.Other -> other
    }

    internal fun add(kind: ArtworkImageKind, bytes: Long): ArtworkCacheUsage = when (kind) {
        ArtworkImageKind.Poster -> copy(posters = posters.adding(bytes))
        ArtworkImageKind.Backdrop -> copy(backdrops = backdrops.adding(bytes))
        ArtworkImageKind.Logo -> copy(logos = logos.adding(bytes))
        ArtworkImageKind.Other -> copy(other = other.adding(bytes))
    }
}

data class MetadataCacheUsage(
    val home: CacheBucket = CacheBucket(),
    val catalog: CacheBucket = CacheBucket(),
    val itemDetail: CacheBucket = CacheBucket(),
) {
    val total: CacheBucket
        get() = CacheBucket(
            bytes = home.bytes + catalog.bytes + itemDetail.bytes,
            fileCount = home.fileCount + catalog.fileCount + itemDetail.fileCount,
        )

    fun bucket(folder: MetadataCacheFolder): CacheBucket = when (folder) {
        MetadataCacheFolder.Home -> home
        MetadataCacheFolder.Catalog -> catalog
        MetadataCacheFolder.ItemDetail -> itemDetail
    }
}

/**
 * Byte counts for artwork and saved home data.
 * Coil stores each image under `sha256(diskCacheKey)`, so posters, backdrops, and logos are
 * recognized from the original `poster-` / `backdrop-` / `logo-` keys (the kind index and any
 * snapshot URLs) and from loose files that already use those prefixes.
 */
object CacheInventory {
    private val urlPattern = Regex("""https?://[^\s"'\\<>]+""")
    private val coilFile = Regex("""[0-9a-f]{64}\.[01]""")

    fun artworkUsage(directory: File, indexFile: File? = null, urlSources: List<File> = emptyList()): ArtworkCacheUsage {
        var usage = ArtworkCacheUsage()
        val accounted = mutableSetOf<String>()
        for (key in imageKeys(indexFile, urlSources)) {
            val hash = coilFileHash(key)
            val bytes = coilEntryBytes(directory, hash)
            if (bytes < 0) continue
            accounted.add(hash)
            usage = usage.add(ArtworkImageKind.classify(key), bytes)
        }
        val seen = mutableSetOf<String>()
        directory.listFiles()?.forEach { file ->
            if (!file.isFile) return@forEach
            val name = file.name
            if (name == "journal" || name.startsWith("journal.")) return@forEach
            if (coilFile.matches(name)) {
                val hash = name.substringBefore('.')
                if (hash in accounted || !seen.add(hash)) return@forEach
                val bytes = coilEntryBytes(directory, hash)
                if (bytes >= 0) usage = usage.add(ArtworkImageKind.Other, bytes)
                return@forEach
            }
            if (name.endsWith(".missing")) return@forEach
            usage = usage.add(ArtworkImageKind.classify(name), file.length())
        }
        return usage
    }

    fun metadataUsage(root: File): MetadataCacheUsage {
        fun folder(name: String) = folderUsage(File(root, name))
        return MetadataCacheUsage(
            home = folder(MetadataCacheFolder.Home.directoryName),
            catalog = folder(MetadataCacheFolder.Catalog.directoryName),
            itemDetail = folder(MetadataCacheFolder.ItemDetail.directoryName),
        )
    }

    fun folderUsage(directory: File): CacheBucket {
        if (!directory.isDirectory) return CacheBucket()
        return directory.walkTopDown().filter { it.isFile }.fold(CacheBucket()) { bucket, file ->
            bucket.adding(file.length())
        }
    }

    /** Original Coil disk-cache keys whose image files are still on disk. */
    fun cachedKeys(directory: File, indexFile: File?, urlSources: List<File>): List<String> =
        imageKeys(indexFile, urlSources).filter { coilEntryBytes(directory, coilFileHash(it)) >= 0 }

    /** Coil's on-disk name for a disk-cache key (`sha256` hex, matching `RealDiskCache`). */
    fun coilFileHash(key: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun formatBytes(bytes: Long): String {
        val safe = bytes.coerceAtLeast(0)
        if (safe == 0L) return "0 KB"
        var value = safe / 1000.0
        val units = arrayOf("KB", "MB", "GB", "TB")
        var unit = 0
        while (value >= 1000 && unit < units.lastIndex) {
            value /= 1000.0
            unit++
        }
        val text = String.format(Locale.US, if (value >= 10) "%.0f" else "%.1f", value).removeSuffix(".0")
        return "$text ${units[unit]}"
    }

    private fun imageKeys(indexFile: File?, urlSources: List<File>): Set<String> {
        val keys = linkedSetOf<String>()
        if (indexFile != null && indexFile.isFile) {
            indexFile.readLines().forEach { line ->
                val trimmed = line.trim()
                if (trimmed.isNotEmpty()) keys.add(trimmed)
            }
        }
        urlSources.forEach { root ->
            if (!root.isDirectory) return@forEach
            root.walkTopDown().filter { it.isFile && it.length() <= 8L * 1024 * 1024 }.forEach { file ->
                val text = runCatching { file.readText() }.getOrNull() ?: return@forEach
                urlPattern.findAll(text).forEach { match ->
                    keys.add(ArtworkDiskKey.key(match.value.trimEnd(',', '}', ']')))
                }
            }
        }
        return keys
    }

    /** Combined size of Coil's `.0` metadata and `.1` image, or -1 when the entry is gone. */
    private fun coilEntryBytes(directory: File, hash: String): Long {
        val meta = File(directory, "$hash.0")
        val data = File(directory, "$hash.1")
        if (!meta.isFile && !data.isFile) return -1
        return (if (meta.isFile) meta.length() else 0L) + (if (data.isFile) data.length() else 0L)
    }
}

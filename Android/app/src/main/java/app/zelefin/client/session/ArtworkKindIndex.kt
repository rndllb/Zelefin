package app.zelefin.client.session

import android.content.Context
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * Original Coil disk-cache keys (`poster-…`, `backdrop-…`, `logo-…`, `other-…`).
 * Coil renames them to a hash on disk, so the kind only survives if we keep the key.
 */
object ArtworkKindIndex {
    private val keys = ConcurrentHashMap.newKeySet<String>()
    private val loadedFor = AtomicReference<String?>(null)
    private val io = Executors.newSingleThreadExecutor { task ->
        Thread(task, "zelefin-artwork-index").apply { isDaemon = true }
    }

    fun file(context: Context): File = File(context.cacheDir, "Zelefin/artwork-kinds.txt")

    fun note(context: Context, key: String) {
        val index = file(context)
        load(index)
        if (!keys.add(key)) return
        io.execute {
            runCatching {
                index.parentFile?.mkdirs()
                index.appendText("$key\n")
            }
        }
    }

    fun load(index: File): Set<String> {
        if (loadedFor.get() == index.path) return keys
        synchronized(this) {
            if (loadedFor.get() == index.path) return keys
            if (index.isFile) {
                index.readLines().forEach { line ->
                    val trimmed = line.trim()
                    if (trimmed.isNotEmpty()) keys.add(trimmed)
                }
            }
            loadedFor.set(index.path)
        }
        return keys
    }

    fun remove(index: File, drop: Collection<String>) {
        if (drop.isEmpty()) return
        load(index)
        keys.removeAll(drop.toSet())
        rewrite(index)
    }

    fun clear(index: File) {
        keys.clear()
        loadedFor.set(index.path)
        index.delete()
    }

    private fun rewrite(index: File) {
        index.parentFile?.mkdirs()
        val temporary = File(index.parentFile, "${index.name}.tmp")
        temporary.writeText(keys.joinToString("\n", postfix = if (keys.isEmpty()) "" else "\n"))
        if (!temporary.renameTo(index)) {
            index.writeText(temporary.readText())
            temporary.delete()
        }
    }
}

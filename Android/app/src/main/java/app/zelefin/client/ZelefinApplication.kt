package app.zelefin.client

import android.app.Application
import app.zelefin.client.network.GatewayHttp
import app.zelefin.client.push.ZelefinPush
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.SvgDecoder
import coil.disk.DiskCache
import coil.memory.MemoryCache

class ZelefinApplication : Application(), ImageLoaderFactory {
    init {
        // kotlin-logging uses Android's Log when this is set, and SLF4J otherwise.
        System.setProperty("kotlin-logging-to-android-native", "true")
    }

    override fun onCreate() {
        super.onCreate()
        ZelefinPush.ensureChannel(this)
        app.zelefin.client.session.SessionMessageCenter.install(this)
        app.zelefin.client.ui.loadInterfacePreferences(this)
        app.zelefin.client.cast.ZelefinCast.warmup(this)
    }

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .okHttpClient(GatewayHttp.client)
        .components { add(SvgDecoder.Factory()) }
        .memoryCache { MemoryCache.Builder(this).maxSizeBytes(96 * 1024 * 1024).build() }
        .diskCache {
            DiskCache.Builder()
                .directory(cacheDir.resolve("Zelefin/Artwork"))
                .maxSizeBytes(512L * 1024 * 1024)
                .build()
        }
        .respectCacheHeaders(false)
        .crossfade(false)
        .build()
}

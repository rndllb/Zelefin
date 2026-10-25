package app.zelefin.client.session

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.util.Base64
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.SavedSession
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Jellyfin profile photo upload, like iOS `SessionStore.updateProfileImage`. */
object AccountPhoto {
    private const val MAX_PIXEL = 720

    suspend fun jpeg(context: Context, uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val bitmap = runCatching { decode(context, uri) }.getOrNull()
            ?: throw ZelefinException.server("Zelefin could not read that photo.")
        val longest = maxOf(bitmap.width, bitmap.height)
        val scaled = if (longest > MAX_PIXEL) {
            val scale = MAX_PIXEL.toFloat() / longest
            Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
        } else {
            bitmap
        }
        ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 86, out)
            out.toByteArray()
        }
    }

    private fun decode(context: Context, uri: Uri): Bitmap? = if (Build.VERSION.SDK_INT >= 28) {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val longest = maxOf(info.size.width, info.size.height)
            if (longest > MAX_PIXEL * 2) {
                val scale = (MAX_PIXEL * 2).toFloat() / longest
                decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
            }
        }
    } else {
        context.contentResolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it) }
    }

    /**
     * Uploads to `/UserImage` (Jellyfin 10.9+), falling back to the older `/Users/{id}/Images/Primary`,
     * which is Emby's only route. Both take the JPEG as base64 text.
     */
    suspend fun upload(session: SavedSession, jpeg: ByteArray, userId: String = session.userId) = withContext(Dispatchers.IO) {
        val body = Base64.encodeToString(jpeg, Base64.NO_WRAP)
        val paths = listOfNotNull(
            "/UserImage?userId=$userId".takeUnless { session.isEmbyServer },
            "/Users/$userId/Images/Primary",
        )
        var lastStatus = 0
        for (path in paths) {
            val url = ServerUrl.join(session.serverUrl, path) ?: throw ZelefinException.invalidServerUrl()
            val request = Request.Builder()
                .url(url)
                .post(body.toRequestBody("image/jpeg".toMediaType()))
                .header("Authorization", "MediaBrowser Client=\"Zelefin\", Device=\"${Build.MODEL ?: "Android"}\", DeviceId=\"${session.deviceId}\", Version=\"${app.zelefin.client.BuildConfig.VERSION_NAME}\", Token=\"${session.accessToken}\"")
                .header("X-Emby-Token", session.accessToken)
                .build()
            GatewayHttp.client.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                val headers = response.headers.names().associateWith { response.header(it).orEmpty() }
                if (AccessGateway.isChallenge(response.code, headers, text)) {
                    throw ZelefinException.server("The access gateway blocked the upload. Check Network → Access Gateway.")
                }
                if (response.isSuccessful) return@withContext
                lastStatus = response.code
            }
            if (lastStatus != 404 && lastStatus != 405) break
        }
        throw ZelefinException.server(
            when (lastStatus) {
                401, 403 -> "This account cannot change its profile picture."
                413 -> "Choose a smaller photo."
                else -> "The server did not accept the photo ($lastStatus)."
            },
        )
    }

    /** The current user's image tag after an upload, so the avatar URL changes. */
    suspend fun imageTag(session: SavedSession): String? = withContext(Dispatchers.IO) {
        val url = ServerUrl.join(session.serverUrl, "/Users/${session.userId}") ?: return@withContext null
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("Cache-Control", "no-cache")
            .header("X-Emby-Token", session.accessToken)
            .build()
        runCatching {
            GatewayHttp.client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val root = Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject
                (root["PrimaryImageTag"] as? JsonPrimitive)?.content
            }
        }.getOrNull()
    }
}

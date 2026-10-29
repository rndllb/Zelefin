package app.zelefin.client.network

import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request

object ServerAddress {
    private val probe = GatewayHttp.client.newBuilder()
        .callTimeout(8, TimeUnit.SECONDS)
        .build()

    /**
     * The address with the scheme the server answers on. Only LAN and Tailscale addresses typed
     * without a scheme have a second candidate; anything that connects counts as an answer.
     */
    suspend fun resolve(raw: String): String = withContext(Dispatchers.IO) {
        val candidates = ServerUrl.candidates(raw)
        if (candidates.isEmpty()) throw ZelefinException.invalidServerUrl()
        candidates.dropLast(1).firstOrNull(::answers) ?: candidates.last()
    }

    private fun answers(url: String): Boolean = try {
        probe.newCall(Request.Builder().url(url).build()).execute().close()
        true
    } catch (_: IOException) {
        false
    }
}

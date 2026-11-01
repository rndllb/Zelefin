package app.zelefin.client.network

import app.zelefin.client.ZelefinLog
import app.zelefin.core.AccessGateway
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.Interceptor
import okhttp3.OkHttpClient

object GatewayCredentials {
    @Volatile
    var clientId: String = ""

    @Volatile
    var clientSecret: String = ""

    fun headers(): Map<String, String> = AccessGateway.headers(clientId, clientSecret)
}

object GatewayHttp {
    private val gateway = Interceptor { chain ->
        val headers = GatewayCredentials.headers()
        val request = if (headers.isEmpty()) {
            chain.request()
        } else {
            chain.request().newBuilder().apply {
                headers.forEach { (name, value) -> header(name, value) }
            }.build()
        }
        chain.proceed(request)
    }

    /**
     * Server, Seerr, Ombi, and plugin calls that fail go to the log. A cancelled call (a closed page,
     * a stopped stream) isn't a failure, nor is an expected answer ([ZelefinLog.isExpectedStatus]).
     */
    private val logging = Interceptor { chain ->
        val request = chain.request()
        val response = try {
            chain.proceed(request)
        } catch (e: IOException) {
            if (!chain.call().isCanceled()) {
                ZelefinLog.warning("Network", "${ZelefinLog.describe(request)} failed: ${e.message ?: e::class.java.simpleName}")
            }
            throw e
        }
        if (!response.isSuccessful && !ZelefinLog.isExpectedStatus(request.url.encodedPath, request.url.host, response.code)) {
            ZelefinLog.write(
                if (response.code >= 500) ZelefinLog.Level.Error else ZelefinLog.Level.Warning,
                "Network",
                "${ZelefinLog.describe(request)} → ${response.code}",
            )
        }
        response
    }

    val client: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(ServerRoute.interceptor)
        .addInterceptor(gateway)
        .addInterceptor(logging)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    val playback: OkHttpClient = client.newBuilder()
        .readTimeout(90, TimeUnit.SECONDS)
        .build()
}

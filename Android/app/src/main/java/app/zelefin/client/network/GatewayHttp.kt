package app.zelefin.client.network

import app.zelefin.core.AccessGateway
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

    val client: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(ServerRoute.interceptor)
        .addInterceptor(gateway)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    val playback: OkHttpClient = client.newBuilder()
        .readTimeout(90, TimeUnit.SECONDS)
        .build()
}

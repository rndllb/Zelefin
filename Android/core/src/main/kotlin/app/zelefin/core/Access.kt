package app.zelefin.core

object AccessGateway {
    fun headers(clientId: String, clientSecret: String): Map<String, String> {
        val id = clientId.trim()
        val secret = clientSecret.trim()
        if (id.isEmpty() || secret.isEmpty()) return emptyMap()
        return mapOf(
            "CF-Access-Client-Id" to id,
            "CF-Access-Client-Secret" to secret,
            "P-Access-Token-Id" to id,
            "P-Access-Token" to secret,
        )
    }

    fun isChallenge(status: Int, headers: Map<String, String>, body: String): Boolean {
        fun header(name: String) = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value.orEmpty()
        val location = header("Location")
        val contentType = header("Content-Type")
        val sample = body.take(1_200)
        val looksHtml = contentType.contains("text/html", ignoreCase = true) ||
            sample.contains("<html", ignoreCase = true) ||
            sample.contains("<!doctype html", ignoreCase = true)
        val locationLooksAccess = location.contains("cloudflareaccess.com", ignoreCase = true) ||
            location.contains("cdn-cgi/access", ignoreCase = true)
        val bodyLooksAccess = sample.contains("cloudflareaccess", ignoreCase = true) ||
            sample.contains("cf-access", ignoreCase = true) ||
            sample.contains("pangolin", ignoreCase = true)
        val cfRayBlocked = header("CF-Ray").isNotEmpty() && looksHtml
        if (locationLooksAccess || bodyLooksAccess || cfRayBlocked) return true
        if (looksHtml && status in listOf(301, 302, 303, 307, 308, 401, 403)) return true
        return looksHtml && status in 200..299
    }
}

enum class NetworkFailure {
    NotConnected,
    TimedOut,
    CannotFindHost,
    CannotConnect,
    ConnectionLost,
    Tls,
    BadUrl,
    TransportSecurity,
    Other,
}

sealed class ServerReachability {
    data class Reachable(val serverName: String, val version: String) : ServerReachability()
    data object ReachableRequiringAuthentication : ServerReachability()
    data object BlockedByAccessGateway : ServerReachability()
    data class Failed(val description: String) : ServerReachability()

    val isReachable: Boolean
        get() = this is Reachable || this is ReachableRequiringAuthentication

    val message: String
        get() = when (this) {
            is Reachable -> "Reached $serverName ($version)"
            ReachableRequiringAuthentication ->
                "Reached the server, but it requires auth at the public-info endpoint."
            BlockedByAccessGateway -> ZelefinException.accessGateway().message.orEmpty()
            is Failed -> description
        }

    companion object {
        fun from(error: Throwable): ServerReachability {
            val zelefin = error as? ZelefinException
            if (zelefin?.code == ZelefinException.Code.AccessGateway) return BlockedByAccessGateway
            if (zelefin != null) return Failed(zelefin.message ?: "Couldn’t reach that server.")
            return Failed(error.message ?: "Couldn’t reach that server.")
        }

        fun fromStatus(status: Int): ServerReachability = when (status) {
            401, 403 -> ReachableRequiringAuthentication
            else -> Failed("Server reached, but it doesn't look like a Jellyfin server (HTTP $status).")
        }

        fun fromNetwork(failure: NetworkFailure, fallback: String = ""): ServerReachability =
            Failed(explanation(failure).ifEmpty { fallback.ifEmpty { "Couldn’t reach that server." } })

        fun explanation(failure: NetworkFailure): String = when (failure) {
            NetworkFailure.NotConnected -> "No internet connection."
            NetworkFailure.TimedOut -> "The request timed out."
            NetworkFailure.CannotFindHost -> "Couldn’t find that host. Check the URL."
            NetworkFailure.CannotConnect -> "Couldn’t connect to the host."
            NetworkFailure.ConnectionLost -> "The network connection was lost."
            NetworkFailure.Tls -> "TLS/certificate error. Check HTTPS and the certificate."
            NetworkFailure.BadUrl -> "Invalid server URL."
            NetworkFailure.TransportSecurity -> "App Transport Security blocked this HTTP URL. Use HTTPS."
            NetworkFailure.Other -> ""
        }
    }
}

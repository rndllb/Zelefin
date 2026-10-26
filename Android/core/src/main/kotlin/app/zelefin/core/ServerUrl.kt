package app.zelefin.core

import java.net.URI
import java.util.Locale

object ServerUrl {
    fun normalize(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) throw ZelefinException.invalidServerUrl()
        val prefixed = if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "https://$trimmed"
        }
        return canonical(prefixed)
    }

    /** LAN addresses default to HTTP; public hosts still default to HTTPS. */
    fun normalizeLanAddress(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) throw ZelefinException.invalidServerUrl()
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            return normalize(trimmed)
        }
        val hostPart = trimmed.split("/", limit = 2).first()
        val host = hostPart.split(":", limit = 2).first()
        return if (isInternalHost(host)) normalize("http://$trimmed") else normalize(trimmed)
    }

    fun resolve(base: String, path: String, token: String? = null): String? {
        val resolved = if (isAbsoluteHttp(path)) {
            rewriteIfNeeded(path, base)
        } else {
            join(base, path) ?: return null
        }
        return appendToken(resolved, token)
    }

    fun appending(query: List<Pair<String, String?>>, url: String): String {
        if (query.isEmpty()) return url
        val parts = splitQuery(url)
        val items = parts.second.toMutableList()
        items += query.map { it.first to it.second.orEmpty() }
        return parts.first + "?" + items.joinToString("&") { "${it.first}=${it.second}" }
    }

    fun rewriteIfNeeded(url: String, publicBase: String): String {
        val remote = parse(url) ?: return url
        val base = parse(publicBase) ?: return url
        if (remote.host.equals(base.host, ignoreCase = true)) return url
        if (!isInternalHost(remote.host)) return url
        val publicPath = trimPath(base.path)
        var path = if (remote.path.startsWith("/")) remote.path else "/${remote.path}"
        if (publicPath.isNotEmpty() && path != publicPath && !path.startsWith("$publicPath/")) {
            path = publicPath + path
        }
        return assemble(base.scheme, base.host, base.port, path, remote.query)
    }

    fun isInternalHost(host: String): Boolean {
        val value = host.trim('[', ']').lowercase(Locale.US)
        if (value == "localhost" || value == "::1" || value.startsWith("127.") || value == "0.0.0.0") {
            return true
        }
        if (value.endsWith(".local") || value.endsWith(".lan") || value.endsWith(".internal") || value.endsWith(".home")) {
            return true
        }
        if (!value.contains(".") && !value.contains(":")) return true
        return isPrivateIPv4(value)
    }

    /** An IPv4 network the device sits on directly. */
    data class LocalSubnet(val address: String, val prefixLength: Int)

    /**
     * True when [host] is on a network the device is attached to right now, so Auto can skip the
     * speed test. A LAN IP reached through a VPN subnet route (Tailscale) is still private, but the
     * stream crosses the VPN's uplink and has to be measured like any remote server.
     */
    fun isOnLocalNetwork(host: String, subnets: List<LocalSubnet>): Boolean {
        val value = host.trim('[', ']').lowercase(Locale.US)
        val ip = ipv4(value) ?: return isInternalHost(value)
        if (value.startsWith("127.")) return true
        if (!isPrivateIPv4(value)) return false
        return subnets.any { subnet ->
            val network = ipv4(subnet.address) ?: return@any false
            val prefix = subnet.prefixLength.coerceIn(0, 32)
            if (prefix == 0) return@any false
            val mask = (0xFFFFFFFFL shl (32 - prefix)) and 0xFFFFFFFFL
            (ip and mask) == (network and mask)
        }
    }

    private fun ipv4(value: String): Long? {
        val pieces = value.split(".")
        if (pieces.size != 4) return null
        var result = 0L
        for (piece in pieces) {
            val part = piece.toIntOrNull()?.takeIf { it in 0..255 } ?: return null
            result = (result shl 8) or part.toLong()
        }
        return result
    }

    fun join(base: String, path: String): String? {
        val parsed = parse(base) ?: return null
        val split = path.split("?", limit = 2)
        val rawPath = split[0]
        val query = split.getOrNull(1)
        val extra = when {
            rawPath.isEmpty() -> ""
            rawPath.startsWith("/") -> rawPath
            else -> "/$rawPath"
        }
        return assemble(parsed.scheme, parsed.host, parsed.port, trimPath(parsed.path) + extra, query)
    }

    fun sessionSocket(base: String, token: String, deviceId: String): String? {
        val parsed = parse(base) ?: return null
        val scheme = when (parsed.scheme.lowercase(Locale.US)) {
            "https" -> "wss"
            "http" -> "ws"
            else -> return null
        }
        val path = trimPath(parsed.path) + "/socket"
        val items = splitQueryItems(parsed.query).filter { it.first != "api_key" && it.first != "deviceId" }.toMutableList()
        items += "api_key" to token
        items += "deviceId" to deviceId
        return assemble(scheme, parsed.host, parsed.port, path, items.joinToString("&") { "${it.first}=${it.second}" })
    }

    private fun appendToken(url: String?, token: String?): String? {
        if (url == null) return null
        if (token.isNullOrEmpty()) return url
        val (origin, items) = splitQuery(url)
        if (items.any { it.first.equals("api_key", ignoreCase = true) || it.first.equals("ApiKey", ignoreCase = true) }) {
            return url
        }
        val next = items + ("api_key" to token)
        return origin + "?" + next.joinToString("&") { "${it.first}=${it.second}" }
    }

    private fun canonical(raw: String): String {
        val parsed = parse(raw) ?: throw ZelefinException.invalidServerUrl()
        val scheme = parsed.scheme.lowercase(Locale.US)
        if (scheme != "http" && scheme != "https") throw ZelefinException.invalidServerUrl()
        if (parsed.host.isEmpty()) throw ZelefinException.invalidServerUrl()
        return assemble(scheme, parsed.host, parsed.port, trimPath(parsed.path), null)
    }

    private fun trimPath(path: String): String {
        var value = path
        while (value.length > 1 && value.endsWith("/")) value = value.dropLast(1)
        return if (value == "/") "" else value
    }

    private fun isAbsoluteHttp(path: String): Boolean {
        val parsed = parse(path) ?: return false
        return (parsed.scheme == "http" || parsed.scheme == "https") && parsed.host.isNotEmpty()
    }

    private fun isPrivateIPv4(host: String): Boolean {
        val pieces = host.split(".")
        if (pieces.size != 4) return false
        val parts = pieces.map { it.toIntOrNull() ?: return false }
        if (parts.any { it !in 0..255 }) return false
        return when (parts[0]) {
            10, 127 -> true
            169 -> parts[1] == 254
            172 -> parts[1] in 16..31
            192 -> parts[1] == 168
            else -> false
        }
    }

    private data class Parts(val scheme: String, val host: String, val port: Int?, val path: String, val query: String?)

    private fun parse(raw: String): Parts? {
        val uri = try {
            URI(raw)
        } catch (_: Exception) {
            return null
        }
        val scheme = uri.scheme ?: return null
        val host = uri.host ?: return null
        val path = uri.rawPath ?: ""
        return Parts(scheme, host, uri.port.takeIf { it != -1 }, path, uri.rawQuery)
    }

    private fun assemble(scheme: String, host: String, port: Int?, path: String, query: String?): String {
        val portPart = if (port != null) ":$port" else ""
        val queryPart = if (!query.isNullOrEmpty()) "?$query" else ""
        return "$scheme://$host$portPart$path$queryPart"
    }

    private fun splitQuery(url: String): Pair<String, List<Pair<String, String>>> {
        val index = url.indexOf('?')
        if (index < 0) return url to emptyList()
        return url.substring(0, index) to splitQueryItems(url.substring(index + 1))
    }

    private fun splitQueryItems(query: String?): List<Pair<String, String>> {
        if (query.isNullOrEmpty()) return emptyList()
        return query.split("&").filter { it.isNotEmpty() }.map { item ->
            val eq = item.indexOf('=')
            if (eq < 0) item to "" else item.substring(0, eq) to item.substring(eq + 1)
        }
    }
}

package app.zelefin.client.session

import org.json.JSONObject

/** A Jellyfin `DisplayMessage` from the dashboard or another client. */
data class SessionDisplayMessage(
    val id: String,
    val header: String,
    val text: String,
    val timeoutMs: Int?,
) {
    val alertTitle: String get() = header
    val alertBody: String?
        get() {
            val body = text.trim()
            return if (body.isEmpty() || body.equals(header, ignoreCase = true)) null else body
        }

    companion object {
        const val KIND = "sessionMessage"

        fun parse(json: String): SessionDisplayMessage? = runCatching {
            parse(JSONObject(json))
        }.getOrNull()

        fun parse(root: JSONObject): SessionDisplayMessage? {
            val type = root.optionalString("MessageType") ?: root.optionalString("messageType")
            val payload = root.optionalObject("Data") ?: root.optionalObject("data")
            val name = payload?.optionalString("Name") ?: payload?.optionalString("name")
            val isDisplay = type.equals("DisplayMessage", ignoreCase = true) ||
                (type.equals("GeneralCommand", ignoreCase = true) && name.equals("DisplayMessage", ignoreCase = true))
            if (!isDisplay) return null
            val arguments = payload?.optionalObject("Arguments")
                ?: payload?.optionalObject("arguments")
                ?: payload
                ?: return null
            return parseArguments(arguments)
        }

        fun fromArguments(arguments: Map<String, String?>?): SessionDisplayMessage? {
            if (arguments.isNullOrEmpty()) return null
            val values = JSONObject()
            arguments.forEach { (key, value) ->
                if (value != null) values.put(key, value)
            }
            return parseArguments(values)
        }

        fun fromPush(data: Map<String, String>, fallbackTitle: String?, fallbackBody: String?): SessionDisplayMessage? {
            val kind = data["kind"] ?: data["type"] ?: data["Name"] ?: data["name"]
            val looksLikeMessage = kind.equals("sessionMessage", ignoreCase = true) ||
                kind.equals("DisplayMessage", ignoreCase = true)
            if (!looksLikeMessage) return null
            val header = data.first("Header", "header", "title") ?: fallbackTitle
            val text = data.first("Text", "text", "body", "message") ?: fallbackBody
            if (header.isNullOrBlank() && text.isNullOrBlank()) return null
            return SessionDisplayMessage(
                id = data["id"]?.takeIf { it.isNotBlank() } ?: System.nanoTime().toString(),
                header = header?.takeIf { it.isNotBlank() } ?: "Message",
                text = text?.takeIf { it.isNotBlank() } ?: header.orEmpty(),
                timeoutMs = data.first("TimeoutMs", "timeoutMs", "timeout")?.toIntOrNull(),
            )
        }

        private fun parseArguments(arguments: JSONObject): SessionDisplayMessage? {
            val text = arguments.first("Text", "text", "Message", "message")
            val header = arguments.first("Header", "header", "Title", "title")
            if (text.isNullOrBlank() && header.isNullOrBlank()) return null
            return SessionDisplayMessage(
                id = System.nanoTime().toString(),
                header = header?.takeIf { it.isNotBlank() } ?: "Message",
                text = text?.takeIf { it.isNotBlank() } ?: header.orEmpty(),
                timeoutMs = arguments.first("TimeoutMs", "timeoutMs", "Timeout", "timeout")?.toIntOrNull(),
            )
        }

        private fun JSONObject.first(vararg keys: String): String? {
            keys.forEach { key ->
                keys().asSequence().firstOrNull { it.equals(key, ignoreCase = true) }?.let { match ->
                    optionalString(match)?.takeIf { it.isNotBlank() }?.let { return it }
                }
            }
            return null
        }

        private fun Map<String, String>.first(vararg keys: String): String? {
            keys.forEach { key ->
                entries.firstOrNull { it.key.equals(key, ignoreCase = true) }
                    ?.value
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { return it }
            }
            return null
        }

        private fun JSONObject.optionalString(key: String): String? {
            if (!has(key) || isNull(key)) return null
            return when (val value = opt(key)) {
                is String -> value.trim().takeIf { it.isNotEmpty() }
                is Number -> value.toString()
                else -> optString(key).trim().takeIf { it.isNotEmpty() }
            }
        }

        private fun JSONObject.optionalObject(key: String): JSONObject? =
            if (has(key) && !isNull(key)) optJSONObject(key) else null
    }
}

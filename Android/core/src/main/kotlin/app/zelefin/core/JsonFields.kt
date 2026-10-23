package app.zelefin.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

object LenientJson {
    val parser: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    fun parse(text: String): JsonElement = parser.parseToJsonElement(text)

    fun objectOrNull(text: String): JsonObject? = runCatching { parse(text).jsonObject }.getOrNull()
}

fun JsonObject.str(key: String): String? {
    val value = this[key] ?: return null
    val primitive = value as? JsonPrimitive ?: return null
    if (primitive.isString) return primitive.content.trim().ifEmpty { null }
    return primitive.contentOrNull?.trim()?.ifEmpty { null }
}

fun JsonObject.int(key: String): Int? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.intOrNull ?: value.longOrNull?.toInt() ?: value.contentOrNull?.trim()?.toIntOrNull()
}

fun JsonObject.dbl(key: String): Double? {
    val value = this[key] as? JsonPrimitive ?: return null
    return value.doubleOrNull ?: value.contentOrNull?.trim()?.toDoubleOrNull()
}

fun JsonObject.bool(key: String): Boolean? {
    val value = this[key] as? JsonPrimitive ?: return null
    value.booleanOrNull?.let { return it }
    return when (value.contentOrNull?.trim()?.lowercase()) {
        "true", "yes", "1" -> true
        "false", "no", "0" -> false
        else -> value.intOrNull?.let { it != 0 }
    }
}

fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray

fun JsonObject.objects(key: String): List<JsonObject> =
    (this[key] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

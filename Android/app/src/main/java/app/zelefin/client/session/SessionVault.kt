package app.zelefin.client.session

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import app.zelefin.client.network.GatewayCredentials
import app.zelefin.core.GatewaySecrets
import app.zelefin.core.SavedAccountBox
import app.zelefin.core.SavedSession
import java.util.UUID
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class SessionVault(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val prefs = openPrefs(context)
    private val devicePrefs = context.getSharedPreferences("zelefin.device", Context.MODE_PRIVATE)

    val deviceId: String
        get() {
            val existing = devicePrefs.getString(DEVICE_ID, null)
            if (!existing.isNullOrBlank()) return existing
            val created = UUID.randomUUID().toString()
            devicePrefs.edit().putString(DEVICE_ID, created).apply()
            return created
        }

    fun loadAccounts(): SavedAccountBox? {
        val raw = prefs.getString(ACCOUNTS, null) ?: return null
        return runCatching { json.decodeFromString<SavedAccountBox>(raw) }.getOrNull()
    }

    fun save(session: SavedSession, select: Boolean = true) {
        val box = (loadAccounts() ?: SavedAccountBox()).upsert(session, select)
        prefs.edit().putString(ACCOUNTS, json.encodeToString(box)).apply()
    }

    fun current(): SavedSession? = loadAccounts()?.current

    fun clear() {
        prefs.edit().remove(ACCOUNTS).apply()
    }

    fun loadGateway(): GatewaySecrets {
        val raw = prefs.getString(GATEWAY, null) ?: return GatewaySecrets()
        return runCatching { json.decodeFromString<GatewaySecrets>(raw) }.getOrNull() ?: GatewaySecrets()
    }

    fun saveGateway(secrets: GatewaySecrets) {
        prefs.edit().putString(GATEWAY, json.encodeToString(secrets)).apply()
        GatewayCredentials.clientId = secrets.clientId
        GatewayCredentials.clientSecret = secrets.clientSecret
    }

    fun applyGateway() {
        val secrets = loadGateway()
        GatewayCredentials.clientId = secrets.clientId
        GatewayCredentials.clientSecret = secrets.clientSecret
    }

    private fun openPrefs(context: Context): SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "zelefin.session",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (_: Exception) {
        context.getSharedPreferences("zelefin.session.fallback", Context.MODE_PRIVATE)
    }

    private companion object {
        const val ACCOUNTS = "accounts"
        const val GATEWAY = "gateway"
        const val DEVICE_ID = "device-id"
    }
}

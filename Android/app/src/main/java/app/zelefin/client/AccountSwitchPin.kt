package app.zelefin.client

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import app.zelefin.core.SavedSession
import app.zelefin.core.ZelefinException
import java.security.MessageDigest

/**
 * Device-local 4–6 digit PIN that locks a saved account so others can’t sign into it.
 * Stored as a hash bound to the account, plus an enabled flag — never the digits.
 * Biometric unlock is a separate flag and is offered only while a PIN exists.
 */
class AccountSwitchPin(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = openPrefs(appContext)

    fun hasPin(accountId: String): Boolean {
        if (!prefs.getBoolean(enabledKey(accountId), false)) return false
        return !prefs.getString(hashKey(accountId), null).isNullOrBlank()
    }

    /** On when a PIN exists and this device was allowed to unlock it with biometrics. Defaults on. */
    fun biometricsEnabled(accountId: String): Boolean {
        if (!hasPin(accountId)) return false
        if (!prefs.contains(biometricsKey(accountId))) return AccountBiometrics.canUse(appContext)
        return prefs.getBoolean(biometricsKey(accountId), false)
    }

    fun setBiometricsEnabled(enabled: Boolean, accountId: String) {
        prefs.edit().putBoolean(biometricsKey(accountId), enabled).apply()
    }

    fun setPin(pin: String, accountId: String) {
        val trimmed = pin.trim()
        if (!isValid(trimmed)) throw ZelefinException.server("Enter a 4 to 6 digit PIN.")
        val editor = prefs.edit()
            .putString(hashKey(accountId), digest(trimmed, accountId))
            .putBoolean(enabledKey(accountId), true)
            .remove(biometricsKey(accountId))
        if (AccountBiometrics.canUse(appContext)) editor.putBoolean(biometricsKey(accountId), true)
        editor.apply()
    }

    fun verify(pin: String, accountId: String): Boolean {
        if (!hasPin(accountId)) return false
        val stored = prefs.getString(hashKey(accountId), null) ?: return false
        val candidate = digest(pin.trim(), accountId)
        return MessageDigest.isEqual(stored.toByteArray(Charsets.UTF_8), candidate.toByteArray(Charsets.UTF_8))
    }

    fun remove(accountId: String) {
        prefs.edit().remove(hashKey(accountId)).remove(enabledKey(accountId)).remove(biometricsKey(accountId)).apply()
    }

    private fun openPrefs(context: Context): SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFS,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (_: Exception) {
        context.getSharedPreferences("$PREFS.fallback", Context.MODE_PRIVATE)
    }

    companion object {
        private const val PREFS = "zelefin.account-pin"

        fun isValid(pin: String): Boolean {
            if (pin.length !in 4..6) return false
            return pin.all { it.isDigit() }
        }

        /** Same payload as iOS: the account id is part of the hash, so a PIN is not reusable across accounts. */
        fun digest(pin: String, accountId: String): String {
            val payload = "zelefin.pin.v1|$accountId|$pin".toByteArray(Charsets.UTF_8)
            val hash = MessageDigest.getInstance("SHA-256").digest(payload)
            return hash.joinToString("") { "%02x".format(it) }
        }

        private fun hashKey(accountId: String) = "hash.$accountId"

        private fun enabledKey(accountId: String) = "enabled.$accountId"

        private fun biometricsKey(accountId: String) = "biometrics.$accountId"
    }
}

/** A switch that is waiting for the target account's PIN. */
data class AccountPinPrompt(
    val account: SavedSession,
    val message: String? = null,
    val attempt: Int = 0,
)

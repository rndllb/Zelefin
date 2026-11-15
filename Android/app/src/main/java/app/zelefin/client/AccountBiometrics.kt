package app.zelefin.client

import android.content.Context
import android.content.pm.PackageManager
import androidx.biometric.BiometricManager

/** Face or fingerprint unlock for an account PIN. Device credentials do not count. */
object AccountBiometrics {
    private const val Authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK

    fun canUse(context: Context): Boolean =
        BiometricManager.from(context).canAuthenticate(Authenticators) == BiometricManager.BIOMETRIC_SUCCESS

    /** Face ID when the device has a face sensor, otherwise fingerprint. */
    fun name(context: Context): String {
        val features = context.packageManager
        val face = features.hasSystemFeature(PackageManager.FEATURE_FACE)
        val finger = features.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        return when {
            face && !finger -> "Face ID"
            finger && !face -> "Fingerprint"
            else -> "Face ID or Fingerprint"
        }
    }
}

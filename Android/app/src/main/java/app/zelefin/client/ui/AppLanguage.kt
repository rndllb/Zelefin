package app.zelefin.client.ui

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.os.LocaleListCompat

/**
 * Per-app UI language override. [SYSTEM] follows the device.
 * Applied with [AppCompatDelegate.setApplicationLocales].
 */
enum class AppLanguage(val code: String, val nativeName: String, val englishName: String) {
    SYSTEM("", "System", "System"),
    ENGLISH("en", "English", "English"),
    CHINESE_SIMPLIFIED("zh-Hans", "中文（简体）", "Chinese (Simplified)"),
    HINDI("hi", "हिन्दी", "Hindi"),
    SPANISH("es", "Español", "Spanish"),
    ARABIC("ar", "العربية", "Arabic"),
    FRENCH("fr", "Français", "French"),
    PORTUGUESE_BRAZIL("pt-BR", "Português (Brasil)", "Portuguese (Brazil)"),
    RUSSIAN("ru", "Русский", "Russian"),
    GERMAN("de", "Deutsch", "German"),
    JAPANESE("ja", "日本語", "Japanese"),
    INDONESIAN("id", "Bahasa Indonesia", "Indonesian"),
    ;

    /** Tag passed to AndroidX locale APIs (`zh-CN` for Simplified Chinese). */
    val androidTag: String?
        get() = when (this) {
            SYSTEM -> null
            CHINESE_SIMPLIFIED -> "zh-CN"
            PORTUGUESE_BRAZIL -> "pt-BR"
            else -> code
        }

    companion object {
        const val STORAGE_KEY = "zelefin.appLanguage"

        var current by mutableStateOf(SYSTEM)
            private set

        fun fromStored(raw: String?): AppLanguage =
            entries.firstOrNull { it.code == raw.orEmpty() } ?: SYSTEM

        fun load(context: Context) {
            val raw = prefs(context).getString(STORAGE_KEY, null)
            current = fromStored(raw)
            apply(current)
        }

        fun set(context: Context, language: AppLanguage) {
            current = language
            prefs(context).edit().putString(STORAGE_KEY, language.code).apply()
            apply(language)
        }

        fun apply(language: AppLanguage = current) {
            val locales = language.androidTag
                ?.let { LocaleListCompat.forLanguageTags(it) }
                ?: LocaleListCompat.getEmptyLocaleList()
            AppCompatDelegate.setApplicationLocales(locales)
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences("zelefin.interface", Context.MODE_PRIVATE)
    }
}

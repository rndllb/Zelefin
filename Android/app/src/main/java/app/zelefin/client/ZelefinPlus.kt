package app.zelefin.client

/**
 * Zelefin Plus features on iOS: Downloads, extra accounts, remote sessions, SyncPlay,
 * admin tools. Android has no purchase flow yet, so everything is unlocked. Set
 * [UNLOCKED] to false once Google Play Billing exists; each gated control then shows
 * [notice] instead of running.
 */
object ZelefinPlus {
    const val UNLOCKED = true

    enum class Feature(val title: String) {
        Downloads("Downloads"),
        ExtraAccounts("extra accounts"),
        Sessions("Sessions"),
        SyncPlay("SyncPlay"),
        AdminTools("Admin Tools"),
        Interface("Home and Tabs"),
    }

    fun allows(@Suppress("UNUSED_PARAMETER") feature: Feature): Boolean = UNLOCKED

    fun notice(feature: Feature): Pair<String, String> =
        "Zelefin Plus" to "Zelefin Plus includes ${feature.title}. Sign in, browse, and Play stay free."
}

package app.zelefin.client

/** The server type picked on the Connect screen. */
enum class SignInServerType { Jellyfin, Silo, Emby }

sealed interface SignInRoute {
    /** Jellyfin sign-in, which also covers Silo's Jellyfin-compatible address (`username#profile`). */
    data object Jellyfin : SignInRoute

    /** Silo's own sign-in, then "Who's watching?". */
    data object SiloNative : SignInRoute

    /** Emby's own API; it has no Quick Connect. */
    data object Emby : SignInRoute

    data class Refused(val message: String) : SignInRoute
}

object SignInRouting {
    const val SiloMainAddressMessage = "This is Silo's main address. Choose Silo, or enter Silo's Jellyfin-compatible address."
    const val NotSiloMessage = "This isn't a Silo server. Choose Jellyfin, or check the address."
    const val EmbyAddressMessage = "This is an Emby server. Choose Emby."
    const val NotEmbyMessage = "This isn't an Emby server. Choose Jellyfin, or check the address."

    /**
     * [isSiloMainAddress] is the native Silo probe; [isSiloCompatAddress] is the Jellyfin branding
     * check and is only asked for when Silo is picked and the address is not Silo's main one.
     * [isEmbyAddress] reads `/System/Info/Public` and is only asked for when Jellyfin or Emby is picked.
     */
    inline fun route(
        type: SignInServerType,
        isSiloMainAddress: Boolean,
        isSiloCompatAddress: () -> Boolean,
        isEmbyAddress: () -> Boolean = { false },
    ): SignInRoute =
        when (type) {
            SignInServerType.Jellyfin -> when {
                isSiloMainAddress -> SignInRoute.Refused(SiloMainAddressMessage)
                isEmbyAddress() -> SignInRoute.Refused(EmbyAddressMessage)
                else -> SignInRoute.Jellyfin
            }
            SignInServerType.Silo -> when {
                isSiloMainAddress -> SignInRoute.SiloNative
                isSiloCompatAddress() -> SignInRoute.Jellyfin
                else -> SignInRoute.Refused(NotSiloMessage)
            }
            SignInServerType.Emby -> if (!isSiloMainAddress && isEmbyAddress()) SignInRoute.Emby else SignInRoute.Refused(NotEmbyMessage)
        }
}

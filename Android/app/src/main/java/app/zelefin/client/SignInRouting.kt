package app.zelefin.client

/** The server type picked on the Connect screen. */
enum class SignInServerType { Jellyfin, Silo }

sealed interface SignInRoute {
    /** Jellyfin sign-in, which also covers Silo's Jellyfin-compatible address (`username#profile`). */
    data object Jellyfin : SignInRoute

    /** Silo's own sign-in, then "Who's watching?". */
    data object SiloNative : SignInRoute

    data class Refused(val message: String) : SignInRoute
}

object SignInRouting {
    const val SiloMainAddressMessage = "This is Silo's main address. Choose Silo, or enter Silo's Jellyfin-compatible address."
    const val NotSiloMessage = "This isn't a Silo server. Choose Jellyfin, or check the address."

    /**
     * [isSiloMainAddress] is the native Silo probe; [isSiloCompatAddress] is the Jellyfin branding
     * check and is only asked for when Silo is picked and the address is not Silo's main one.
     */
    inline fun route(type: SignInServerType, isSiloMainAddress: Boolean, isSiloCompatAddress: () -> Boolean): SignInRoute =
        when (type) {
            SignInServerType.Jellyfin -> if (isSiloMainAddress) SignInRoute.Refused(SiloMainAddressMessage) else SignInRoute.Jellyfin
            SignInServerType.Silo -> when {
                isSiloMainAddress -> SignInRoute.SiloNative
                isSiloCompatAddress() -> SignInRoute.Jellyfin
                else -> SignInRoute.Refused(NotSiloMessage)
            }
        }
}

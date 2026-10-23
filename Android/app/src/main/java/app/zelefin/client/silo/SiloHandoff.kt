package app.zelefin.client.silo

import android.content.Context
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.core.SavedSession
import app.zelefin.core.SiloAccount
import app.zelefin.core.SiloLink
import app.zelefin.core.SiloProfile
import app.zelefin.core.ZelefinException

/** The full-screen "Who's watching?" picker shown after a Silo sign-in. */
data class SiloProfilePicker(
    val serverName: String,
    val accountName: String,
    val profiles: List<SiloProfile>,
    val busyProfileId: String? = null,
    val message: String? = null,
)

/** Household profiles of the signed-in Silo account, for switching and the Profile page. */
data class SiloHousehold(
    val profiles: List<SiloProfile> = emptyList(),
    val avatarUploadEnabled: Boolean = false,
    val loading: Boolean = false,
    val switchingTo: String? = null,
    val message: String? = null,
    val signInExpired: Boolean = false,
)

data class SiloPinPrompt(
    val profile: SiloProfile,
    val busy: Boolean = false,
    val message: String? = null,
)

data class SiloNotice(val title: String, val message: String, val signInAgain: Boolean = false)

object SiloHandoff {
    /** Silo approves the code itself, so Jellyfin answers almost at once; give up after about 20 seconds. */
    private val pollPauses = listOf(250L, 500L, 750L, 1_000L, 1_500L, 2_000L, 2_000L, 2_000L, 2_000L, 2_000L, 2_000L, 2_000L, 2_000L)

    /**
     * Signs [profile] into Silo's Jellyfin-compatible API at [jellyfinUrl]: Quick Connect starts on
     * Jellyfin, Silo approves the code as that profile, and Jellyfin hands back the profile's token.
     */
    suspend fun signIn(
        context: Context,
        native: SiloAccountClient,
        account: SiloAccount,
        profile: SiloProfile,
        profileToken: String?,
        jellyfinUrl: String,
        serverName: String?,
        deviceId: String,
    ): SavedSession {
        val library = JellyfinLibrary(context, jellyfinUrl, deviceId = deviceId)
        val handshake = library.startQuickConnect()
        native.approveHandoff(handshake.code, profile.id, profileToken)
        val result = library.waitForQuickConnect(handshake, pollPauses)
        val user = result.user ?: throw ZelefinException.missingUser()
        val tokens = native.tokens ?: throw ZelefinException.siloSignInExpired()
        return SavedSession(
            serverUrl = jellyfinUrl,
            accessToken = result.accessToken.orEmpty(),
            userId = user.id.toString(),
            userName = profile.name,
            deviceId = deviceId,
            userImageTag = user.primaryImageTag,
            serverName = serverName ?: user.serverName,
            isSiloServer = true,
            siloLink = SiloLink(
                nativeUrl = native.baseUrl,
                refreshToken = tokens.refreshToken,
                accessToken = tokens.accessToken,
                accessExpiresAt = tokens.expiresAt,
                accountId = account.id,
                accountName = account.username,
                role = account.role,
                profileId = profile.id,
                profileName = profile.name,
                isPrimaryProfile = profile.isPrimary,
                profileHasPin = profile.hasPin,
                profileToken = profileToken,
                profileAvatarUrl = profile.avatarUrl,
                profileAvatar = profile.avatar,
                profileAvatarSource = profile.avatarSource,
            ),
        )
    }
}

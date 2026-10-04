package app.zelefin.client.session

import android.content.Context
import app.zelefin.client.jellyfin.JellyfinLibrary
import app.zelefin.client.jellyfin.advertiseSessionCapabilities
import app.zelefin.core.SavedSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.jellyfin.sdk.api.sockets.SocketApiState
import org.jellyfin.sdk.api.sockets.subscribeGeneralCommand
import org.jellyfin.sdk.model.api.GeneralCommandType

/**
 * Uses the same Jellyfin API session as library calls. A custom socket used to
 * connect with a different device id, so the dashboard saw Android without DisplayMessage.
 */
class SessionSocket(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    private var job: Job? = null

    fun connect(@Suppress("UNUSED_PARAMETER") session: SavedSession, library: JellyfinLibrary) {
        disconnect()
        job = scope.launch {
            launch {
                library.sdk.webSocket.state.collectLatest { state ->
                    if (state is SocketApiState.Connected) {
                        runCatching { library.advertiseSessionCapabilities() }
                    }
                }
            }
            library.sdk.webSocket.subscribeGeneralCommand(GeneralCommandType.DISPLAY_MESSAGE).collect { message ->
                SessionDisplayMessage.fromArguments(message.data?.arguments)?.let {
                    SessionMessageCenter.present(context, it)
                }
            }
        }
    }

    fun disconnect() {
        job?.cancel()
        job = null
    }
}

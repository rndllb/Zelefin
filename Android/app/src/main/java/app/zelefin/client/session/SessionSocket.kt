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
import org.jellyfin.sdk.api.sockets.subscribe
import org.jellyfin.sdk.api.sockets.subscribeGeneralCommand
import org.jellyfin.sdk.api.sockets.subscribePlayStateCommands
import org.jellyfin.sdk.api.sockets.subscribeSyncPlayCommands
import org.jellyfin.sdk.model.api.GeneralCommandType
import org.jellyfin.sdk.model.api.PlayMessage
import org.jellyfin.sdk.model.api.PlaystateCommand
import org.jellyfin.sdk.model.api.SendCommandType
import org.jellyfin.sdk.model.api.SyncPlayGroupDoesNotExistUpdate
import org.jellyfin.sdk.model.api.SyncPlayGroupJoinedUpdate
import org.jellyfin.sdk.model.api.SyncPlayGroupLeftUpdate
import org.jellyfin.sdk.model.api.SyncPlayGroupUpdateMessage
import org.jellyfin.sdk.model.api.SyncPlayNotInGroupUpdate
import org.jellyfin.sdk.model.api.SyncPlayPlayQueueUpdate

/**
 * Uses the same Jellyfin API session as library calls. A custom socket used to
 * connect with a different device id, so the dashboard saw Android without DisplayMessage.
 */
class SessionSocket(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    private var job: Job? = null

    fun connect(
        @Suppress("UNUSED_PARAMETER") session: SavedSession,
        library: JellyfinLibrary,
        events: Events? = null,
    ) {
        disconnect()
        job = scope.launch {
            launch {
                library.sdk.webSocket.state.collectLatest { state ->
                    if (state is SocketApiState.Connected) {
                        runCatching { library.advertiseSessionCapabilities() }
                    }
                }
            }
            launch {
                library.sdk.webSocket.subscribeGeneralCommand(GeneralCommandType.DISPLAY_MESSAGE).collect { message ->
                    SessionDisplayMessage.fromArguments(message.data?.arguments)?.let {
                        SessionMessageCenter.present(context, it)
                    }
                }
            }
            launch {
                library.sdk.webSocket.subscribe<SyncPlayGroupUpdateMessage>().collect { message ->
                    when (val update = message.data) {
                        is SyncPlayGroupJoinedUpdate -> events?.onGroupJoined(
                            update.groupId.toString(),
                            update.data.groupName.trim(),
                        )
                        is SyncPlayGroupLeftUpdate,
                        is SyncPlayGroupDoesNotExistUpdate,
                        is SyncPlayNotInGroupUpdate -> events?.onGroupLeft()
                        is SyncPlayPlayQueueUpdate -> {
                            val queue = update.data
                            val current = queue.playlist.getOrNull(queue.playingItemIndex) ?: queue.playlist.firstOrNull()
                            if (current != null) {
                                events?.onPlayQueue(
                                    itemId = current.itemId.toString(),
                                    playlistItemId = current.playlistItemId.toString(),
                                    startSeconds = queue.startPositionTicks / TicksPerSecond,
                                )
                            }
                        }
                        else -> Unit
                    }
                }
            }
            launch {
                library.sdk.webSocket.subscribeSyncPlayCommands().collect { message ->
                    val command = message.data ?: return@collect
                    events?.onSyncPlayCommand(command.command, command.positionTicks?.div(TicksPerSecond))
                }
            }
            launch {
                library.sdk.webSocket.subscribe<PlayMessage>().collect { message ->
                    val ids = message.data?.itemIds.orEmpty()
                    val index = message.data?.startIndex ?: 0
                    val itemId = ids.getOrNull(index) ?: ids.firstOrNull() ?: return@collect
                    events?.onRemotePlay(itemId.toString())
                }
            }
            launch {
                library.sdk.webSocket.subscribePlayStateCommands(
                    setOf(PlaystateCommand.STOP, PlaystateCommand.PAUSE, PlaystateCommand.UNPAUSE, PlaystateCommand.SEEK),
                ).collect { message ->
                    val request = message.data ?: return@collect
                    events?.onPlaystate(
                        request.command,
                        request.seekPositionTicks?.div(TicksPerSecond),
                    )
                }
            }
        }
    }

    fun disconnect() {
        job?.cancel()
        job = null
    }

    interface Events {
        fun onGroupJoined(groupId: String, name: String)
        fun onGroupLeft()
        fun onPlayQueue(itemId: String, playlistItemId: String, startSeconds: Double)
        fun onSyncPlayCommand(command: SendCommandType, positionSeconds: Double?)
        fun onRemotePlay(itemId: String)
        fun onRemoteStop()
        fun onPlaystate(command: PlaystateCommand, positionSeconds: Double?)
    }

    private companion object {
        const val TicksPerSecond = 10_000_000.0
    }
}

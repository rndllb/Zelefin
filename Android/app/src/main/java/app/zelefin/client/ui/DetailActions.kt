package app.zelefin.client.ui

import app.zelefin.client.BrowsePage
import app.zelefin.client.jellyfin.RemoteArtworkKind
import app.zelefin.client.jellyfin.RemoteImageChoice
import app.zelefin.client.jellyfin.RemoteSession
import app.zelefin.client.jellyfin.SyncPlayGroup
import app.zelefin.core.MediaItem

/** Title-page navigation and server actions, supplied by the model. Nullable entries hide their menu rows. */
class DetailTitleActions(
    val onBrowse: (BrowsePage) -> Unit = {},
    val onRefreshDetail: () -> Unit = {},
    val remoteTargets: (suspend () -> List<RemoteSession>)? = null,
    val playOnRemote: suspend (RemoteSession, MediaItem) -> Unit = { _, _ -> },
    val syncPlayGroups: (suspend () -> List<SyncPlayGroup>)? = null,
    val playInSyncPlay: suspend (item: MediaItem, joinGroupId: String?, newGroupName: String?) -> Unit = { _, _, _ -> },
    val refreshMetadata: (suspend (MediaItem) -> Unit)? = null,
    val remoteArtwork: (suspend (MediaItem, RemoteArtworkKind) -> List<RemoteImageChoice>)? = null,
    val applyArtwork: suspend (MediaItem, RemoteArtworkKind, RemoteImageChoice) -> Unit = { _, _, _ -> },
    val deleteFromLibrary: (suspend (MediaItem) -> Unit)? = null,
)

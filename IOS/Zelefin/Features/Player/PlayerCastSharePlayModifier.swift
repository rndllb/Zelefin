import SwiftUI

/// Keeps PlayerView's body under the type-checker limit while wiring Cast + SharePlay.
struct PlayerCastSharePlayModifier: ViewModifier {
    var sharePlay: SharePlayManager
    var activeItem: MediaItem
    var model: PlayerModel?
    var onHelloReply: (SharePlayCommand) -> Void
    var onFollowItem: (String) -> Void
    var onCastConnected: () -> Void
    var onCastDisconnected: () -> Void
    var onCastFinished: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: sharePlay.incomingCommand) { _, command in
                guard let command else { return }
                if command.kind == .hello {
                    onHelloReply(command)
                    sharePlay.incomingCommand = nil
                    return
                }
                model?.applySharePlayCommand(command)
                sharePlay.incomingCommand = nil
            }
            .onChange(of: sharePlay.activityItemId) { _, id in
                guard let id, id != activeItem.id else { return }
                onFollowItem(id)
            }
            .onChange(of: CastManager.shared.isConnected) { wasConnected, isConnected in
                if isConnected {
                    onCastConnected()
                } else if wasConnected {
                    onCastDisconnected()
                }
            }
            .onChange(of: CastManager.shared.playbackFinishedCount) { _, _ in
                onCastFinished()
            }
    }
}

extension View {
    func playerCastSharePlay(
        sharePlay: SharePlayManager,
        activeItem: MediaItem,
        model: PlayerModel?,
        onHelloReply: @escaping (SharePlayCommand) -> Void,
        onFollowItem: @escaping (String) -> Void,
        onCastConnected: @escaping () -> Void,
        onCastDisconnected: @escaping () -> Void,
        onCastFinished: @escaping () -> Void
    ) -> some View {
        modifier(
            PlayerCastSharePlayModifier(
                sharePlay: sharePlay,
                activeItem: activeItem,
                model: model,
                onHelloReply: onHelloReply,
                onFollowItem: onFollowItem,
                onCastConnected: onCastConnected,
                onCastDisconnected: onCastDisconnected,
                onCastFinished: onCastFinished
            )
        )
    }
}

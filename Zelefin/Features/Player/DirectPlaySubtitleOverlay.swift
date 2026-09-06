import SwiftUI
import UIKit

/// Draws overlay cues on the fitted video picture (letterbox-aware), including authored PGS rects.
struct DirectPlaySubtitleOverlay: View {
    let cues: [DirectPlaySubtitleCue]
    let pictureSize: CGSize
    var fillsScreen = false

    var body: some View {
        GeometryReader { proxy in
            let video = DirectPlayPictureLayout.pictureRect(
                picture: pictureSize,
                in: proxy.size,
                fill: fillsScreen
            )
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    cueView(cue, in: video)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cueView(_ cue: DirectPlaySubtitleCue, in video: CGRect) -> some View {
        switch cue.body {
        case .image(let image):
            bitmapCue(image, in: video)
        case .text(let text):
            textCue(text, placement: cue.placement, in: video)
        case .richText(let runs):
            textCue(runs.map(\.text).joined(), placement: cue.placement, in: video)
        }
    }

    private func bitmapCue(_ image: DirectPlaySubtitleImage, in video: CGRect) -> some View {
        let frame = DirectPlayPictureLayout.imageFrame(
            position: image.position,
            canvasSize: image.canvasSize,
            in: video
        )
        return Image(uiImage: UIImage(cgImage: image.cgImage))
            .resizable()
            .frame(width: max(1, frame.width), height: max(1, frame.height))
            .position(x: frame.midX, y: frame.midY)
    }

    private func textCue(_ text: String, placement: DirectPlaySubtitlePlacement?, in video: CGRect) -> some View {
        let layout = DirectPlayPictureLayout.textLayout(pictureHeight: video.height)
        let point: CGPoint
        if let position = placement?.position {
            point = CGPoint(
                x: video.minX + position.x * video.width,
                y: video.minY + position.y * video.height
            )
        } else {
            point = CGPoint(
                x: video.midX,
                y: video.maxY - layout.bottomMargin - layout.fontSize
            )
        }
        return Text(text)
            .font(.system(size: layout.fontSize, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.95), radius: 2, y: 1)
            .shadow(color: .black, radius: 0, y: 1)
            .frame(maxWidth: video.width * 0.9)
            .position(x: point.x, y: point.y)
    }
}

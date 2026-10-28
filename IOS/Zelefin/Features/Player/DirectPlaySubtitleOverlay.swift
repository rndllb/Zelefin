import SwiftUI
import UIKit

/// Draws overlay cues on the fitted video picture (letterbox-aware), including authored PGS rects.
struct DirectPlaySubtitleOverlay: View {
    let cues: [DirectPlaySubtitleCue]
    let pictureSize: CGSize
    var fillsScreen = false
    /// Top of the visible progress bar in screen points; cues that would sit under it rise above it.
    var controlsTop: CGFloat? = nil
    @AppStorage(SubtitleAppearance.sizeKey) private var sizeRaw = SubtitleAppearance.Size.medium.rawValue
    @AppStorage(SubtitleAppearance.colorKey) private var colorRaw = SubtitleAppearance.TextColor.white.rawValue
    @AppStorage(SubtitleAppearance.backgroundKey) private var backgroundRaw = SubtitleAppearance.Background.dropShadow.rawValue
    @AppStorage(SubtitleAppearance.brightnessKey) private var brightness = 100.0
    @AppStorage(SubtitleAppearance.positionKey) private var positionLift = 0.0

    var body: some View {
        GeometryReader { proxy in
            let video = DirectPlayPictureLayout.pictureRect(
                picture: pictureSize,
                in: proxy.size,
                fill: fillsScreen
            )
            let ceiling = controlsTop.map { $0 - proxy.frame(in: .global).minY - 8 }
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    cueView(cue, in: video, ceiling: ceiling)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .animation(.easeInOut(duration: 0.25), value: ceiling)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cueView(_ cue: DirectPlaySubtitleCue, in video: CGRect, ceiling: CGFloat?) -> some View {
        switch cue.body {
        case .image(let image):
            bitmapCue(image, in: video, ceiling: ceiling)
        case .text(let text):
            textCue(text, placement: nil, in: video, ceiling: ceiling)
        case .richText(let runs):
            textCue(DirectPlayPictureLayout.joinedRunText(runs.map(\.text)), placement: nil, in: video, ceiling: ceiling)
        }
    }

    /// How far a cue whose bottom edge is at `bottom` moves up to clear the controls (zero or negative).
    private func rise(bottom: CGFloat, ceiling: CGFloat?) -> CGFloat {
        guard let ceiling else { return 0 }
        return min(0, ceiling - bottom)
    }

    /// Image subtitles (PGS, VobSub) follow the size setting too, growing from their bottom edge so a
    /// line near the bottom of the picture stays there.
    private func bitmapCue(_ image: DirectPlaySubtitleImage, in video: CGRect, ceiling: CGFloat?) -> some View {
        let frame = DirectPlayPictureLayout.imageFrame(
            position: image.position,
            canvasSize: image.canvasSize,
            in: video
        )
        let scale = (SubtitleAppearance.Size(rawValue: sizeRaw) ?? .medium).scale
        let width = max(1, frame.width * scale)
        let height = max(1, frame.height * scale)
        return Image(uiImage: UIImage(cgImage: image.cgImage))
            .resizable()
            .frame(width: width, height: height)
            .position(x: frame.midX, y: frame.maxY - height / 2)
            .offset(y: rise(bottom: frame.maxY, ceiling: ceiling))
    }

    private func textCue(_ text: String, placement: DirectPlaySubtitlePlacement?, in video: CGRect, ceiling: CGFloat?) -> some View {
        let size = SubtitleAppearance.Size(rawValue: sizeRaw) ?? .medium
        let color = SubtitleAppearance.TextColor(rawValue: colorRaw) ?? .white
        let background = SubtitleAppearance.Background(rawValue: backgroundRaw) ?? .dropShadow
        let layout = DirectPlayPictureLayout.textLayout(
            pictureHeight: video.height,
            sizeScale: size.scale,
            lift: CGFloat(positionLift / 100)
        )
        let point: CGPoint
        if let position = placement?.position {
            let lift = CGFloat(positionLift / 100) * video.height * 0.32
            point = CGPoint(
                x: video.minX + position.x * video.width,
                y: video.minY + position.y * video.height - lift
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
            .modifier(SubtitleTextChrome(color: color, background: background, brightness: brightness))
            .frame(maxWidth: video.width * 0.9)
            .position(x: point.x, y: point.y)
            // The cue is centred on `point`; two lines reach about 1.2 font sizes below it.
            .offset(y: rise(bottom: point.y + layout.fontSize * 1.2, ceiling: ceiling))
    }
}

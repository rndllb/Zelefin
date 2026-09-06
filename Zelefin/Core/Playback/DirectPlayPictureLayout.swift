import CoreGraphics
import Foundation

/// Maps overlay cues onto the on-screen picture (`resizeAspect` or `resizeAspectFill`).
enum DirectPlayPictureLayout {
    static func pictureRect(picture: CGSize, in bounds: CGSize, fill: Bool) -> CGRect {
        fill ? filledRect(picture: picture, in: bounds) : fittedRect(picture: picture, in: bounds)
    }

    static func fittedRect(picture: CGSize, in bounds: CGSize) -> CGRect {
        guard picture.width > 0, picture.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let pictureAspect = picture.width / picture.height
        let boundsAspect = bounds.width / bounds.height
        if pictureAspect > boundsAspect {
            let height = bounds.width / pictureAspect
            let y = (bounds.height - height) / 2
            return CGRect(x: 0, y: y, width: bounds.width, height: height)
        }
        let width = bounds.height * pictureAspect
        let x = (bounds.width - width) / 2
        return CGRect(x: x, y: 0, width: width, height: bounds.height)
    }

    /// Covers the view (crop). 16:9 on 16:10 fills top-to-bottom; 4:3 on 16:9 fills side-to-side.
    static func filledRect(picture: CGSize, in bounds: CGSize) -> CGRect {
        guard picture.width > 0, picture.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let pictureAspect = picture.width / picture.height
        let boundsAspect = bounds.width / bounds.height
        if pictureAspect > boundsAspect {
            let width = bounds.height * pictureAspect
            let x = (bounds.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: bounds.height)
        }
        let height = bounds.width / pictureAspect
        let y = (bounds.height - height) / 2
        return CGRect(x: 0, y: y, width: bounds.width, height: height)
    }

    /// Bitmap cues: `position` is normalized against `canvasSize`, or against the video frame when
    /// the canvas is zero. Result is in view coordinates inside `frame`.
    static func imageFrame(
        position: CGRect,
        canvasSize: CGSize,
        in frame: CGRect
    ) -> CGRect {
        let local: CGRect
        if canvasSize.width > 0, canvasSize != .zero {
            let scale = frame.width / canvasSize.width
            let px = position.minX * canvasSize.width * scale
            let py = position.minY * canvasSize.height * scale
            let canvasCenterY = canvasSize.height / 2 * scale
            let frameCenterY = frame.height / 2
            local = CGRect(
                x: px,
                y: frameCenterY + (py - canvasCenterY),
                width: position.width * canvasSize.width * scale,
                height: position.height * canvasSize.height * scale
            )
        } else {
            local = CGRect(
                x: position.minX * frame.width,
                y: position.minY * frame.height,
                width: position.width * frame.width,
                height: position.height * frame.height
            )
        }
        return local.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    static func textLayout(pictureHeight: CGFloat) -> (fontSize: CGFloat, bottomMargin: CGFloat) {
        let height = max(pictureHeight, 1)
        return (min(36, max(17, height * 0.05)), height * 0.06)
    }

    /// The engine publishes a prefetch window. Only cues whose time range contains the playhead
    /// belong on screen; everything else is future (or expired) text that would stack and look early.
    static func visibleCues(
        in cues: [DirectPlaySubtitleCue],
        at seconds: TimeInterval
    ) -> [DirectPlaySubtitleCue] {
        cues.filter { cue in
            cue.startTime <= seconds && seconds < cue.endTime
        }
    }
}

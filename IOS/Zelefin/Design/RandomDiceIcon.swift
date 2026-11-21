import SwiftUI

/// Lucide-style dice face (1…6), matching Jellyfin Enhanced’s random-button icons.
struct RandomDiceIcon: View {
    /// Pip count on the face; values outside 1…6 clamp.
    var face: Int
    var lineWidth: CGFloat = 2

    private var pips: Int { min(6, max(1, face)) }

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let inset = lineWidth / 2
            let rect = CGRect(
                x: size.width * (3.0 / 24.0),
                y: size.height * (3.0 / 24.0),
                width: size.width * (18.0 / 24.0),
                height: size.height * (18.0 / 24.0)
            ).insetBy(dx: inset, dy: inset)
            let radius = min(rect.width, rect.height) * (2.0 / 18.0)
            context.stroke(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .foreground,
                style: stroke
            )

            let pipRadius = max(lineWidth * 0.55, size.width * 0.045)
            for point in Self.pipUnits(for: pips) {
                let center = CGPoint(
                    x: size.width * point.x,
                    y: size.height * point.y
                )
                let pip = Path(ellipseIn: CGRect(
                    x: center.x - pipRadius,
                    y: center.y - pipRadius,
                    width: pipRadius * 2,
                    height: pipRadius * 2
                ))
                context.fill(pip, with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }

    /// Pip centers in the Lucide 24×24 viewBox, as unit fractions.
    private static func pipUnits(for face: Int) -> [CGPoint] {
        func unit(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x / 24, y: y / 24)
        }
        switch face {
        case 1:
            return [unit(12, 12)]
        case 2:
            return [unit(15, 9), unit(9, 15)]
        case 3:
            return [unit(16, 8), unit(12, 12), unit(8, 16)]
        case 4:
            return [unit(16, 8), unit(8, 8), unit(8, 16), unit(16, 16)]
        case 5:
            return [unit(16, 8), unit(8, 8), unit(8, 16), unit(16, 16), unit(12, 12)]
        default:
            return [
                unit(16, 8), unit(16, 12), unit(16, 16),
                unit(8, 8), unit(8, 12), unit(8, 16),
            ]
        }
    }

    static func nextFace(excluding current: Int) -> Int {
        let options = (1...6).filter { $0 != current }
        return options.randomElement() ?? current
    }
}

/// Wobble + full spin from Jellyfin Enhanced’s `dice` keyframes (0.6s loop while loading).
private struct RandomDiceSpin<Content: View>: View {
    var rolling: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !rolling)) { context in
            let phase: CGFloat = {
                guard rolling else { return 0 }
                let t = context.date.timeIntervalSinceReferenceDate
                return CGFloat(t.truncatingRemainder(dividingBy: 0.6) / 0.6)
            }()
            let sample = Self.sample(at: phase)
            content()
                .scaleEffect(sample.scale)
                .rotationEffect(.degrees(sample.rotation))
        }
    }

    private static func sample(at t: CGFloat) -> (rotation: CGFloat, scale: CGFloat) {
        // Matches:
        // 0%,100% → 0°/1; 10/30/50% → -10°/1.1; 20/40% → 10°/1.1; 60% → 360°/1
        let keys: [(CGFloat, CGFloat, CGFloat)] = [
            (0.0, 0, 1),
            (0.1, -10, 1.1),
            (0.2, 10, 1.1),
            (0.3, -10, 1.1),
            (0.4, 10, 1.1),
            (0.5, -10, 1.1),
            (0.6, 360, 1),
            (1.0, 0, 1),
        ]
        for index in 0..<(keys.count - 1) {
            let a = keys[index]
            let b = keys[index + 1]
            if t <= b.0 || index == keys.count - 2 {
                let span = max(b.0 - a.0, 0.0001)
                let u = min(1, max(0, (t - a.0) / span))
                return (
                    rotation: a.1 + (b.1 - a.1) * u,
                    scale: a.2 + (b.2 - a.2) * u
                )
            }
        }
        return (0, 1)
    }
}

extension View {
    func randomDiceSpin(rolling: Bool) -> some View {
        RandomDiceSpin(rolling: rolling) { self }
    }
}

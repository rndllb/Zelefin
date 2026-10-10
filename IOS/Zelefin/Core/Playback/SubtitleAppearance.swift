import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// Text-subtitle look and timing stored on this device.
enum SubtitleAppearance {
    static let sizeKey = "zelefin.subtitles.size"
    static let colorKey = "zelefin.subtitles.color"
    static let backgroundKey = "zelefin.subtitles.background"
    static let brightnessKey = "zelefin.subtitles.brightness"
    static let positionKey = "zelefin.subtitles.position"
    static let syncKey = "zelefin.subtitles.sync-seconds"

    static let brightnessRange: ClosedRange<Double> = 10...100
    static let positionRange: ClosedRange<Double> = 0...100
    static let syncRange: ClosedRange<Double> = -10...10
    static let syncStep = 0.25

    enum Size: String, CaseIterable, Identifiable {
        case small
        case medium
        case large
        case extraLarge

        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }

        var scale: CGFloat {
            switch self {
            case .small: 0.78
            case .medium: 1
            case .large: 1.28
            case .extraLarge: 1.58
            }
        }

        var relativeFontSize: CGFloat {
            switch self {
            case .small: 80
            case .medium: 100
            case .large: 130
            case .extraLarge: 160
            }
        }
    }

    enum TextColor: String, CaseIterable, Identifiable {
        case white
        case yellow
        case cyan
        case green
        case magenta

        var id: String { rawValue }
        var title: String {
            switch self {
            case .white: "White"
            case .yellow: "Yellow"
            case .cyan: "Cyan"
            case .green: "Green"
            case .magenta: "Magenta"
            }
        }

        var color: Color {
            switch self {
            case .white: .white
            case .yellow: Color(red: 1, green: 0.92, blue: 0.2)
            case .cyan: Color(red: 0.35, green: 0.92, blue: 1)
            case .green: Color(red: 0.45, green: 0.95, blue: 0.45)
            case .magenta: Color(red: 1, green: 0.45, blue: 0.85)
            }
        }
    }

    enum Background: String, CaseIterable, Identifiable {
        case none
        case dropShadow
        case outline
        case highlight

        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .dropShadow: "Drop Shadow"
            case .outline: "Outline"
            case .highlight: "Highlight"
            }
        }
    }

    enum Position: String, CaseIterable, Identifiable {
        case `default`
        case raised

        var id: String { rawValue }
        var title: String {
            switch self {
            case .default: "Default"
            case .raised: "Raised"
            }
        }

        var liftPreset: Double {
            switch self {
            case .default: 0
            case .raised: 45
            }
        }
    }

    static var size: Size {
        get { Size(rawValue: string(sizeKey)) ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey) }
    }

    static var color: TextColor {
        get { TextColor(rawValue: string(colorKey)) ?? .white }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: colorKey) }
    }

    static var background: Background {
        get { Background(rawValue: string(backgroundKey)) ?? .dropShadow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: backgroundKey) }
    }

    static var brightness: Double {
        get { clamped(UserDefaults.standard.object(forKey: brightnessKey) as? Double ?? 100, brightnessRange) }
        set { UserDefaults.standard.set(clamped(newValue, brightnessRange), forKey: brightnessKey) }
    }

    static var positionLift: Double {
        get { clamped(UserDefaults.standard.object(forKey: positionKey) as? Double ?? 0, positionRange) }
        set { UserDefaults.standard.set(clamped(newValue, positionRange), forKey: positionKey) }
    }

    static var position: Position {
        get { positionLift > 0.5 ? .raised : .default }
        set { positionLift = newValue.liftPreset }
    }

    static var syncSeconds: Double {
        get { snappedSync(UserDefaults.standard.object(forKey: syncKey) as? Double ?? 0) }
        set { UserDefaults.standard.set(snappedSync(newValue), forKey: syncKey) }
    }

    static func snappedSync(_ value: Double) -> Double {
        let clampedValue = min(syncRange.upperBound, max(syncRange.lowerBound, value))
        return (clampedValue / syncStep).rounded() * syncStep
    }

    static func syncTitle(_ seconds: Double = syncSeconds) -> String {
        let value = snappedSync(seconds)
        if abs(value) < 0.001 { return "In Sync" }
        let formatted = String(format: "%@%.2f s", value > 0 ? "+" : "", value)
        return formatted.replacingOccurrences(of: ".00 s", with: " s").replacingOccurrences(of: ".50 s", with: ".5 s")
    }

    static func foreground(color: TextColor = color, brightness: Double = brightness) -> Color {
        color.color.opacity(clamped(brightness, brightnessRange) / 100)
    }

    static func textLayout(pictureHeight: CGFloat) -> (fontSize: CGFloat, bottomMargin: CGFloat) {
        DirectPlayPictureLayout.textLayout(
            pictureHeight: pictureHeight,
            sizeScale: size.scale,
            lift: CGFloat(positionLift / 100)
        )
    }

    static func textStyleRules() -> [AVTextStyleRule] {
        var attributes: [String: Any] = [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: argb(color.color, alpha: brightness / 100),
            kCMTextMarkupAttribute_RelativeFontSize as String: size.relativeFontSize,
        ]
        switch background {
        case .none:
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = kCMTextMarkupCharacterEdgeStyle_None
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = argb(.black, alpha: 0)
        case .dropShadow:
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = kCMTextMarkupCharacterEdgeStyle_DropShadow
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = argb(.black, alpha: 0)
        case .outline:
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = kCMTextMarkupCharacterEdgeStyle_Uniform
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = argb(.black, alpha: 0)
        case .highlight:
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = kCMTextMarkupCharacterEdgeStyle_None
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = argb(.black, alpha: 0.62 * (brightness / 100))
        }
        return AVTextStyleRule(textMarkupAttributes: attributes).map { [$0] } ?? []
    }

    private static func argb(_ color: Color, alpha: Double) -> [CGFloat] {
        let ui = UIColor(color)
        var r: CGFloat = 1
        var g: CGFloat = 1
        var b: CGFloat = 1
        var a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [CGFloat(min(1, max(0, alpha))), r, g, b]
    }

    private static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    private static func clamped(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

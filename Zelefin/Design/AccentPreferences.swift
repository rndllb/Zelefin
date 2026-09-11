import SwiftUI
import UIKit

/// Named accent swatches plus an optional custom hex, stored in UserDefaults.
struct AccentPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hex: String

    var color: Color {
        AccentPreferences.color(fromHex: hex) ?? Color(red: 42 / 255, green: 212 / 255, blue: 252 / 255)
    }
}

enum AccentPreferences {
    static let presetIdKey = "zelefin.accent-preset-id"
    static let customHexKey = "zelefin.custom-accent-hex"
    static let customId = "custom"
    static let defaultId = cyan.id
    static let defaultCustomHex = cyan.hex

    /// Login-button cyan. This is the default interface accent.
    static let cyan = AccentPreset(id: "cyan", name: "Cyan", hex: "#2AD4FC")

    static let presets: [AccentPreset] = [
        cyan,
        AccentPreset(id: "red", name: "Red", hex: "#FA2D48"),
        AccentPreset(id: "pink", name: "Pink", hex: "#FF3778"),
        AccentPreset(id: "orange", name: "Orange", hex: "#FF9500"),
        AccentPreset(id: "yellow", name: "Yellow", hex: "#FFD60A"),
        AccentPreset(id: "green", name: "Green", hex: "#34C759"),
        AccentPreset(id: "teal", name: "Teal", hex: "#30B0C7"),
        AccentPreset(id: "blue", name: "Blue", hex: "#0A84FF"),
        AccentPreset(id: "indigo", name: "Indigo", hex: "#5E5CE6"),
        AccentPreset(id: "purple", name: "Purple", hex: "#BF5AF2"),
        AccentPreset(id: "lightgray", name: "Light Gray", hex: "#ACACB0")
    ]

    static var current: Color {
        color(id: storedPresetId, customHex: storedCustomHex)
    }

    static func color(id: String, customHex: String) -> Color {
        preset(id: id, customHex: customHex).color
    }

    static func preset(id: String, customHex: String = defaultCustomHex) -> AccentPreset {
        if id == customId {
            let hex = normalizedHex(customHex) ?? defaultCustomHex
            return AccentPreset(id: customId, name: "Custom", hex: hex)
        }
        return presets.first { $0.id == id } ?? cyan
    }

    static func color(fromHex hex: String) -> Color? {
        guard let rgb = rgbComponents(fromHex: hex) else { return nil }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return defaultCustomHex }
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    static func normalizedHex(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(value)"
    }

    private static var storedPresetId: String {
        UserDefaults.standard.string(forKey: presetIdKey) ?? defaultId
    }

    private static var storedCustomHex: String {
        UserDefaults.standard.string(forKey: customHexKey) ?? defaultCustomHex
    }

    private static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let normalized = normalizedHex(hex) else { return nil }
        let digits = String(normalized.dropFirst())
        let scanner = Scanner(string: digits)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return (r, g, b)
    }
}

struct ZelefinAccentTint: ViewModifier {
    @AppStorage(AccentPreferences.presetIdKey) private var presetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customHex = AccentPreferences.defaultCustomHex

    func body(content: Content) -> some View {
        content.tint(AccentPreferences.color(id: presetId, customHex: customHex))
    }
}

extension View {
    func zelefinAccentTint() -> some View {
        modifier(ZelefinAccentTint())
    }
}

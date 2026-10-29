import SwiftUI
import UIKit

/// Named accent swatches plus an optional custom hex, stored in UserDefaults.
struct AccentPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let hex: String

    var color: Color {
        AccentPreferences.color(fromHex: hex) ?? Color(red: 153 / 255, green: 150 / 255, blue: 209 / 255)
    }
}

enum AccentPreferences {
    static let presetIdKey = "zelefin.accent-preset-id"
    static let customHexKey = "zelefin.custom-accent-hex"
    static let customId = "custom"
    static let defaultId = periwinkle.id
    static let defaultCustomHex = periwinkle.hex

    /// The sign-in screen's periwinkle, between the icon's lavender and sky. This is the default interface accent.
    static let periwinkle = AccentPreset(id: "periwinkle", name: "Periwinkle", hex: "#9996D1")
    static let cyan = AccentPreset(id: "cyan", name: "Cyan", hex: "#2AD4FC")

    static let presets: [AccentPreset] = [
        periwinkle,
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
        return presets.first { $0.id == id } ?? periwinkle
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

    static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
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

/// Dark surfaces carrying a faint wash of the accent hue.
/// Same CIELAB tone scale as Android's `accentColorScheme` neutrals (chroma 8), so both apps shift alike.
struct ZelefinSurfaces: Equatable, Sendable {
    /// Page background behind settings lists (Material `surface`, tone 6).
    let canvas: Color
    /// Grouped rows, library cards, and artwork placeholders (Material `surfaceContainerHigh`, tone 17).
    let raised: Color
    /// Text and marks on [raised] surfaces, like genre cards (Material `onSurface`, tone 90).
    let content: Color
    /// Genre card ground: a deep slate in the accent hue (`#0f172a` for a periwinkle accent).
    let genreBase: Color
    /// Genre card glow, drawn at 60% opacity (`#8485f1` for a periwinkle accent).
    let genreGlow: Color

    init(accentHex: String) {
        let lab = ZelefinSurfaces.lab(hex: accentHex)
        let angle = atan2(lab.b, lab.a)
        let accentChroma = hypot(lab.a, lab.b)
        func tone(_ l: Double, chroma: Double) -> Color {
            ZelefinSurfaces.color(l: l, a: chroma * cos(angle), b: chroma * sin(angle))
        }
        canvas = tone(6, chroma: 8)
        raised = tone(17, chroma: 8)
        content = tone(90, chroma: 8)
        // A near-grey accent keeps the genre art grey instead of inventing a hue.
        genreBase = tone(8, chroma: min(22, accentChroma))
        genreGlow = tone(59, chroma: min(68, accentChroma))
    }

    static let `default` = ZelefinSurfaces(accentHex: AccentPreferences.periwinkle.hex)

    private static let white = (x: 95.047, y: 100.0, z: 108.883)

    private static func lab(hex: String) -> (l: Double, a: Double, b: Double) {
        let rgb = AccentPreferences.rgbComponents(fromHex: hex) ?? (0.6, 0.588, 0.82)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(rgb.r), g = linear(rgb.g), bl = linear(rgb.b)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) * 100
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * bl) * 100
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) * 100
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        let fx = f(x / white.x), fy = f(y / white.y), fz = f(z / white.z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func color(l: Double, a: Double, b: Double) -> Color {
        let fy = (l + 16) / 116
        let fx = a / 500 + fy
        let fz = fy - b / 200
        func inverse(_ f: Double) -> Double { f * f * f > 0.008856 ? f * f * f : (f - 16 / 116) / 7.787 }
        let x = white.x * inverse(fx) / 100
        let y = white.y * inverse(fy) / 100
        let z = white.z * inverse(fz) / 100
        func gamma(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            return min(max(v, 0), 1)
        }
        return Color(
            red: gamma(3.2406 * x - 1.5372 * y - 0.4986 * z),
            green: gamma(-0.9689 * x + 1.8758 * y + 0.0415 * z),
            blue: gamma(0.0557 * x - 0.2040 * y + 1.0570 * z)
        )
    }
}

extension EnvironmentValues {
    @Entry var zelefinSurfaces = ZelefinSurfaces.default
}

struct ZelefinAccentTint: ViewModifier {
    @AppStorage(AccentPreferences.presetIdKey) private var presetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customHex = AccentPreferences.defaultCustomHex

    func body(content: Content) -> some View {
        let preset = AccentPreferences.preset(id: presetId, customHex: customHex)
        content
            .tint(preset.color)
            .environment(\.zelefinSurfaces, ZelefinSurfaces(accentHex: preset.hex))
            .task(id: preset.hex) {
                Self.tintWindows(UIColor(preset.color))
            }
    }

    /// UIKit controls (switches, menus, back buttons) take the window's tint, which on the Mac is the
    /// system accent unless it is set.
    @MainActor
    private static func tintWindows(_ color: UIColor) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.tintColor = color
            }
        }
    }
}

/// Accent-tinted fill for grouped list rows; apply to each `Section`.
struct ZelefinRowBackground: ViewModifier {
    @Environment(\.zelefinSurfaces) private var surfaces

    func body(content: Content) -> some View {
        content.listRowBackground(surfaces.raised)
    }
}

extension View {
    func zelefinAccentTint() -> some View {
        modifier(ZelefinAccentTint())
    }

    func zelefinRowBackground() -> some View {
        modifier(ZelefinRowBackground())
    }
}

import SwiftUI

struct SubtitleAppearanceSettingsView: View {
    @AppStorage(SubtitleAppearance.sizeKey) private var sizeRaw = SubtitleAppearance.Size.medium.rawValue
    @AppStorage(SubtitleAppearance.colorKey) private var colorRaw = SubtitleAppearance.TextColor.white.rawValue
    @AppStorage(SubtitleAppearance.backgroundKey) private var backgroundRaw = SubtitleAppearance.Background.dropShadow.rawValue
    @AppStorage(SubtitleAppearance.brightnessKey) private var brightness = 100.0
    @AppStorage(SubtitleAppearance.positionKey) private var positionLift = 0.0
    @AppStorage(SubtitleAppearance.syncKey) private var syncSeconds = 0.0

    private var size: Binding<SubtitleAppearance.Size> {
        Binding(
            get: { SubtitleAppearance.Size(rawValue: sizeRaw) ?? .medium },
            set: { sizeRaw = $0.rawValue }
        )
    }

    private var color: Binding<SubtitleAppearance.TextColor> {
        Binding(
            get: { SubtitleAppearance.TextColor(rawValue: colorRaw) ?? .white },
            set: { colorRaw = $0.rawValue }
        )
    }

    private var background: Binding<SubtitleAppearance.Background> {
        Binding(
            get: { SubtitleAppearance.Background(rawValue: backgroundRaw) ?? .dropShadow },
            set: { backgroundRaw = $0.rawValue }
        )
    }

    private var position: Binding<SubtitleAppearance.Position> {
        Binding(
            get: { positionLift > 0.5 ? .raised : .default },
            set: { positionLift = $0.liftPreset }
        )
    }

    var body: some View {
        Form {
            Section {
                SubtitleAppearancePreview(
                    size: size.wrappedValue,
                    color: color.wrappedValue,
                    background: background.wrappedValue,
                    brightness: brightness
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 112)
            } header: {
                Text("Style")
            }

            Section {
                Picker("Font Size", selection: size) {
                    ForEach(SubtitleAppearance.Size.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Text Color", selection: color) {
                    ForEach(SubtitleAppearance.TextColor.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Background", selection: background) {
                    ForEach(SubtitleAppearance.Background.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                sliderRow("Brightness", value: $brightness, range: SubtitleAppearance.brightnessRange) {
                    "\(Int(brightness.rounded()))"
                }
                Picker("Position", selection: position) {
                    ForEach(SubtitleAppearance.Position.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Slider(value: $positionLift, in: SubtitleAppearance.positionRange, step: 1)
                sliderRow("Sync", value: syncBinding, range: SubtitleAppearance.syncRange, step: SubtitleAppearance.syncStep) {
                    SubtitleAppearance.syncTitle(syncSeconds)
                }
            } footer: {
                Text("Raise captions from the bottom of the picture. Style applies to text subtitles in Zelefin’s player. Positive sync shows captions later; negative shows them earlier.")
            }
        }
        .zelefinSettingsChrome(title: "Subtitles")
        .onChange(of: brightness) { _, value in
            brightness = min(SubtitleAppearance.brightnessRange.upperBound, max(SubtitleAppearance.brightnessRange.lowerBound, value))
        }
        .onChange(of: positionLift) { _, value in
            positionLift = min(SubtitleAppearance.positionRange.upperBound, max(SubtitleAppearance.positionRange.lowerBound, value))
        }
    }

    private var syncBinding: Binding<Double> {
        Binding(
            get: { SubtitleAppearance.snappedSync(syncSeconds) },
            set: { syncSeconds = SubtitleAppearance.snappedSync($0) }
        )
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        label: () -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Text(label())
                    .font(.body.weight(.medium))
                    .foregroundStyle(LoginPalette.secondaryText)
                    .monospacedDigit()
            }
            if let step {
                Slider(value: value, in: range, step: step)
                    .tint(AccentPreferences.current)
            } else {
                Slider(value: value, in: range)
                    .tint(AccentPreferences.current)
            }
        }
    }
}

struct SubtitleAppearancePreview: View {
    var size: SubtitleAppearance.Size
    var color: SubtitleAppearance.TextColor
    var background: SubtitleAppearance.Background
    var brightness: Double

    var body: some View {
        Text("Sample subtitle text")
            .font(.system(size: 17 * size.scale, weight: .semibold))
            .multilineTextAlignment(.center)
            .modifier(SubtitleTextChrome(color: color, background: background, brightness: brightness))
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 12)
    }
}

struct SubtitleTextChrome: ViewModifier {
    var color: SubtitleAppearance.TextColor
    var background: SubtitleAppearance.Background
    var brightness: Double

    func body(content: Content) -> some View {
        let ink = SubtitleAppearance.foreground(color: color, brightness: brightness)
        switch background {
        case .none:
            content.foregroundStyle(ink)
        case .dropShadow:
            content
                .foregroundStyle(ink)
                .shadow(color: .black.opacity(0.95), radius: 2, y: 1)
                .shadow(color: .black, radius: 0, y: 1)
        case .outline:
            content
                .foregroundStyle(ink)
                .shadow(color: .black, radius: 0, x: 1, y: 0)
                .shadow(color: .black, radius: 0, x: -1, y: 0)
                .shadow(color: .black, radius: 0, x: 0, y: 1)
                .shadow(color: .black, radius: 0, x: 0, y: -1)
        case .highlight:
            content
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.62 * (brightness / 100)), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

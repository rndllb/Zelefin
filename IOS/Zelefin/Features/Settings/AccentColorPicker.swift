import SwiftUI

/// Accent swatch grid — solid tiles per preset plus a custom eyedropper slot.
struct AccentColorPickerGrid: View {
    @Binding var accentPresetId: String
    @Binding var customAccentHex: String
    var swatchSize: CGFloat = 44

    private var customColor: Color {
        AccentPreferences.color(fromHex: customAccentHex) ?? AccentPreferences.periwinkle.color
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 14
        ) {
            ForEach(AccentPreferences.presets) { preset in
                accentPresetButton(preset)
            }
            customAccentButton
        }
    }

    private func accentPresetButton(_ preset: AccentPreset) -> some View {
        Button {
            accentPresetId = preset.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    colorSwatch(fill: preset.color)
                    if accentPresetId == preset.id {
                        selectionChrome
                    }
                }
                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(accentPresetId == preset.id ? Color.white : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(accentPresetId == preset.id ? .isSelected : [])
    }

    private var customAccentButton: some View {
        Button {
            seedCustomHexFromCurrentPresetIfNeeded()
            accentPresetId = AccentPreferences.customId
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    colorSwatch(fill: customColor)
                        .overlay {
                            Image(systemName: "eyedropper.halffull")
                                .font(.system(size: swatchSize * 0.34, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        }
                    if accentPresetId == AccentPreferences.customId {
                        selectionChrome
                    }
                }
                Text("Custom")
                    .font(.caption2)
                    .foregroundStyle(
                        accentPresetId == AccentPreferences.customId ? Color.white : Color.secondary
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom")
        .accessibilityAddTraits(accentPresetId == AccentPreferences.customId ? .isSelected : [])
    }

    private func colorSwatch(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: swatchSize * 0.22, style: .continuous)
            .fill(fill)
            .frame(width: swatchSize, height: swatchSize)
    }

    private var selectionChrome: some View {
        Group {
            RoundedRectangle(cornerRadius: swatchSize * 0.22, style: .continuous)
                .strokeBorder(.white, lineWidth: 2.5)
                .frame(width: swatchSize, height: swatchSize)
            Image(systemName: "checkmark")
                .font(.system(size: swatchSize * 0.28, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    private func seedCustomHexFromCurrentPresetIfNeeded() {
        guard accentPresetId != AccentPreferences.customId else { return }
        customAccentHex = AccentPreferences.preset(id: accentPresetId).hex
    }
}

/// Color wheel + hex field shown when the custom accent preset is active.
struct CustomAccentColorControls: View {
    @Binding var accentPresetId: String
    @Binding var customAccentHex: String
    @State private var hexDraft = ""

    private var pickerColor: Binding<Color> {
        Binding(
            get: {
                AccentPreferences.color(fromHex: customAccentHex) ?? AccentPreferences.periwinkle.color
            },
            set: { newColor in
                customAccentHex = AccentPreferences.hex(from: newColor)
                accentPresetId = AccentPreferences.customId
                hexDraft = customAccentHex
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ColorPicker("Color", selection: pickerColor, supportsOpacity: false)
                .tint(AccentPreferences.color(id: accentPresetId, customHex: customAccentHex))

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(pickerColor.wrappedValue)
                    .frame(width: 36, height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)

                TextField("Hex code", text: $hexDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .onSubmit { commitHexDraft() }
                    .onChange(of: hexDraft) { _, newValue in
                        guard let normalized = AccentPreferences.normalizedHex(newValue) else { return }
                        customAccentHex = normalized
                        accentPresetId = AccentPreferences.customId
                    }
                    .accessibilityLabel("Hex code")
            }
        }
        .onAppear {
            hexDraft = customAccentHex
        }
        .onChange(of: customAccentHex) { _, newValue in
            if hexDraft != newValue {
                hexDraft = newValue
            }
        }
    }

    private func commitHexDraft() {
        if let normalized = AccentPreferences.normalizedHex(hexDraft) {
            customAccentHex = normalized
            accentPresetId = AccentPreferences.customId
            hexDraft = normalized
        } else {
            hexDraft = customAccentHex
        }
    }
}

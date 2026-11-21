import SwiftUI

/// Accent picker: live identity strip + horizontal bead rail (not a labeled swatch grid).
struct AccentColorPickerGrid: View {
    @Binding var accentPresetId: String
    @Binding var customAccentHex: String

    private var active: AccentPreset {
        AccentPreferences.preset(id: accentPresetId, customHex: customAccentHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            accentIdentity

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AccentPreferences.presets) { preset in
                        bead(preset.color, name: preset.name, selected: accentPresetId == preset.id) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                accentPresetId = preset.id
                            }
                        }
                    }
                    customBead
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
            }
            // Let the selected bead’s ring breathe past the clip.
            .padding(.horizontal, -2)
        }
    }

    private var accentIdentity: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(active.color.opacity(0.28))
                    .frame(width: 54, height: 54)
                    .blur(radius: 10)
                Circle()
                    .fill(active.color)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: active.color.opacity(0.45), radius: 10, y: 4)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(active.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(active.hex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            if accentPresetId == AccentPreferences.customId {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .foregroundStyle(active.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(active.color.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(active.color.opacity(0.22), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Accent \(active.name), \(active.hex)")
    }

    private var customBead: some View {
        let selected = accentPresetId == AccentPreferences.customId
        let fill = AccentPreferences.color(fromHex: customAccentHex) ?? AccentPreferences.periwinkle.color
        return bead(fill, name: "Custom", selected: selected, showsEyedropper: true) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                seedCustomHexFromCurrentPresetIfNeeded()
                accentPresetId = AccentPreferences.customId
            }
        }
    }

    private func bead(
        _ fill: Color,
        name: String,
        selected: Bool,
        showsEyedropper: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                    .shadow(color: selected ? fill.opacity(0.55) : .clear, radius: selected ? 8 : 0, y: 2)

                if showsEyedropper {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: selected ? 13 : 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                }

                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.9), lineWidth: 2)
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(fill.opacity(0.35), lineWidth: 5)
                        .frame(width: 42, height: 42)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func seedCustomHexFromCurrentPresetIfNeeded() {
        guard accentPresetId != AccentPreferences.customId else { return }
        customAccentHex = AccentPreferences.preset(id: accentPresetId).hex
    }
}

/// Compact custom editor — system wheel + hex chip, shown only for the Custom bead.
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

    private var activeColor: Color {
        pickerColor.wrappedValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker(selection: pickerColor, supportsOpacity: false) {
                Text(AppLanguage.string("Mix your own", default: "Mix your own"))
                    .font(.subheadline.weight(.medium))
            }
            .tint(activeColor)

            HStack(spacing: 0) {
                Text("#")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)

                TextField("RRGGBB", text: $hexDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .onSubmit { commitHexDraft() }
                    .onChange(of: hexDraft) { _, newValue in
                        let trimmed = newValue.hasPrefix("#") ? newValue : "#\(newValue)"
                        guard let normalized = AccentPreferences.normalizedHex(trimmed) else { return }
                        customAccentHex = normalized
                        accentPresetId = AccentPreferences.customId
                    }
                    .accessibilityLabel("Hex code")

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(activeColor)
                    .frame(width: 28, height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .onAppear {
            hexDraft = hexDigits(customAccentHex)
        }
        .onChange(of: customAccentHex) { _, newValue in
            let digits = hexDigits(newValue)
            if hexDraft.uppercased() != digits {
                hexDraft = digits
            }
        }
    }

    private func hexDigits(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        return value
    }

    private func commitHexDraft() {
        let candidate = hexDraft.hasPrefix("#") ? hexDraft : "#\(hexDraft)"
        if let normalized = AccentPreferences.normalizedHex(candidate) {
            customAccentHex = normalized
            accentPresetId = AccentPreferences.customId
            hexDraft = hexDigits(normalized)
        } else {
            hexDraft = hexDigits(customAccentHex)
        }
    }
}

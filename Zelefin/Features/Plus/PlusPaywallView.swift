import SwiftUI

/// Plus purchase canvas. Same black field, Z mark, card, and cyan LOGIN button as sign-in.
struct PlusPaywallView: View {
    var feature: PlusFeature?
    @Environment(PlusEntitlement.self) private var plus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedOffer = PlusProductID.annual

    var body: some View {
        ZStack {
            LoginPalette.canvas
                .ignoresSafeArea()

            LoginCanvasGlow(isRegularWidth: horizontalSizeClass == .regular)

            VStack(spacing: 0) {
                closeBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        brandBlock
                            .padding(.bottom, 28)

                        offersCard
                            .padding(.bottom, 10)

                        Text("Family Sharing is on. Annual and Lifetime unlock the same features.")
                            .font(.footnote)
                            .foregroundStyle(LoginPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 18)

                        statusText

                        VStack(spacing: 12) {
                            purchaseButton
                            restoreButton
                        }

                        includedCard
                            .padding(.top, 22)

                        Text("Sign in, browse, and Play stay free. HDR, Dolby Vision, Atmos, and 4K are not locked. Intro Skipper, Open Subtitles, Jellyfin Enhanced, Seerr, and the Zelefin notifications plugin stay free.")
                            .font(.footnote)
                            .foregroundStyle(LoginPalette.captionText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 44)
                }
            }
        }
        .tint(AccentPreferences.current)
        .preferredColorScheme(.dark)
        .onChange(of: plus.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .task {
            await plus.start()
        }
    }

    private var closeBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("CLOSE")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AccentPreferences.current)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            ConnectBrandMark(size: horizontalSizeClass == .regular ? 168 : 148)
            VStack(spacing: 8) {
                Text("Zelefin Plus")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(feature?.paywallMessage ?? plusSummary)
                    .font(.subheadline)
                    .foregroundStyle(LoginPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var offersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(PlusProductID.allCases.enumerated()), id: \.element.rawValue) { index, offer in
                if index > 0 {
                    Divider()
                        .background(LoginPalette.divider)
                }
                offerRow(offer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .modifier(LoginCardBackground())
    }

    private func offerRow(_ offer: PlusProductID) -> some View {
        let isSelected = selectedOffer == offer
        return Button {
            selectedOffer = offer
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? AccentPreferences.current : LoginPalette.iconTint)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LoginPalette.captionText)
                        .tracking(0.6)
                    Text(offer.subtitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LoginPalette.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(plus.priceLabel(for: offer))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(offer.title), \(plus.priceLabel(for: offer)), \(offer.subtitle)")
    }

    @ViewBuilder
    private var statusText: some View {
        if let error = plus.purchaseError, !error.isEmpty {
            Text(error)
                .font(.footnote.weight(.medium))
                .foregroundStyle(LoginPalette.failure)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }
    }

    private var purchaseButton: some View {
        Button {
            Task { await plus.purchase(selectedOffer) }
        } label: {
            HStack(spacing: 8) {
                if plus.isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(LoginPalette.actionLabel)
                }
                Text(plus.isPurchasing ? "PURCHASING…" : purchaseTitle)
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginActionButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(plus.isPurchasing)
        .opacity(plus.isPurchasing ? 0.42 : 1)
        .accessibilityLabel(purchaseTitle)
    }

    private var restoreButton: some View {
        Button {
            Task { await plus.restore() }
        } label: {
            HStack(spacing: 8) {
                Text("RESTORE PURCHASES")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
            }
            .modifier(LoginSecondaryButtonStyle())
        }
        .buttonStyle(.plain)
        .disabled(plus.isPurchasing)
        .opacity(plus.isPurchasing ? 0.42 : 1)
        .accessibilityLabel("Restore Purchases")
    }

    private var includedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(PlusFeature.allCases.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .background(LoginPalette.divider)
                        .padding(.leading, 52)
                }
                includedRow(item)
            }
        }
        .padding(.vertical, 6)
        .modifier(LoginCardBackground())
    }

    private func includedRow(_ item: PlusFeature) -> some View {
        let isHighlighted = item == feature
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isHighlighted ? AccentPreferences.current : LoginPalette.iconTint)
                .frame(width: 22, alignment: .center)
            Text(item.paywallTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(LoginPalette.fieldValue)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel(isHighlighted ? "\(item.paywallTitle), this feature" : item.paywallTitle)
    }

    private var purchaseTitle: String {
        switch selectedOffer {
        case .annual: "START 7-DAY TRIAL"
        case .lifetime: "GET LIFETIME"
        }
    }

    private var plusSummary: String {
        "Unlock downloads, Live TV, extra accounts, Home and tab layout, and the rest of the client. Jellyfin plugins and Seerr stay free."
    }
}

struct PlusLockedPage: View {
    let feature: PlusFeature
    @Environment(PlusEntitlement.self) private var plus
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            LoginPalette.canvas
                .ignoresSafeArea()
            LoginCanvasGlow(isRegularWidth: horizontalSizeClass == .regular)

            VStack(spacing: 18) {
                ConnectBrandMark(size: horizontalSizeClass == .regular ? 168 : 148)
                VStack(spacing: 8) {
                    Text(feature.lockTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LoginPalette.primaryText)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Text(feature.lockMessage)
                        .font(.subheadline)
                        .foregroundStyle(LoginPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    plus.request(feature)
                } label: {
                    Text("SEE PLUS")
                        .font(.caption.weight(.bold))
                        .tracking(0.9)
                        .modifier(LoginActionButtonStyle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("See Plus")
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 26)
        }
        .tint(AccentPreferences.current)
        .preferredColorScheme(.dark)
    }
}

private struct PlusPaywallPresenter: ViewModifier {
    func body(content: Content) -> some View {
        @Bindable var plus = PlusEntitlement.shared
        content
            .fullScreenCover(item: $plus.requestedFeature) { feature in
                PlusPaywallView(feature: feature)
                    .environment(plus)
            }
    }
}

extension View {
    func zelefinPlusPaywall() -> some View {
        modifier(PlusPaywallPresenter())
    }
}

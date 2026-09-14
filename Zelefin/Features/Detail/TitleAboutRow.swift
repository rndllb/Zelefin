import SwiftUI

struct TitleAboutRow: View {
    let item: MediaItem
    var onMore: () -> Void

    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    private var cards: [TitleAboutCard] {
        TitleAboutCards.cards(for: item)
    }

    private var synopsisSize: CGSize {
        PosterMetrics.aboutSynopsisCardSize.scaled(by: sidebarLayout.scale)
    }

    private var ratingSize: CGSize {
        PosterMetrics.aboutRatingCardSize.scaled(by: sidebarLayout.scale)
    }

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "About", showsChevron: false)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: PosterMetrics.rowSpacing) {
                        ForEach(cards) { card in
                            aboutCard(card)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: synopsisSize.height)
            }
        }
    }

    @ViewBuilder
    private func aboutCard(_ card: TitleAboutCard) -> some View {
        switch card {
        case let .synopsis(title, genres, overview):
            synopsisCard(title: title, genres: genres, overview: overview)
        case let .tomatometer(score, isFresh, meaning):
            ratingCard(
                icon: {
                    Image(isFresh ? "TomatometerFresh" : "TomatometerSplat")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                },
                value: "\(score)%",
                label: "TOMATOMETER",
                meaning: meaning,
                accessibilityLabel: "Rotten Tomatoes \(score) percent. \(meaning)"
            )
        case let .audience(score, meaning):
            ratingCard(
                icon: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                },
                value: score,
                label: "AUDIENCE",
                meaning: meaning,
                accessibilityLabel: "Audience score \(score). \(meaning)"
            )
        case let .commonSense(age, meaning):
            ratingCard(
                icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                        .accessibilityHidden(true)
                },
                value: age,
                label: "COMMON SENSE",
                meaning: meaning,
                accessibilityLabel: "Common Sense \(age). \(meaning)"
            )
        }
    }

    @ViewBuilder
    private func synopsisCard(title: String, genres: String?, overview: String?) -> some View {
        if let overview, !overview.isEmpty {
            Button(action: onMore) {
                synopsisCardChrome(title: title, genres: genres, overview: overview)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(title)")
            .accessibilityHint("Shows the full description")
        } else {
            synopsisCardChrome(title: title, genres: genres, overview: nil)
        }
    }

    private func synopsisCardChrome(title: String, genres: String?, overview: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let genres {
                Text(genres)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            if let overview, !overview.isEmpty {
                synopsisBody(overview)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: synopsisSize.width, height: synopsisSize.height, alignment: .topLeading)
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: PosterMetrics.aboutCardCornerRadius, style: .continuous))
    }

    private func synopsisBody(_ overview: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(overview)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, Self.cardBackground],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 36, height: 18)
                Text("MORE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
    }

    private func ratingCard<Icon: View>(
        @ViewBuilder icon: () -> Icon,
        value: String,
        label: String,
        meaning: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                icon()
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(meaning)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: ratingSize.width, height: ratingSize.height, alignment: .topLeading)
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: PosterMetrics.aboutCardCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    static let cardBackground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
}

import SwiftUI

struct TitleSpecsRow: View {
    let item: MediaItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            specsContent(spacing: 5)
            specsContent(spacing: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Title details")
    }

    @ViewBuilder
    private func specsContent(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            if let year = item.year, let runtime = item.runtimeLabel {
                specText("\(year) · \(runtime)")
            } else if let year = item.year {
                specText("\(year)")
            } else if let runtime = item.runtimeLabel {
                specText(runtime)
            }
            if let score = item.criticRating, score > 0 {
                HStack(spacing: 3) {
                    Image(score >= 60 ? "TomatometerFresh" : "TomatometerSplat")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("\(Int(score.rounded()))%")
                }
                .fixedSize()
                    .accessibilityLabel("Rotten Tomatoes \(Int(score.rounded())) percent")
            }
            if let audience = item.communityRating, audience > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                    Text(audience <= 10 ? String(format: "%.1f", audience) : "\(Int(audience.rounded()))%")
                }
                .fixedSize()
                .accessibilityLabel("Audience score")
            }
            if let age = item.ageGateLabel {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                    Text(age)
                }
                .fixedSize()
                .accessibilityLabel(age)
            }
            if let rating = item.officialRating, !rating.isEmpty {
                specBadge(rating)
            }
            if let resolution = item.videoResolution.displayName {
                specBadge(resolution)
            }
            if item.videoRange == .dolbyVision {
                Image("DolbyVisionLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                    .accessibilityLabel("Dolby Vision")
            } else if item.videoRange != .sdr {
                specBadge(item.videoRange.displayName)
            }
            if item.audioFormat == .atmos {
                Image("DolbyAtmosLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                    .accessibilityLabel("Dolby Atmos")
            }
            if item.hasClosedCaptions {
                specBadge("CC")
            }
            if item.hasAudioDescription {
                specBadge("AD")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.88))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func specText(_ value: String) -> some View {
        Text(value)
            .fixedSize()
            .layoutPriority(1)
    }

    private func specBadge(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
            .accessibilityLabel(value)
    }
}

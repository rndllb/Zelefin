import SwiftUI

struct PosterQualityBadgeStack: View {
    let item: MediaItem
    var compact = false

    private var badges: [PosterQualityBadge] {
        PosterQualityBadges.badges(for: item)
    }

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: compact ? 4 : 5) {
                ForEach(badges) { badge in
                    mark(badge)
                }
            }
            .padding(compact ? 6 : 7)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badges.map(\.accessibilityLabel).joined(separator: ", "))
        }
    }

    private func mark(_ badge: PosterQualityBadge) -> some View {
        Text(badge.title)
            .font(.system(size: compact ? 10 : 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2.5 : 3)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

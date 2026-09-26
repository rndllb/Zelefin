import SwiftUI

struct TitleAboutPage: View {
    let item: MediaItem
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(TitleMoreInfoView.sheetBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityLabel("About \(item.name)")
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear
                .frame(width: 46, height: 46)

            VStack(spacing: 3) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let genre = item.genres.first, !genre.isEmpty {
                    Text(genre)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .zelefinLiquidGlassCircle()
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

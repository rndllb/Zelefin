import SwiftUI

struct TitleMoreInfoView: View {
    let item: MediaItem
    let info: TitleMoreInfo
    var onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TitleSpecsRow(item: item)
                    if !info.information.isEmpty {
                        moreSection(title: "Information", rows: info.information)
                    }
                    if !info.languages.isEmpty {
                        moreSection(title: "Languages", rows: info.languages)
                    }
                    if !info.file.isEmpty {
                        moreSection(title: "File", rows: info.file)
                    }
                    if !info.links.isEmpty {
                        linksSection
                    }
                    if let note = info.accessibilityNote {
                        accessibilitySection(note)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Self.sheetBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    static let sheetBackground = Color(red: 32 / 255, green: 32 / 255, blue: 34 / 255)

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

    private func moreSection(title: String, rows: [TitleMoreRow]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            TitleMoreRowsList(rows: rows)
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Links")
                .font(.title2.bold())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(info.links) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Text(link.name)
                            .font(.body)
                            .foregroundStyle(.white)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accessibilitySection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Accessibility")
                .font(.title2.bold())
                .foregroundStyle(.white)
            HStack(alignment: .top, spacing: 10) {
                Text("CC")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

struct TitleFactsSection: View {
    let title: String
    let rows: [TitleMoreRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, showsChevron: false)
            TitleMoreRowsList(rows: rows)
                .padding(.horizontal, 16)
        }
    }
}

struct TitleMoreRowsList: View {
    let rows: [TitleMoreRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.48))
                    Text(row.value)
                        .font(.body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

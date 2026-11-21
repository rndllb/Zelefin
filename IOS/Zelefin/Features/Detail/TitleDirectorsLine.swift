import SwiftUI

/// “Directed by …” / “Created by …” with each name opening that person’s page.
struct TitleDirectorsLine: View {
    let people: [CreditPerson]
    var itemKind: MediaKind = .movie

    private var byline: TitleDirectors.Byline? {
        TitleDirectors.byline(from: people, itemKind: itemKind)
    }

    var body: some View {
        if let byline, !byline.people.isEmpty {
            ViewThatFits(in: .horizontal) {
                line(byline, spacing: 5)
                line(byline, spacing: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(byline.accessibilityLabel)
        }
    }

    @ViewBuilder
    private func line(_ byline: TitleDirectors.Byline, spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(byline.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
            ForEach(Array(byline.people.enumerated()), id: \.offset) { index, person in
                if index > 0 {
                    Text(separator(before: index, count: byline.people.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize()
                }
                NavigationLink {
                    PersonDetailView(
                        personID: person.id,
                        name: person.name,
                        imageTag: person.imageTag,
                        imageURL: person.imageURL
                    )
                } label: {
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .underline(true, pattern: .solid, color: .white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(person.name)
                .accessibilityHint("Opens \(person.name)’s page")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func separator(before index: Int, count: Int) -> String {
        if count == 2 { return "and" }
        if index == count - 1 { return ", and" }
        return ","
    }
}

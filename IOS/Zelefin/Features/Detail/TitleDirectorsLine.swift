import SwiftUI

/// “Directed by …” with each name opening that person’s page.
struct TitleDirectorsLine: View {
    let people: [CreditPerson]

    private var directors: [CreditPerson] {
        TitleDirectors.people(from: people)
    }

    var body: some View {
        if !directors.isEmpty {
            ViewThatFits(in: .horizontal) {
                line(spacing: 5)
                line(spacing: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(TitleDirectors.line(from: directors) ?? "Directors")
        }
    }

    @ViewBuilder
    private func line(spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text("Directed by")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize()
            ForEach(Array(directors.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Text(separator(before: index, count: directors.count))
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

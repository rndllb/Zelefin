import SwiftUI

struct TitleEnhancedExtras: View {
    let item: MediaItem
    @Environment(SessionStore.self) private var session
    @State private var reviews: [JellyfinEnhancedReview] = []
    @State private var tmdbReviews: [TMDBUserReview] = []
    @State private var awards: JellyfinEnhancedAwards?
    @State private var showsEditor = false
    @State private var errorMessage: String?

    var body: some View {
        if session.jellyfinEnhancedAvailable, JellyfinEnhancedReviewKey.target(for: item) != nil {
            VStack(alignment: .leading, spacing: 20) {
                if let awards, !awards.isEmpty {
                    TitleAwardsSection(awards: awards)
                }
                if !tmdbReviews.isEmpty {
                    TitleTMDBReviewsSection(reviews: tmdbReviews)
                }
                TitleReviewsSection(
                    currentUserID: session.session?.userID ?? "",
                    isAdministrator: session.isAdministrator,
                    reviews: reviews,
                    onWrite: { showsEditor = true },
                    onDelete: { review in
                        Task { await delete(review) }
                    }
                )
            }
            .padding(.bottom, 20)
            .task(id: "\(item.id)-\(item.tmdbID ?? 0)") { await refresh() }
            .sheet(isPresented: $showsEditor) {
                TitleReviewEditor(
                    existing: reviews.first { $0.isAuthored(by: session.session?.userID ?? "") },
                    onSave: { content, rating in
                        Task { await save(content: content, rating: rating) }
                    },
                    onDelete: {
                        if let mine = reviews.first(where: { $0.isAuthored(by: session.session?.userID ?? "") }) {
                            Task { await delete(mine) }
                        }
                    },
                    onClose: { showsEditor = false }
                )
                .presentationBackground(TitleMoreInfoView.sheetBackground)
            }
            .alert("Reviews", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func refresh() async {
        guard let client = session.client,
              let target = JellyfinEnhancedReviewKey.target(for: item)
        else { return }
        let enhanced = JellyfinEnhancedClient(client: client)
        async let fetchedReviews = enhanced.reviews(mediaType: target.mediaType, tmdbID: target.tmdbID)
        async let fetchedTMDB = enhanced.tmdbReviews(mediaType: target.mediaType, tmdbID: target.tmdbID)
        async let fetchedAwards = enhanced.awards(mediaType: target.mediaType, tmdbID: target.tmdbID)
        reviews = (try? await fetchedReviews) ?? []
        tmdbReviews = await fetchedTMDB
        awards = await fetchedAwards
    }

    private func save(content: String, rating: Double?) async {
        guard let client = session.client,
              let target = JellyfinEnhancedReviewKey.target(for: item)
        else { return }
        do {
            try await JellyfinEnhancedClient(client: client).saveReview(
                mediaType: target.mediaType,
                tmdbID: target.tmdbID,
                content: content,
                rating: rating
            )
            showsEditor = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ review: JellyfinEnhancedReview) async {
        guard let client = session.client,
              let target = JellyfinEnhancedReviewKey.target(for: item)
        else { return }
        let enhanced = JellyfinEnhancedClient(client: client)
        do {
            if review.isAuthored(by: session.session?.userID ?? "") {
                try await enhanced.deleteOwnReview(mediaType: target.mediaType, tmdbID: target.tmdbID)
            } else {
                try await enhanced.deleteReview(
                    userID: review.userID,
                    mediaType: target.mediaType,
                    tmdbID: target.tmdbID
                )
            }
            showsEditor = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TitleTMDBReviewsSection: View {
    let reviews: [TMDBUserReview]
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "TMDB Reviews", showsChevron: false)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(review.author)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            if let rating = review.rating {
                                Text(String(format: "%.0f/10", rating))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        Text(shownText(for: review))
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                        if review.content.count > 280 {
                            Button(expandedIDs.contains(review.id) ? "Show Less" : "Read More") {
                                if expandedIDs.contains(review.id) {
                                    expandedIDs.remove(review.id)
                                } else {
                                    expandedIDs.insert(review.id)
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func shownText(for review: TMDBUserReview) -> String {
        if expandedIDs.contains(review.id) || review.content.count <= 280 {
            return review.content
        }
        return String(review.content.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

struct TitleAwardsSection: View {
    let awards: JellyfinEnhancedAwards
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Awards")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(awards.summary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Awards, \(awards.summary)")
            .accessibilityHint(expanded ? "Collapse" : "Show award list")

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(awards.awards) { award in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(award.name)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                Text(award.isWin ? "Won" : "Nominated")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            HStack(spacing: 8) {
                                if let year = award.year {
                                    Text(String(year))
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.48))
                                }
                                if let detail = award.detailLine {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.48))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct TitleReviewsSection: View {
    let currentUserID: String
    let isAdministrator: Bool
    let reviews: [JellyfinEnhancedReview]
    var onWrite: () -> Void
    var onDelete: (JellyfinEnhancedReview) -> Void

    private var mine: JellyfinEnhancedReview? {
        reviews.first { $0.isAuthored(by: currentUserID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reviews", showsChevron: false)

            HStack(spacing: 12) {
                if let average = JellyfinEnhancedReview.averageRating(in: reviews) {
                    TitleStarRating(rating: average, size: 14)
                    Text(String(format: "%.1f", average))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(reviews.count == 1 ? "1 rating" : "\(reviews.count) ratings")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.48))
                } else if !reviews.isEmpty {
                    Text(reviews.count == 1 ? "1 review" : "\(reviews.count) reviews")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.48))
                } else {
                    Text("No reviews yet")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 8)
                Button(mine == nil ? "Write a Review" : "Edit Your Review") {
                    onWrite()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)

            if !reviews.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(reviews) { review in
                        reviewRow(review)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func reviewRow(_ review: JellyfinEnhancedReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(review.userName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let rating = review.rating {
                    TitleStarRating(rating: rating, size: 11)
                }
            }
            if review.hasText {
                Text(review.content)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if review.isAuthored(by: currentUserID) || isAdministrator {
                Button("Delete", role: .destructive) {
                    onDelete(review)
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }
}

struct TitleStarRating: View {
    let rating: Double
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: glyph(for: star))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("\(rating, specifier: "%.1f") out of 5 stars")
    }

    private func glyph(for star: Int) -> String {
        let filled = rating + 0.001
        if filled >= Double(star) { return "star.fill" }
        if filled >= Double(star) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct TitleReviewEditor: View {
    var existing: JellyfinEnhancedReview?
    var onSave: (String, Double?) -> Void
    var onDelete: (() -> Void)?
    var onClose: () -> Void

    @State private var content: String
    @State private var rating: Double?

    init(
        existing: JellyfinEnhancedReview?,
        onSave: @escaping (String, Double?) -> Void,
        onDelete: (() -> Void)?,
        onClose: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _content = State(initialValue: existing?.content ?? "")
        _rating = State(initialValue: existing?.rating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                tapStar(star)
                            } label: {
                                Image(systemName: glyph(for: star))
                                    .font(.title3)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(star) stars")
                        }
                        Spacer()
                        if let rating {
                            Text(rating.truncatingRemainder(dividingBy: 1) == 0
                                 ? "\(Int(rating))"
                                 : String(format: "%.1f", rating))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Review") {
                    TextField("What did you think?", text: $content, axis: .vertical)
                        .lineLimit(4...10)
                }
                if existing != nil, onDelete != nil {
                    Section {
                        Button("Delete Review", role: .destructive) {
                            onDelete?()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TitleMoreInfoView.sheetBackground)
            .navigationTitle(existing == nil ? "Write a Review" : "Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(content, rating)
                    }
                    .disabled(!JellyfinEnhancedReviewPayload.isValid(content: content, rating: rating))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func tapStar(_ star: Int) {
        let value = Double(star)
        if rating == value, star > 1 {
            rating = value - 0.5
        } else {
            rating = value
        }
    }

    private func glyph(for star: Int) -> String {
        guard let rating else { return "star" }
        if rating + 0.001 >= Double(star) { return "star.fill" }
        if rating + 0.001 >= Double(star) - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

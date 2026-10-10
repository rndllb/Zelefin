import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CatalogAlphabetIndex {
    static func sectionLetter(for text: String) -> Character {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        if first.isNumber { return "#" }
        guard first.isLetter else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let foldedFirst = folded.uppercased().first else { return "#" }
        if let scalar = foldedFirst.unicodeScalars.first, scalar.isASCII, (65...90).contains(scalar.value) {
            return foldedFirst
        }
        return "#"
    }

    static func letters(in items: [MediaItem]) -> [Character] {
        var seen = Set<Character>()
        for item in items {
            seen.insert(sectionLetter(for: item.name))
        }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return alphabet.filter(seen.contains) + (seen.contains("#") ? ["#"] : [])
    }

    static func firstItemID(for letter: Character, in items: [MediaItem]) -> String? {
        items.first { sectionLetter(for: $0.name) == letter }?.id
    }
}

extension Array where Element == MediaItem {
    func catalogLetterIndex() -> [Character: Int] {
        var map: [Character: Int] = [:]
        enumerated().forEach { position, item in
            let letter = CatalogAlphabetIndex.sectionLetter(for: item.name)
            if map[letter] == nil {
                map[letter] = position
            }
        }
        return map
    }
}

/// Trailing A–Z scrubber matching Vellum Music: drag the strip, jump instantly, stay pinned.
struct CatalogAlphabetRail: View {
    let items: [MediaItem]
    let scrollTo: (String) -> Void

    private let hitWidth: CGFloat = 40
    private let letterWidth: CGFloat = 18
    private let rowHeight: CGFloat = 14
    private let rowSpacing: CGFloat = 1
    private let trailingMargin: CGFloat = -1
    private let navBarHeight: CGFloat = 44

    @State private var selectedLetter: Character?
    @State private var lastReportedLetter: Character?

    private let deviceTopInset: CGFloat
    private let deviceBottomInset: CGFloat

    private var letters: [Character] { CatalogAlphabetIndex.letters(in: items) }

    init(items: [MediaItem], scrollTo: @escaping (String) -> Void) {
        self.items = items
        self.scrollTo = scrollTo
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene?.keyWindow ?? scene?.windows.first
        self.deviceTopInset = window?.safeAreaInsets.top ?? 0
        self.deviceBottomInset = window?.safeAreaInsets.bottom ?? 0
        #else
        self.deviceTopInset = 0
        self.deviceBottomInset = 0
        #endif
    }

    var body: some View {
        let letters = letters
        GeometryReader { geo in
            let contentTop = deviceTopInset + navBarHeight
            let contentBottom = geo.size.height - deviceBottomInset
            let contentCenterY = (contentTop + contentBottom) / 2
            let trailingX = geo.size.width - trailingMargin - letterWidth / 2
            let stackHeight = Self.stackHeight(
                count: letters.count,
                rowHeight: rowHeight,
                rowSpacing: rowSpacing
            )
            let stackOriginGlobalY = geo.frame(in: .global).minY + contentCenterY - stackHeight / 2

            VStack(spacing: rowSpacing) {
                ForEach(letters, id: \.self) { letter in
                    Text(String(letter))
                        .font(.system(size: 11, weight: selectedLetter == letter ? .bold : .semibold))
                        .foregroundStyle(
                            selectedLetter == letter
                                ? AccentPreferences.current
                                : AccentPreferences.current.opacity(0.88)
                        )
                        .frame(width: letterWidth, height: rowHeight)
                }
            }
            .frame(width: hitWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        guard let index = Self.letterIndex(
                            atGlobalY: value.location.y,
                            stackOriginGlobalY: stackOriginGlobalY,
                            count: letters.count,
                            rowHeight: rowHeight,
                            rowSpacing: rowSpacing
                        ),
                        letters.indices.contains(index) else { return }
                        select(letters[index])
                    }
                    .onEnded { _ in
                        lastReportedLetter = nil
                        selectedLetter = nil
                    }
            )
            .position(x: trailingX, y: contentCenterY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(!letters.isEmpty)
        .transaction { $0.animation = nil }
        .animation(nil, value: selectedLetter)
    }

    private func select(_ letter: Character) {
        guard lastReportedLetter != letter else { return }
        lastReportedLetter = letter
        selectedLetter = letter
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        if let id = CatalogAlphabetIndex.firstItemID(for: letter, in: items) {
            scrollTo(id)
        }
    }

    private static func stackHeight(count: Int, rowHeight: CGFloat, rowSpacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * rowSpacing
    }

    private static func letterIndex(
        atGlobalY globalY: CGFloat,
        stackOriginGlobalY: CGFloat,
        count: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> Int? {
        guard count > 0 else { return nil }
        let height = stackHeight(count: count, rowHeight: rowHeight, rowSpacing: rowSpacing)
        guard height > 0 else { return nil }
        let relativeY = globalY - stackOriginGlobalY
        guard relativeY >= 0, relativeY < height else { return nil }
        return min(count - 1, max(0, Int(relativeY / (rowHeight + rowSpacing))))
    }
}

import SwiftUI

/// Text sizes for the sheets a title's More menu opens. The Mac's text styles run about four points
/// under the phone's, which reads small at desk distance, so the Mac steps each one up.
enum TitleSheetFont {
    #if targetEnvironment(macCatalyst)
    static let row: Font = .title3
    static let detail: Font = .body
    static let note: Font = .callout
    #else
    static let row: Font = .body
    static let detail: Font = .subheadline
    static let note: Font = .footnote
    #endif
}

enum TitleSheetMetrics {
    #if targetEnvironment(macCatalyst)
    static let thumbnail = CGSize(width: 80, height: 120)
    #else
    static let thumbnail = CGSize(width: 52, height: 78)
    #endif
}

/// A sheet opened from a title's More menu: Settings' accent canvas and raised rows, an X to close,
/// and on the Mac a page sized for a computer window instead of a phone.
struct TitleSheet<Content: View>: View {
    let title: String
    var closeDisabled: Bool
    var confirmTitle: String?
    var confirmDisabled: Bool
    var onConfirm: (() -> Void)?
    var onClose: () -> Void
    let content: Content

    init(
        title: String,
        closeDisabled: Bool = false,
        confirmTitle: String? = nil,
        confirmDisabled: Bool = false,
        onConfirm: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.closeDisabled = closeDisabled
        self.confirmTitle = confirmTitle
        self.confirmDisabled = confirmDisabled
        self.onConfirm = onConfirm
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .font(TitleSheetFont.row)
                .zelefinSettingsChrome(title: title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton(action: onClose)
                            .disabled(closeDisabled)
                    }
                    if let confirmTitle, let onConfirm {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(confirmTitle, action: onConfirm)
                                .disabled(confirmDisabled)
                        }
                    }
                }
        }
        .zelefinTitleSheetSize()
    }
}

/// One row of a `TitleSheet` list: a title, an optional line under it, and optional artwork.
struct TitleSheetRow: View {
    let title: String
    var detail: String? = nil
    var detailLines = 3
    var imageURL: URL? = nil
    var showsImage = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if showsImage {
                PosterImage(url: imageURL)
                    .frame(width: TitleSheetMetrics.thumbnail.width, height: TitleSheetMetrics.thumbnail.height)
                    .posterCard(cornerRadius: 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TitleSheetFont.row.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(TitleSheetFont.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(detailLines)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// A labeled text field for a `TitleSheet` form, with the label above so long values have room.
struct TitleSheetField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TitleSheetFont.note.weight(.semibold))
                .foregroundStyle(.secondary)
            if multiline {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(5...14)
            } else {
                TextField(prompt, text: $text)
            }
        }
        .font(TitleSheetFont.row)
        .textFieldStyle(.plain)
        .padding(.vertical, 4)
    }
}

extension View {
    /// Hands a sheet the window's session and downloads again. On the Mac a sheet doesn't always inherit
    /// them, and a view inside that reads one crashes. Apply it where the sheet is presented.
    func zelefinSheetStores(_ session: SessionStore, _ downloads: DownloadStore) -> some View {
        environment(session).environment(downloads)
    }

    /// On the Mac, opens the sheet at a size meant for a computer window. Elsewhere it changes nothing.
    @ViewBuilder
    func zelefinTitleSheetSize() -> some View {
        #if targetEnvironment(macCatalyst)
        frame(minWidth: 640, idealWidth: 760, minHeight: 560, idealHeight: 760)
            .presentationSizing(.fitted)
        #else
        self
        #endif
    }
}

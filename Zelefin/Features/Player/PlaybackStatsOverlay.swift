import SwiftUI

struct PlaybackStatsOverlay: View {
    let snapshot: PlaybackStatsSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        ForEach(section.rows, id: \.label) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.label)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 88, alignment: .leading)
                                Text(row.value)
                                    .foregroundStyle(.white)
                                    #if os(iOS)
                                    .textSelection(.enabled)
                                    #endif
                            }
                            .font(.caption.monospaced())
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: 360, maxHeight: 420, alignment: .topLeading)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        }
        .padding(.leading, 16)
        .padding(.top, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct PlaybackStatsOverlay: View {
    let snapshot: PlaybackStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
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
                                            .textSelection(.enabled)
                                    }
                                    .font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: 360)
                .containerRelativeFrame(.vertical, alignment: .top) { height, _ in
                    min(420, max(160, height - 160))
                }
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                }
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .padding(.leading, 16)
        .padding(.top, 72)
        .padding(.bottom, 16)
    }
}

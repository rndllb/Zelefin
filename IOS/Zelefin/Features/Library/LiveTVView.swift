import SwiftUI
import UIKit

struct LiveTVView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    var showsBackButton = false
    @State private var section: LiveTVSection = .onNow
    @State private var programFilters: Set<LiveTVProgramFilter> = []
    @State private var showFilters = false
    @State private var channels: [LiveChannel] = []
    @State private var recordings: [LiveTVRecording] = []
    @State private var guide: [LiveGuideChannel] = []
    @State private var guideRangeStart = Date()
    @State private var guideRangeEnd = Date().addingTimeInterval(12 * 3600)
    @State private var isLoading = true
    @State private var isLoadingGuide = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var playingItem: MediaItem?

    var body: some View {
        liveTVBody
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .liveTVPageChrome(
            isPushed: showsBackButton,
            showsFilter: showsProgramFilters,
            filterButton: { filterButton }
        ) {
            if chipsInHeader {
                LiveTVChipRow(selection: $section, placement: .header)
            }
        }
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        .sheet(isPresented: $showFilters) {
            LiveTVFilterSheet(selection: $programFilters)
        }
        .presentsPlayerFromRoot($playingItem)
        .alert("Library", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private var liveTVBody: some View {
        if isLoading && channels.isEmpty && recordings.isEmpty {
            ProgressView().tint(.white)
        } else if let errorMessage, channels.isEmpty, recordings.isEmpty {
            ContentUnavailableView(
                "No Live TV",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text(errorMessage)
            )
        } else {
            loadedBody
        }
    }

    private var loadedBody: some View {
        VStack(spacing: 0) {
            if !chipsInHeader {
                LiveTVChipRow(selection: $section, placement: .page)
                .padding(.top, pageHeaderClearance + 8)
            }

            pages
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, chipsInHeader ? pageHeaderClearance : 0)
        }
    }

    @ViewBuilder
    private var pages: some View {
        switch section {
        case .onNow:
            onNowPage
        case .guide:
            guidePage
        case .channels:
            channelsPage
        case .recordings:
            recordingsPage
        }
    }

    private var chipsInHeader: Bool {
        !showsBackButton && tabBarPlacement == .sidebar
    }

    private var showsProgramFilters: Bool {
        section == .onNow || section == .guide || section == .channels
    }

    private var pageHeaderClearance: CGFloat {
        if showsBackButton { return 0 }
        if RootPageChrome.showsTitle { return RootPageChrome.headerRowHeight }
        if tabBarPlacement == .sidebar { return RootPageChrome.headerRowHeight }
        return 0
    }

    private var filterButton: some View {
        CatalogFilterButton(
            filterCount: programFilters.count,
            onFilter: { showFilters = true }
        )
        .fixedSize()
        .imageScale(.medium)
        .controlSize(.regular)
    }

    private var onNowPage: some View {
        channelListPage(
            rows: onNowRows,
            emptyTitle: "Nothing On",
            emptySymbol: "dot.radiowaves.left.and.right",
            emptyMessage: programFilters.isEmpty
                ? "Channels that are airing something will show up here."
                : "No programs match these filters."
        )
    }

    private var channelsPage: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let rows = listedChannels
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "tv",
                    description: Text(
                        programFilters.isEmpty
                            ? "Channels from this tuner will show up here."
                            : "No channels match these filters."
                    )
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: PosterGridLayout.squareColumns(for: sidebarLayout), spacing: 22) {
                        ForEach(rows) { channel in
                            LiveTVChannelCard(
                                channel: channel,
                                now: context.date,
                                artwork: session.jellyfinLibrary,
                                onPlay: { playingItem = channel.playItem }
                            )
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func channelListPage(
        rows: [LiveChannel],
        emptyTitle: String,
        emptySymbol: String,
        emptyMessage: String
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if rows.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySymbol,
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rows) { channel in
                        LiveTVNowRow(
                            channel: channel,
                            now: context.date,
                            artwork: session.jellyfinLibrary
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.black)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var onNowRows: [LiveChannel] {
        channels.filter { channel in
            guard let program = channel.currentProgram else { return false }
            return program.matches(programFilters)
        }
    }

    private var listedChannels: [LiveChannel] {
        channels.sortedByLineup().matching(programFilters: programFilters)
    }

    private var filteredGuide: [LiveGuideChannel] {
        guard !programFilters.isEmpty else { return guide }
        return guide.compactMap { row in
            let programs = row.programs.filter { $0.matches(programFilters) }
            guard !programs.isEmpty else { return nil }
            return LiveGuideChannel(channel: row.channel, programs: programs)
        }
    }

    private var guidePage: some View {
        Group {
            if isLoadingGuide && guide.isEmpty {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if guide.isEmpty {
                ContentUnavailableView(
                    "No Guide",
                    systemImage: "list.bullet.rectangle",
                    description: Text(errorMessage ?? "Program listings from this tuner will show up here.")
                )
            } else if filteredGuide.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "line.3.horizontal.decrease",
                    description: Text("No programs match these filters.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LiveTVGuideGrid(
                    rows: filteredGuide,
                    rangeStart: guideRangeStart,
                    rangeEnd: guideRangeEnd,
                    artwork: session.jellyfinLibrary,
                    onPlay: { playingItem = $0 }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: channels.map(\.id)) {
            await loadGuide()
        }
    }

    private var recordingsPage: some View {
        Group {
            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "rectangle.stack",
                    description: Text("Saved recordings from this server will show up here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: PosterGridLayout.landscapeColumns(for: sidebarLayout), spacing: 20) {
                        ForEach(recordings) { recording in
                            recordingCard(recording)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task(id: section) {
            guard section == .recordings else { return }
            await reloadRecordings()
        }
    }

    private func recordingCard(_ recording: LiveTVRecording) -> some View {
        let imageURL = session.jellyfinLibrary?.artworkURL(for: recording.item, style: .landscape)
            ?? session.jellyfinLibrary?.primaryURL(for: recording.item)
        return ZStack(alignment: .bottomTrailing) {
            Button {
                playingItem = recording.item
            } label: {
                LiveTVRecordingCard(
                    item: recording.item,
                    imageURL: imageURL,
                    isRecording: recording.isInProgress,
                    showsOverflowIcon: false
                )
            }
            .buttonStyle(.plain)

            LiveTVCoverOverflowButton(
                item: recording.item,
                showsPlay: true,
                onPlay: { playingItem = recording.item },
                onDelete: recording.isInProgress ? nil : { Task { await deleteRecording(recording) } },
                onItemChange: { updated in
                    if let index = recordings.firstIndex(where: { $0.id == updated.id }) {
                        recordings[index] = recordings[index].withItem(updated)
                    }
                }
            )
            .padding(.trailing, 2)
            .padding(.bottom, 2)
        }
    }

    private func load() async {
        guard let library = session.jellyfinLibrary else {
            isLoading = false
            errorMessage = "Sign in to watch Live TV."
            return
        }
        do {
            let enabled = try await library.liveTVInfoEnabled()
            if !enabled {
                recordings = (try? await library.liveTVRecordings()) ?? []
                channels = []
                errorMessage = recordings.isEmpty ? "Live TV is turned off on this server." : nil
                isLoading = false
                return
            }
            async let fetchedChannels = library.liveTVChannels()
            async let fetchedAiring = library.liveTVPrograms(isAiring: true, limit: 200)
            async let fetchedRecordings = library.liveTVRecordings()
            let listed = try await fetchedChannels
            channels = listed.overlaying(airing: (try? await fetchedAiring) ?? [])
            recordings = (try? await fetchedRecordings) ?? []
            errorMessage = channels.isEmpty && recordings.isEmpty
                ? "Channels and recordings from this server will show up here."
                : nil
        } catch is CancellationError {
            return
        } catch {
            if channels.isEmpty && recordings.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadGuide() async {
        guard let library = session.jellyfinLibrary, !channels.isEmpty else { return }
        isLoadingGuide = true
        defer { isLoadingGuide = false }
        let start = LiveTVGuideTimeline.slotStart(containing: Date())
        let end = start.addingTimeInterval(12 * 3600)
        guideRangeStart = start
        guideRangeEnd = end
        do {
            let programs = try await library.liveTVGuide(
                channelIDs: channels.map(\.id),
                from: start,
                to: end
            )
            let grouped = Dictionary(grouping: programs, by: \.channel.id)
            guide = channels.map { channel in
                LiveGuideChannel(
                    channel: channel,
                    programs: (grouped[channel.id] ?? []).sorted {
                        ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast)
                    }
                )
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if guide.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reloadRecordings() async {
        guard let library = session.jellyfinLibrary else { return }
        recordings = (try? await library.liveTVRecordings()) ?? recordings
    }

    private func deleteRecording(_ recording: LiveTVRecording) async {
        guard let library = session.jellyfinLibrary else { return }
        do {
            try await library.deleteLiveTVRecording(id: recording.id)
            recordings.removeAll { $0.id == recording.id }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func liveTVPageChrome<Filter: View, Center: View>(
        isPushed: Bool,
        showsFilter: Bool,
        @ViewBuilder filterButton: () -> Filter,
        @ViewBuilder center: () -> Center
    ) -> some View {
        if isPushed {
            self
                .zelefinPushedChrome(title: RootPageChrome.showsTitle ? "Live TV" : "") {
                    if showsFilter {
                        filterButton()
                    }
                }
                .zelefinScrollEdgeBlur()
        } else {
            self
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .top) {
                    FloatingPageHeader(
                        title: RootPageChrome.showsTitle ? "Live TV" : "",
                        isVisible: true,
                        liftsIntoPadTabBar: true
                    ) {
                        if showsFilter {
                            filterButton()
                        }
                    } center: {
                        center()
                    }
                }
        }
    }
}

private struct LiveTVChipRow: View {
    @Binding var selection: LiveTVSection
    var placement: Placement = .page

    enum Placement {
        case page
        case header
    }

    var body: some View {
        switch placement {
        case .page:
            chipStack
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        case .header:
            chipStack
                .fixedSize()
        }
    }

    private var chipStack: some View {
        HStack(spacing: placement == .header ? 6 : 8) {
            ForEach(LiveTVSection.allCases) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(item.title)
                        .font(placement == .header ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.92))
                        .padding(.horizontal, placement == .header ? 11 : 14)
                        .padding(.vertical, placement == .header ? 6 : 8)
                        .background(selected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LiveTVFilterSheet: View {
    @Binding var selection: Set<LiveTVProgramFilter>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Program Type") {
                    ForEach(LiveTVProgramFilter.allCases) { filter in
                        Button {
                            if selection.contains(filter) {
                                selection.remove(filter)
                            } else {
                                selection.insert(filter)
                            }
                        } label: {
                            HStack {
                                Text(filter.title)
                                    .foregroundStyle(.white)
                                Spacer()
                                if selection.contains(filter) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .zelefinRowBackground()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LiveTVNowRow: View {
    let channel: LiveChannel
    let now: Date
    let artwork: JellyfinLibraryClient?

    var body: some View {
        NavigationLink {
            if let program = channel.currentProgram {
                LiveTVProgramDetailView(program: program, playItem: channel.playItem)
            } else {
                ItemDetailView(item: channel.playItem)
            }
        } label: {
            HStack(spacing: 10) {
                PosterImage(url: artwork?.primaryURL(for: channel.item), aspectRatio: 1, contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                PosterImage(
                    url: programArt,
                    aspectRatio: 16 / 9,
                    contentMode: .fill
                )
                .frame(width: 118, height: 66)
                .posterCard(cornerRadius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.currentProgram?.name ?? channel.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if channel.currentProgram?.isOnNow(at: now) == true {
                            LiveTVOnNowBadge()
                        }
                        Text(channel.currentProgram?.startTimeLabel(at: now) ?? "Live")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    LiveTVProgressBar(progress: channel.currentProgram?.airProgress(at: now) ?? 0)
                }
            }
        }
        .buttonStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
    }

    private var programArt: URL? {
        if let program = channel.currentProgram {
            return artwork?.programStillURL(for: program.item, channel: channel.item)
        }
        return artwork?.primaryURL(for: channel.item)
    }
}

private struct LiveTVProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(4, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

private struct LiveTVOnNowBadge: View {
    @AppStorage(AccentPreferences.presetIdKey) private var accentPresetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customAccentHex = AccentPreferences.defaultCustomHex

    var body: some View {
        Text("On Now")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AccentPreferences.color(id: accentPresetId, customHex: customAccentHex), in: Capsule())
    }
}

private struct LiveTVChannelCard: View {
    let channel: LiveChannel
    let now: Date
    let artwork: JellyfinLibraryClient?
    var onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                FillingPosterCell(aspectRatio: 1) { size in
                    PosterImage(
                        url: artwork?.primaryURL(for: channel.item),
                        aspectRatio: 1,
                        contentMode: .fit,
                        fill: Color.white.opacity(0.06)
                    )
                    .padding(18)
                    .frame(width: size.width, height: size.height)
                    .background(Color.white.opacity(0.05))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "play.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.62), in: Circle())
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watch \(channel.lineupTitle)")
            .overlay(alignment: .bottomTrailing) {
                LiveTVCoverOverflowButton(
                    item: channel.currentProgram?.item ?? channel.item,
                    showsPlay: true,
                    onPlay: onPlay,
                    onItemChange: { _ in }
                )
                .padding(2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.lineupTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let program = channel.currentProgram {
                    Text(program.name)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                    if let times = program.airTimesLabel {
                        Text(times)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityCaption)
        }
    }

    private var accessibilityCaption: String {
        var parts = [channel.lineupTitle]
        if let program = channel.currentProgram {
            parts.append(program.name)
            if let times = program.airTimesLabel {
                parts.append(times)
            }
        }
        return parts.joined(separator: ", ")
    }
}

private struct LiveTVGuideGrid: View {
    let rows: [LiveGuideChannel]
    let rangeStart: Date
    let rangeEnd: Date
    let artwork: JellyfinLibraryClient?
    var onPlay: (MediaItem) -> Void

    @Environment(SessionStore.self) private var session
    @AppStorage(AccentPreferences.presetIdKey) private var accentPresetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customAccentHex = AccentPreferences.defaultCustomHex
    @State private var now = Date()
    @State private var focusedProgramID: String?
    @State private var detailChannel: LiveChannel?
    @State private var favoriteIDs: Set<String> = []
    @State private var errorMessage: String?

    private var accent: Color {
        AccentPreferences.color(id: accentPresetId, customHex: customAccentHex)
    }

    private var channelWidth: CGFloat { CGFloat(LiveTVGuideTimeline.channelColumnWidth) }
    private var rowHeight: CGFloat { CGFloat(LiveTVGuideTimeline.rowHeight) }
    private var headerHeight: CGFloat { CGFloat(LiveTVGuideTimeline.headerHeight) }
    private var rowSpacing: CGFloat { CGFloat(LiveTVGuideTimeline.rowSpacing) }
    private var timelineWidth: CGFloat {
        CGFloat(LiveTVGuideTimeline.widthPoints(from: rangeStart, to: rangeEnd))
    }
    private var nowX: CGFloat {
        CGFloat(LiveTVGuideTimeline.xPoints(start: now, rangeStart: rangeStart))
    }
    private var slotWidth: CGFloat {
        CGFloat(LiveTVGuideTimeline.pointsPerMinute * Double(LiveTVGuideTimeline.slotMinutes))
    }
    private var gridWidth: CGFloat {
        channelWidth + timelineWidth
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: rowSpacing, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                                LiveTVGuideCanvasRow(
                                    row: row,
                                    rangeStart: rangeStart,
                                    rangeEnd: rangeEnd,
                                    now: now,
                                    channelWidth: channelWidth,
                                    rowHeight: rowHeight,
                                    timelineWidth: timelineWidth,
                                    artwork: artwork,
                                    accent: accent,
                                    focusedProgramID: focusedProgramID,
                                    favoriteIDs: favoriteIDs,
                                    onOpenChannel: { detailChannel = $0 },
                                    onTapProgram: handleTap,
                                    onToggleWatchList: { program in
                                        Task { await toggleWatchList(program) }
                                    }
                                )
                        .frame(width: gridWidth, alignment: .leading)
                    }
                } header: {
                    timeHeader
                        .background(Color.black)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.bottom, 24)
            .background {
                GuideDirectionalLockInstaller()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(item: $detailChannel) { channel in
            if let program = channel.currentProgram {
                LiveTVProgramDetailView(program: program, playItem: channel.playItem)
            } else {
                ItemDetailView(item: channel.playItem)
            }
        }
        .alert("Live TV", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            seedActionState()
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            let programs = rows.flatMap(\.programs)
            favoriteIDs.formUnion(programs.filter(\.item.isFavorite).map(\.id))
        }
    }

    private func handleTap(_ program: LiveProgram) {
        guard program.isOnNow(at: now) else {
            focusedProgramID = nil
            return
        }
        if focusedProgramID == program.id {
            onPlay(program.playItem)
        } else {
            focusedProgramID = program.id
        }
    }

    private func seedActionState() {
        let programs = rows.flatMap(\.programs)
        favoriteIDs = Set(programs.filter(\.item.isFavorite).map(\.id))
    }

    private func toggleWatchList(_ program: LiveProgram) async {
        do {
            let updated = try await session.toggleFavorite(program.item)
            if updated.isFavorite {
                favoriteIDs.insert(program.id)
            } else {
                favoriteIDs.remove(program.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var timeHeader: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: channelWidth, height: headerHeight)
                ForEach(LiveTVGuideTimeline.slots(from: rangeStart, to: rangeEnd), id: \.self) { slot in
                    Text(slot.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                        .frame(width: slotWidth, alignment: .leading)
                }
            }
            if now >= rangeStart, now <= rangeEnd {
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent, in: Capsule())
                    .offset(x: channelWidth + nowX - 22)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: gridWidth, height: headerHeight, alignment: .leading)
    }
}

/// Locks a 2-axis SwiftUI `ScrollView` to one direction per gesture, matching
/// vertical rubber-banding instead of free diagonal panning.
private struct GuideDirectionalLockInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> GuideDirectionalLockView {
        GuideDirectionalLockView()
    }

    func updateUIView(_ uiView: GuideDirectionalLockView, context: Context) {
        uiView.enableLock()
    }
}

private final class GuideDirectionalLockView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        enableLock()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        enableLock()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        enableLock()
    }

    func enableLock() {
        DispatchQueue.main.async { [weak self] in
            guard let scroll = self?.nearestScrollView() else { return }
            scroll.isDirectionalLockEnabled = true
            scroll.alwaysBounceVertical = true
            scroll.alwaysBounceHorizontal = true
            scroll.bounces = true
            scroll.showsVerticalScrollIndicator = false
            scroll.showsHorizontalScrollIndicator = false
            scroll.delaysContentTouches = false
            scroll.canCancelContentTouches = true
        }
    }

    private func nearestScrollView() -> UIScrollView? {
        var node: UIView? = self
        while let current = node {
            if let scroll = current as? UIScrollView {
                return scroll
            }
            if let scroll = firstScrollView(in: current) {
                return scroll
            }
            node = current.superview
        }
        return nil
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        for child in view.subviews {
            if let scroll = child as? UIScrollView {
                return scroll
            }
            if let scroll = firstScrollView(in: child) {
                return scroll
            }
        }
        return nil
    }
}

private struct LiveTVGuideHitTarget: Identifiable {
    var id: String { program.id }
    let program: LiveProgram
    let x: CGFloat
    let width: CGFloat
}

private struct LiveTVGuideCanvasRow: View {
    let row: LiveGuideChannel
    let rangeStart: Date
    let rangeEnd: Date
    let now: Date
    let channelWidth: CGFloat
    let rowHeight: CGFloat
    let timelineWidth: CGFloat
    let artwork: JellyfinLibraryClient?
    let accent: Color
    let focusedProgramID: String?
    let favoriteIDs: Set<String>
    var onOpenChannel: (LiveChannel) -> Void
    var onTapProgram: (LiveProgram) -> Void
    var onToggleWatchList: (LiveProgram) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            channelCell
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawPrograms(context: context, size: size)
                }
                .allowsHitTesting(false)

                ForEach(hitTargets) { target in
                    Color.clear
                        .frame(width: target.width, height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTapProgram(target.program)
                        }
                        .contextMenu {
                            Button(
                                favoriteIDs.contains(target.program.id)
                                    ? "Remove from Watch List"
                                    : "Add to Watch List",
                                systemImage: favoriteIDs.contains(target.program.id) ? "checkmark" : "plus"
                            ) {
                                onToggleWatchList(target.program)
                            }
                        }
                        .offset(x: target.x)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: target.program))
                        .accessibilityHint(accessibilityHint(for: target.program))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: timelineWidth, height: rowHeight, alignment: .topLeading)
        }
        .frame(height: rowHeight)
    }

    private var hitTargets: [LiveTVGuideHitTarget] {
        row.programs.compactMap { program in
            guard let box = Self.box(for: program, rangeStart: rangeStart, rangeEnd: rangeEnd) else {
                return nil
            }
            return LiveTVGuideHitTarget(program: program, x: box.x, width: max(1, box.width))
        }
    }

    private var channelCell: some View {
        Button {
            onOpenChannel(row.channel)
        } label: {
            HStack(spacing: 8) {
                PosterImage(
                    url: artwork?.primaryURL(for: row.channel.item, maxHeight: 64),
                    aspectRatio: 1,
                    contentMode: .fit
                )
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.channel.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let number = row.channel.number {
                        Text(number)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 8)
            .frame(width: channelWidth, height: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.channel.name)
        .accessibilityHint("Shows this channel")
    }

    private func accessibilityLabel(for program: LiveProgram) -> String {
        "\(program.name), \(program.startTimeLabel(at: now))"
    }

    private func accessibilityHint(for program: LiveProgram) -> String {
        if program.isOnNow(at: now) {
            if program.id == focusedProgramID {
                return "Plays this channel live. Press and hold to add to Watch List"
            }
            return "Selects the program that is on now. Press and hold to add to Watch List"
        }
        return "Press and hold to add to Watch List"
    }

    private func drawPrograms(context: GraphicsContext, size: CGSize) {
        for program in row.programs {
            guard let box = Self.box(for: program, rangeStart: rangeStart, rangeEnd: rangeEnd) else {
                continue
            }
            let gutter: CGFloat = 3
            let rect = CGRect(
                x: box.x + gutter,
                y: 1,
                width: max(0, box.width - gutter * 2),
                height: size.height - 2
            )
            let path = Path(rect)
            let airing = program.isOnNow(at: now)
            let focused = program.id == focusedProgramID
            context.fill(path, with: .color(.white.opacity(airing ? 0.12 : 0.07)))
            if airing {
                var clipped = context
                clipped.clip(to: path)
                let progress = CGFloat(
                    LiveTVGuideTimeline.progressWidthPoints(
                        visibleStart: box.visibleStart,
                        visibleEnd: box.visibleEnd,
                        now: now
                    )
                )
                clipped.fill(
                    Path(CGRect(x: rect.minX, y: rect.minY, width: min(progress, rect.width), height: rect.height)),
                    with: .color(.white.opacity(0.22))
                )
            }
            if focused {
                context.stroke(path, with: .color(accent), lineWidth: 2.5)
            }
            let textRect = rect.insetBy(dx: 10, dy: 8)
            guard textRect.width > 8, textRect.height > 8 else { continue }
            context.draw(
                Text(program.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white),
                in: CGRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: min(20, textRect.height))
            )
            if textRect.height > 28 {
                let caption = airing
                    ? (program.remainingLabel(at: now) ?? "On Now")
                    : program.startTimeLabel(at: now)
                context.draw(
                    Text(caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.62)),
                    in: CGRect(x: textRect.minX, y: textRect.minY + 22, width: textRect.width, height: 16)
                )
            }
        }
        let playheadX = CGFloat(LiveTVGuideTimeline.xPoints(start: now, rangeStart: rangeStart))
        if playheadX >= 0, playheadX <= size.width {
            var line = Path()
            line.move(to: CGPoint(x: playheadX, y: 0))
            line.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(line, with: .color(accent), lineWidth: 2)
        }
    }

    private static func box(
        for program: LiveProgram,
        rangeStart: Date,
        rangeEnd: Date
    ) -> (x: CGFloat, width: CGFloat, visibleStart: Date, visibleEnd: Date)? {
        guard let visible = LiveTVGuideTimeline.clampedInterval(
            start: program.startDate,
            end: program.endDate,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        ) else {
            return nil
        }
        return (
            CGFloat(LiveTVGuideTimeline.xPoints(start: visible.start, rangeStart: rangeStart)),
            CGFloat(LiveTVGuideTimeline.widthPoints(from: visible.start, to: visible.end)),
            visible.start,
            visible.end
        )
    }
}

private struct LiveTVRecordingCard: View {
    let item: MediaItem
    let imageURL: URL?
    var isRecording = false
    var caption: String? = nil
    var showsOverflowIcon = true

    var body: some View {
        FillingPosterCell(aspectRatio: 16 / 9) { size in
            PosterImage(url: imageURL, aspectRatio: 16 / 9)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottom) {
                    footer
                }
                .overlay(alignment: .topTrailing) {
                    if isRecording {
                        recordingBadge
                    }
                }
                .posterCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityCaption)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.trailing, showsOverflowIcon ? 36 : 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var recordingBadge: some View {
        Image(systemName: "record.circle.fill")
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(.red, in: Circle())
            .padding(8)
            .accessibilityLabel("Recording")
    }

    private var accessibilityCaption: String {
        if isRecording {
            return "\(item.name), recording"
        }
        return item.name
    }
}

private struct LiveTVCoverOverflowButton: View {
    let item: MediaItem
    var showsPlay = true
    var onPlay: (() -> Void)?
    var onDelete: (() -> Void)?
    var onItemChange: (MediaItem) -> Void

    var body: some View {
        Menu {
            if showsPlay, let onPlay {
                Button("Play", systemImage: "play.fill", action: onPlay)
            }
            TitleUserActions(item: item, onChange: onItemChange, onDelete: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }
}

struct LiveTVProgramDetailView: View {
    let program: LiveProgram
    let playItem: MediaItem

    @Environment(SessionStore.self) private var session
    @State private var upcoming: [LiveProgram] = []
    @State private var playingItem: MediaItem?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isFavorite: Bool
    @State private var restartItem: MediaItem?
    @State private var showsMoreInfo = false
    @State private var showsAboutPage = false
    @State private var heroLock = HeroHeightLock()

    init(program: LiveProgram, playItem: MediaItem) {
        self.program = program
        self.playItem = playItem
        _isFavorite = State(initialValue: program.item.isFavorite || playItem.isFavorite)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(
                            width: geo.size.width,
                            height: heroLock.height(for: geo.size),
                            now: context.date
                        )

                        if !upcoming.isEmpty {
                            upcomingSection(now: context.date)
                                .padding(.top, 4)
                                .padding(.bottom, 20)
                        }

                        if !TitleAboutCards.cards(for: program.item).isEmpty {
                            TitleAboutRow(item: program.item) {
                                showsAboutPage = true
                            }
                            .padding(.bottom, 20)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .zelefinScrollEdgeHidden()
                .zelefinPinnedBottomEdge()
                .onAppear { heroLock.lock(geo.size) }
                .onChange(of: geo.size.width) { heroLock.lock(geo.size) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .zelefinPushedChrome(contentIgnoresTopSafeArea: true, hidesToolbarBackground: true) {
            Menu {
                if restartItem != nil {
                    Button("Restart", systemImage: "gobackward") {
                        playingItem = restartItem
                    }
                }
                Button(
                    isFavorite ? "Remove from Watch List" : "Add to Watch List",
                    systemImage: isFavorite ? "checkmark" : "plus"
                ) {
                    Task { await toggleFavorite() }
                }
                .disabled(isWorking)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: ZelefinPillMetrics.height, height: ZelefinPillMetrics.height)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .zelefinLiquidGlassCircle()
            .accessibilityLabel("More")
        }
        .tint(.white)
        .presentsPlayerFromRoot($playingItem)
        .sheet(isPresented: $showsMoreInfo) {
            TitleMoreInfoView(item: program.item, info: TitleMoreInfo()) {
                showsMoreInfo = false
            }
            .presentationBackground(TitleMoreInfoView.sheetBackground)
        }
        .sheet(isPresented: $showsAboutPage) {
            TitleAboutPage(item: program.item) {
                showsAboutPage = false
            }
            .presentationBackground(TitleMoreInfoView.sheetBackground)
        }
        .alert("Live TV", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await loadDetail() }
    }

    private func hero(width: CGFloat, height: CGFloat, now: Date) -> some View {
        VStack(spacing: 14) {
            TitleLogo(
                item: program.item,
                maxHeight: 72,
                fallbackFont: .largeTitle.bold(),
                alignment: .center
            )
            .frame(minHeight: 44)
            .shadow(color: .black.opacity(0.7), radius: 10, y: 1)

            Text(detailMetadataLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            watchLiveButton(now: now)

            if let overview = program.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    overviewBlock(overview)
                    TitleSpecsRow(item: program.item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TitleSpecsRow(item: program.item)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: width, height: height, alignment: .bottom)
        .background {
            ZStack {
                HeroArtwork(
                    url: session.jellyfinLibrary?.programStillURL(for: program.item, channel: playItem)
                        ?? session.jellyfinLibrary?.backdropURL(for: program.item),
                    placeholderURL: session.jellyfinLibrary?.primaryURL(for: playItem),
                    size: CGSize(width: width, height: height)
                )

                LinearGradient(
                    colors: [.black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .black.opacity(0.55), location: 0.58),
                        .init(color: .black.opacity(0.94), location: 0.86),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .zelefinHeroBackgroundExtension()
        }
    }

    private var detailMetadataLine: String {
        var parts = [program.item.kindLabel]
        if !program.channel.name.isEmpty {
            parts.append(program.channel.name)
        }
        parts.append(contentsOf: Array(program.item.genres.prefix(2)))
        return parts.joined(separator: " · ")
    }

    private func watchLiveButton(now: Date) -> some View {
        Button {
            playingItem = playItem
        } label: {
            HStack(spacing: PlayButtonLayout.spacing) {
                Image(systemName: "play.fill")
                    .font(PlayButtonLayout.iconFont)
                    .frame(width: PlayButtonLayout.iconWidth)

                CapsuleProgressBar(
                    progress: program.airProgress(at: now),
                    width: PlayButtonLayout.progressWidth,
                    height: PlayButtonLayout.progressHeight
                )

                Text(playButtonLabel(now: now))
                    .font(PlayButtonLayout.labelFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, PlayButtonLayout.horizontalPadding)
            .frame(width: PlayButtonLayout.minWidth, height: PlayButtonLayout.height)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("Watch Live")
        .accessibilityValue(program.remainingLabel(at: now) ?? "")
    }

    private func playButtonLabel(now: Date) -> String {
        guard program.isOnNow(at: now), let remaining = program.remainingLabel(at: now) else {
            return "Live"
        }
        if remaining.hasSuffix(" left") {
            return String(remaining.dropLast(5))
        }
        return remaining
    }

    private func overviewBlock(_ overview: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsOverviewMore(overview) ? 56 : 0)

            if showsOverviewMore(overview) {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28, height: 22)

                    Button {
                        showsMoreInfo = true
                    } label: {
                        Text("MORE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More information")
                }
            }
        }
    }

    private func showsOverviewMore(_ overview: String) -> Bool {
        overview.count > 90
    }

    private func upcomingSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Up Next on \(program.channel.name)", showsChevron: false)

            ForEach(Array(upcoming.prefix(8))) { item in
                LiveTVUpcomingRow(program: item, now: now, artwork: session.jellyfinLibrary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private enum PlayButtonLayout {
        static let spacing: CGFloat = 8
        static let iconFont: Font = .body.weight(.bold)
        static let iconWidth: CGFloat = 10
        static let progressWidth: CGFloat = 55
        static let progressHeight: CGFloat = 7
        static let labelFont: Font = .subheadline.weight(.semibold)
        static let horizontalPadding: CGFloat = 12
        static let minWidth: CGFloat = 175
        static let height: CGFloat = 45
    }

    private func loadDetail() async {
        guard let library = session.jellyfinLibrary else { return }
        let start = program.startDate ?? .now
        let end = start.addingTimeInterval(24 * 3600)
        upcoming = ((try? await library.liveTVGuide(channelIDs: [program.channel.id], from: start, to: end)) ?? [])
            .filter { $0.id != program.id }
        if let recording = (try? await library.liveTVRecordings(isInProgress: true))?.first(where: {
            $0.item.name.localizedCaseInsensitiveCompare(program.name) == .orderedSame
        }) {
            restartItem = recording.item
        }
    }

    private func toggleFavorite() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await session.toggleFavorite(program.item)
            isFavorite = updated.isFavorite
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LiveTVUpcomingRow: View {
    let program: LiveProgram
    let now: Date
    let artwork: JellyfinLibraryClient?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(
                url: artwork?.programStillURL(for: program.item, channel: program.channel),
                aspectRatio: 16 / 9,
                contentMode: .fill
            )
            .frame(width: 118, height: 66)
            .posterCard(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if program.isOnNow(at: now) {
                        LiveTVOnNowBadge()
                    }
                    Text(program.startTimeLabel(at: now))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                    if let rating = program.item.officialRating {
                        Text(rating)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(program.name), \(program.startTimeLabel(at: now))")
    }
}


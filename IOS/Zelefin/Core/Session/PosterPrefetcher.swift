import Foundation

/// Warms the on-disk caches for the Movies, Shows, and Collections tabs after Home has loaded.
/// Libraries are fetched smallest-first so a small Collections tab is ready before a huge Movies
/// library. Each catalog is snapshotted, then that library's posters download before the next
/// library starts. Later launches only fetch what is missing. Runs at background priority and
/// is cancellable. Opening a library tab also warms that catalog's posters so the open grid
/// is not waiting on a smaller library ahead of it.
enum PosterPrefetcher {
    /// The library kinds whose full catalogs get their own tab and are worth prefetching.
    static let prefetchedKinds: [LibraryKind] = [.movies, .shows, .collections]

    /// Concurrent poster downloads. Kept low so the sweep never starves on-screen posters.
    static let maxConcurrentDownloads = ArtworkNetworkGate.maxPrefetch

    static func prefetchesPosters(for kind: LibraryKind) -> Bool {
        kind != .collections
    }

    static func orderedKinds(counts: [LibraryKind: Int]) -> [LibraryKind] {
        prefetchedKinds.sorted { lhs, rhs in
            let left = counts[lhs] ?? Int.max
            let right = counts[rhs] ?? Int.max
            if left != right { return left < right }
            let order = prefetchedKinds
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    static func posterURLs(for items: [MediaItem], library: any LibraryServing) -> [URL] {
        artworkURLs(for: items, library: library)
    }

    static func artworkURLs(for items: [MediaItem], library: any LibraryServing) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for item in items {
            for url in library.cacheableArtworkURLs(for: item) where seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    static func run(
        library: any LibraryServing,
        libraries: [MediaLibrary],
        userID: String,
        serverURL: URL,
        snapshotStore: CatalogSnapshotStoring,
        cache: ArtworkCache = .shared
    ) async {
        let host = SnapshotCoding.host(from: serverURL)
        var counts: [LibraryKind: Int] = [:]
        for kind in prefetchedKinds {
            if Task.isCancelled { return }
            counts[kind] = await library.catalogCount(kind: kind, libraries: libraries)
        }

        for kind in orderedKinds(counts: counts) {
            if Task.isCancelled { return }
            let items = await library.browseCatalog(kind: kind, libraries: libraries)
            if Task.isCancelled { return }
            guard !items.isEmpty else { continue }

            snapshotStore.save(
                CatalogSnapshot(
                    version: CatalogSnapshot.currentVersion,
                    userID: userID,
                    serverHost: host,
                    libraryKind: kind,
                    savedAt: Date(),
                    items: items
                )
            )

            guard prefetchesPosters(for: kind) else { continue }
            await download(artworkURLs(for: items, library: library), cache: cache)
        }
    }

    /// Download missing posters with a bounded number in flight. `onProgress` reports
    /// cached-or-fetched count over the original URL list, including posters a visible
    /// cell already pulled from Jellyfin and wrote to disk.
    static func download(
        _ urls: [URL],
        cache: ArtworkCache = .shared,
        onProgress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async {
        let total = urls.count
        guard total > 0 else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await transfer(urls, cache: cache)
            }
            if let onProgress {
                group.addTask {
                    var last = -1
                    while !Task.isCancelled {
                        let cached = cache.settledCount(in: urls)
                        if cached != last {
                            last = cached
                            await onProgress(cached, total)
                        }
                        if cached >= total { return }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            }
            _ = await group.next()
            group.cancelAll()
            if let onProgress {
                await onProgress(total, total)
            }
        }
    }

    private static func transfer(_ urls: [URL], cache: ArtworkCache) async {
        let pending = urls.filter { !cache.isSettled(for: $0) }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: Bool.self) { group in
            var index = 0
            let seed = min(maxConcurrentDownloads, pending.count)
            while index < seed {
                let url = pending[index]
                group.addTask { await cache.prefetch(url) }
                index += 1
            }
            while index < pending.count {
                _ = await group.next()
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                let url = pending[index]
                group.addTask { await cache.prefetch(url) }
                index += 1
            }
        }
    }
}

import Foundation

enum CachePreferences {
    static let autoRefreshMissingImagesKey = "zelefin.cache.auto-refresh-missing-images"
    static let autoRefreshMissingMetadataKey = "zelefin.cache.auto-refresh-missing-metadata"

    static var autoRefreshMissingImages: Bool {
        UserDefaults.standard.bool(forKey: autoRefreshMissingImagesKey)
    }

    static var autoRefreshMissingMetadata: Bool {
        UserDefaults.standard.bool(forKey: autoRefreshMissingMetadataKey)
    }
}

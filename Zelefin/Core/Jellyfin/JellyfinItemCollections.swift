import Foundation
import Get
import JellyfinAPI

extension Paths {
    /// Jellyfin 12+: collections that include this item.
    static func getItemCollections(
        itemID: String,
        userID: String?,
        fields: [ItemFields]? = nil,
        limit: Int = 16
    ) -> Request<BaseItemDtoQueryResult> {
        var query: [(String, String?)] = [
            ("limit", "\(limit)"),
            ("enableImages", "true")
        ]
        if let userID {
            query.append(("userId", userID))
        }
        if let fields, !fields.isEmpty {
            query.append(("fields", fields.map(\.rawValue).joined(separator: ",")))
        }
        return Request(
            path: "/Items/\(itemID)/Collections",
            method: "GET",
            query: query,
            id: "GetItemCollections"
        )
    }
}

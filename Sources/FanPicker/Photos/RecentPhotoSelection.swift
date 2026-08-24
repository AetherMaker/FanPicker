#if canImport(UIKit)
import Foundation

/// One attachment selection made through FanPicker.
public struct RecentPhotoSelection: Identifiable {
    /// Unique ID for this selection event.
    public let id: UUID
    /// Selected photo asset.
    public let asset: RecentPhotoAsset

    init(id: UUID = UUID(), asset: RecentPhotoAsset) {
        self.id = id
        self.asset = asset
    }
}
#endif

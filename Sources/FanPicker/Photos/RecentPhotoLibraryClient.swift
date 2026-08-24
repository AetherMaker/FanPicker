#if canImport(UIKit)
import Foundation
import UIKit

/// A failure from a photo preview request.
public enum RecentPhotoLoadingFailure: Sendable, Equatable {
    /// The request was cancelled.
    case cancelled
    /// The asset is in iCloud and network access is disabled.
    case networkAccessRequired
    /// Photos returned an error.
    case photoLibrary(code: Int, message: String)
}

struct RecentPhotoLibraryAssetDescriptor: Sendable, Equatable {
    let id: String
    let creationDate: Date?
}

enum RecentPhotoLibraryAccess: Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}

enum RecentPhotoPreviewEvent {
    case image(UIImage, RecentPhotoImageQuality)
    case progress(Double)
    case completed(RecentPhotoLoadingFailure?)
}

@MainActor
protocol RecentPhotoLibraryClient: AnyObject {
    var accessState: RecentPhotoLibraryAccess { get }
    var onLibraryChange: (@MainActor () -> Void)? { get set }

    func requestAuthorization() async -> RecentPhotoLibraryAccess
    func fetchRecentAssets(limit: Int) -> [RecentPhotoLibraryAssetDescriptor]
    func replaceCachedAssets(
        with identifiers: [String],
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy
    )
    func requestPreview(
        for identifier: String,
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy,
        onEvent: @escaping @MainActor (RecentPhotoPreviewEvent) -> Void
    )
    func cancelPreviewRequests()
    func clearCachedImages()
    func makeResourceProvider(
        for identifier: String,
        policy: RecentPhotoImagePolicy
    ) -> any RecentPhotoResourceProvider
}
#endif

#if canImport(UIKit)
import Foundation
import Observation
import UIKit

/// Quality of an asset's display preview.
public enum RecentPhotoImageQuality: Sendable, Equatable {
    /// Temporary image shown while loading.
    case placeholder
    /// Usable preview that may be replaced by a sharper image.
    case degraded
    /// Final display preview.
    case final
}

/// A photo shown by FanPicker.
@MainActor
@Observable
public final class RecentPhotoAsset: Identifiable {
    /// Stable asset identifier.
    public let id: String
    /// Photo creation date, when available.
    public let creationDate: Date?
    /// Display preview. Do not use it as the upload resource.
    public private(set) var image: UIImage
    /// Current preview quality.
    public private(set) var imageQuality: RecentPhotoImageQuality
    /// iCloud loading progress from `0` to `1`, or `nil` when inactive.
    public private(set) var loadingProgress: Double?
    /// Failure from the latest preview request.
    public private(set) var loadingFailure: RecentPhotoLoadingFailure?

    @ObservationIgnored
    private var imageFreezeCount = 0
    @ObservationIgnored
    private var pendingImage: UIImage?
    @ObservationIgnored
    private var pendingQuality: RecentPhotoImageQuality?
    @ObservationIgnored
    private let imagePolicy: RecentPhotoImagePolicy
    @ObservationIgnored
    private let resourceProvider: (any RecentPhotoResourceProvider)?

    /// Creates an asset from a supplied preview.
    ///
    /// Pass a resource provider when the asset must support data loading or
    /// file export.
    ///
    /// - Parameters:
    ///   - id: Stable identifier for the photo.
    ///   - image: Display preview.
    ///   - creationDate: Photo creation date, when available.
    ///   - imagePolicy: Default network behavior for resource requests.
    ///   - resourceProvider: Provider for full image data and file export.
    public init(
        id: String,
        image: UIImage,
        creationDate: Date? = nil,
        imagePolicy: RecentPhotoImagePolicy = .production,
        resourceProvider: (any RecentPhotoResourceProvider)? = nil
    ) {
        self.id = id
        self.image = image
        self.creationDate = creationDate
        imageQuality = .final
        loadingProgress = nil
        loadingFailure = nil
        self.imagePolicy = imagePolicy
        self.resourceProvider = resourceProvider
    }

    /// Whether the asset has a usable display preview.
    public var isDisplayReady: Bool {
        imageQuality != .placeholder
    }

    /// Loads image data for upload or processing.
    ///
    /// - Parameters:
    ///   - version: Edited or original photo version.
    ///   - networkAccess: Override for this request, or `nil` to use the asset
    ///     policy.
    /// - Returns: Image data, type identifier, and orientation.
    /// - Throws: ``RecentPhotoResourceError`` when the resource cannot be loaded.
    public func loadImageData(
        version: RecentPhotoImageVersion = .current,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess? = nil
    ) async throws -> RecentPhotoImageData {
        guard let resourceProvider else {
            throw RecentPhotoResourceError.unavailable
        }
        return try await resourceProvider.loadImageData(
            version: version,
            networkAccess: networkAccess ?? imagePolicy.networkAccess
        )
    }

    /// Exports the selected photo to a new file.
    ///
    /// - Parameters:
    ///   - destinationURL: File URL that does not already exist.
    ///   - version: Edited or original photo version.
    ///   - networkAccess: Override for this request, or `nil` to use the asset
    ///     policy.
    /// - Returns: Details about the exported file.
    /// - Throws: ``RecentPhotoResourceError`` when the resource cannot be exported.
    public func exportResource(
        to destinationURL: URL,
        version: RecentPhotoImageVersion = .current,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess? = nil
    ) async throws -> RecentPhotoExport {
        guard let resourceProvider else {
            throw RecentPhotoResourceError.unavailable
        }
        return try await resourceProvider.exportResource(
            to: destinationURL,
            version: version,
            networkAccess: networkAccess ?? imagePolicy.networkAccess
        )
    }

    init(
        id: String,
        placeholder: UIImage,
        creationDate: Date?,
        imagePolicy: RecentPhotoImagePolicy,
        resourceProvider: any RecentPhotoResourceProvider
    ) {
        self.id = id
        image = placeholder
        self.creationDate = creationDate
        imageQuality = .placeholder
        loadingProgress = nil
        loadingFailure = nil
        self.imagePolicy = imagePolicy
        self.resourceProvider = resourceProvider
    }

    func applyPreview(
        _ image: UIImage,
        quality: RecentPhotoImageQuality
    ) {
        guard quality.rank >= imageQuality.rank else { return }
        guard imageFreezeCount == 0 else {
            if quality.rank >= (pendingQuality?.rank ?? -1) {
                pendingImage = image
                pendingQuality = quality
            }
            return
        }

        self.image = image
        imageQuality = quality
        loadingFailure = nil
        if quality == .final {
            loadingProgress = nil
        }
    }

    func applyLoadingProgress(_ progress: Double) {
        guard imageQuality != .final else { return }
        loadingProgress = min(max(progress, 0), 1)
    }

    func finishLoading(failure: RecentPhotoLoadingFailure?) {
        loadingProgress = nil
        loadingFailure = failure
    }

    func beginImageFreeze() {
        imageFreezeCount += 1
    }

    func endImageFreeze() {
        guard imageFreezeCount > 0 else { return }
        imageFreezeCount -= 1
        guard imageFreezeCount == 0,
              let pendingImage,
              let pendingQuality else {
            return
        }

        self.pendingImage = nil
        self.pendingQuality = nil
        image = pendingImage
        imageQuality = pendingQuality
        if pendingQuality == .final {
            loadingProgress = nil
        }
    }
}

private extension RecentPhotoImageQuality {
    var rank: Int {
        switch self {
        case .placeholder:
            0
        case .degraded:
            1
        case .final:
            2
        }
    }
}
#endif

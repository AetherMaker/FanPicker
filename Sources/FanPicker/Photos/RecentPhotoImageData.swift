#if canImport(UIKit)
import Foundation
import ImageIO

/// Photo version requested from Photos.
public enum RecentPhotoImageVersion: Sendable, Equatable {
    /// Current version, including edits.
    case current
    /// Original version stored by Photos.
    case original
}

/// Image data loaded for a selected photo.
public struct RecentPhotoImageData: Sendable {
    /// Encoded image bytes.
    public let data: Data
    /// Uniform type identifier reported by Photos, when available.
    public let typeIdentifier: String?
    /// Image orientation reported by Photos.
    public let orientation: CGImagePropertyOrientation

    /// Creates a loaded image value.
    public init(
        data: Data,
        typeIdentifier: String?,
        orientation: CGImagePropertyOrientation
    ) {
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.orientation = orientation
    }
}

/// Details about an exported photo file.
public struct RecentPhotoExport: Sendable, Equatable {
    /// Exported file URL.
    public let url: URL
    /// Uniform type identifier, when available.
    public let typeIdentifier: String?
    /// Original filename reported by Photos, when available.
    public let originalFilename: String?
    /// Exported file size in bytes.
    public let byteCount: Int64

    /// Creates an export result.
    public init(
        url: URL,
        typeIdentifier: String?,
        originalFilename: String?,
        byteCount: Int64
    ) {
        self.url = url
        self.typeIdentifier = typeIdentifier
        self.originalFilename = originalFilename
        self.byteCount = byteCount
    }
}

/// Error returned while loading or exporting a selected photo.
public enum RecentPhotoResourceError: Error, Sendable, Equatable {
    /// The asset or its resource provider is unavailable.
    case unavailable
    /// The request was cancelled.
    case cancelled
    /// The asset is in iCloud and network access is disabled.
    case networkAccessRequired
    /// The export destination already exists.
    case destinationExists
    /// Photos returned an error.
    case photoLibrary(code: Int, message: String)
    /// The file operation failed.
    case fileSystem(code: Int, message: String)
}

/// Supplies full image data and file exports for a selected asset.
@MainActor
public protocol RecentPhotoResourceProvider: AnyObject {
    /// Loads encoded image data.
    ///
    /// - Parameters:
    ///   - version: Edited or original photo version.
    ///   - networkAccess: Network behavior for this request.
    /// - Returns: Encoded data and image metadata.
    /// - Throws: ``RecentPhotoResourceError`` when loading fails.
    func loadImageData(
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoImageData

    /// Exports a photo to a new file.
    ///
    /// - Parameters:
    ///   - destinationURL: File URL that does not already exist.
    ///   - version: Edited or original photo version.
    ///   - networkAccess: Network behavior for this request.
    /// - Returns: Details about the exported file.
    /// - Throws: ``RecentPhotoResourceError`` when export fails.
    func exportResource(
        to destinationURL: URL,
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoExport
}
#endif

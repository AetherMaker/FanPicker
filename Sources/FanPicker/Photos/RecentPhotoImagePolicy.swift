import CoreGraphics

/// Controls preview quality and iCloud downloads.
public struct RecentPhotoImagePolicy: Sendable, Equatable {
    /// Network behavior for Photos requests.
    public enum NetworkAccess: Sendable, Equatable {
        /// Download assets from iCloud when needed.
        case allowed
        /// Use only assets available on the device.
        case localOnly
    }

    /// Network behavior for previews and selected resources.
    public var networkAccess: NetworkAccess
    /// Extra preview resolution used to protect image quality during scaling.
    public var displayOverscan: CGFloat

    /// Creates an image policy.
    ///
    /// - Parameters:
    ///   - networkAccess: Network behavior for Photos requests.
    ///   - displayOverscan: Preview resolution multiplier. Values below `1` are
    ///     clamped.
    public init(
        networkAccess: NetworkAccess = .allowed,
        displayOverscan: CGFloat = 1.15
    ) {
        self.networkAccess = networkAccess
        self.displayOverscan = displayOverscan
    }

    /// Default policy with iCloud downloads and `1.15` display overscan.
    public static let production = RecentPhotoImagePolicy()
}

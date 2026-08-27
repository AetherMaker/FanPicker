#if canImport(UIKit) && canImport(Photos)
import Photos
import UIKit

extension RecentPhotoSource {
    static func mapAuthorization(
        _ status: PHAuthorizationStatus
    ) -> AccessState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        @unknown default:
            .denied
        }
    }

    static func mapAccess(
        _ access: RecentPhotoLibraryAccess
    ) -> AccessState {
        switch access {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        }
    }

    static func previewTargetSize(
        configuration: FanPickerConfiguration,
        displayScale: CGFloat
    ) -> CGSize {
        let recentDisplaySize = configuration.recentSize * max(
            configuration.hoverScale,
            configuration.revealPeakScale,
            1
        )
        let pointSize = max(recentDisplaySize, configuration.attachmentSize)
        let scale = max(displayScale, 1)
        let overscan = max(configuration.imagePolicy.displayOverscan, 1)
        let pixels = ceil(pointSize * scale * overscan)
        return CGSize(width: pixels, height: pixels)
    }
}
#endif

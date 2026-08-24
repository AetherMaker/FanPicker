#if canImport(UIKit) && canImport(Photos)
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit

@MainActor
final class RecentPhotoImagePipeline: NSObject, RecentPhotoLibraryClient,
    PHPhotoLibraryChangeObserver {
    private final class PreviewRequestToken {
        var id = PHInvalidImageRequestID
    }

    private let manager = PHCachingImageManager()
    private var previewRequests: [PHImageRequestID: PreviewRequestToken] = [:]
    private var photoAssets: [String: PHAsset] = [:]
    var onLibraryChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    var accessState: RecentPhotoLibraryAccess {
        Self.mapAuthorization(
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
    }

    func requestAuthorization() async -> RecentPhotoLibraryAccess {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = current
        }
        return Self.mapAuthorization(status)
    }

    func fetchRecentAssets(
        limit: Int
    ) -> [RecentPhotoLibraryAssetDescriptor] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false),
        ]
        options.fetchLimit = max(limit, 0)

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var descriptors: [RecentPhotoLibraryAssetDescriptor] = []
        var fetched: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            fetched[asset.localIdentifier] = asset
            descriptors.append(
                RecentPhotoLibraryAssetDescriptor(
                    id: asset.localIdentifier,
                    creationDate: asset.creationDate
                )
            )
        }
        photoAssets = fetched
        return descriptors
    }

    func replaceCachedAssets(
        with identifiers: [String],
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy
    ) {
        manager.stopCachingImagesForAllAssets()
        let assets = identifiers.compactMap { photoAssets[$0] }
        guard !assets.isEmpty else { return }

        manager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: previewOptions(policy: policy)
        )
    }

    func requestPreview(
        for identifier: String,
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy,
        onEvent: @escaping @MainActor (RecentPhotoPreviewEvent) -> Void
    ) {
        guard let asset = photoAssets[identifier] else {
            onEvent(
                .completed(
                    .photoLibrary(code: 404, message: "Photo asset unavailable")
                )
            )
            return
        }
        let token = PreviewRequestToken()
        let options = previewOptions(policy: policy)
        options.progressHandler = { progress, _, _, _ in
            Task { @MainActor in
                onEvent(.progress(progress))
            }
        }
        let requestID = manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            Task { @MainActor in
                guard let self else { return }

                let isCancelled = info?[PHImageCancelledKey] as? Bool == true
                let error = info?[PHImageErrorKey] as? Error
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool == true
                let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool == true

                if let image, !isCancelled, error == nil {
                    onEvent(
                        .image(image, isDegraded ? .degraded : .final)
                    )
                }

                if isCancelled || error != nil || !isDegraded {
                    self.previewRequests.removeValue(forKey: token.id)
                    let failure: RecentPhotoLoadingFailure?
                    if isCancelled {
                        failure = .cancelled
                    } else if isInCloud && policy.networkAccess == .localOnly {
                        failure = .networkAccessRequired
                    } else if let error {
                        failure = Self.loadingFailure(error)
                    } else {
                        failure = nil
                    }
                    onEvent(.completed(failure))
                }
            }
        }
        token.id = requestID
        previewRequests[requestID] = token
    }

    func cancelPreviewRequests() {
        for requestID in previewRequests.keys {
            manager.cancelImageRequest(requestID)
        }
        previewRequests.removeAll()
    }

    func clearCachedImages() {
        manager.stopCachingImagesForAllAssets()
    }

    func makeResourceProvider(
        for identifier: String,
        policy _: RecentPhotoImagePolicy
    ) -> any RecentPhotoResourceProvider {
        PhotoKitRecentPhotoResourceProvider(
            identifier: identifier
        )
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.onLibraryChange?()
        }
    }

    private func previewOptions(
        policy: RecentPhotoImagePolicy
    ) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = policy.networkAccess == .allowed
        options.version = .current
        return options
    }

    private static func mapAuthorization(
        _ status: PHAuthorizationStatus
    ) -> RecentPhotoLibraryAccess {
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

    static func loadingFailure(
        _ error: Error
    ) -> RecentPhotoLoadingFailure {
        let error = error as NSError
        if error.domain == PHPhotosErrorDomain {
            if error.code == PHPhotosError.userCancelled.rawValue {
                return .cancelled
            }
            if error.code == PHPhotosError.networkAccessRequired.rawValue {
                return .networkAccessRequired
            }
        }
        return .photoLibrary(code: error.code, message: error.localizedDescription)
    }
}
#endif

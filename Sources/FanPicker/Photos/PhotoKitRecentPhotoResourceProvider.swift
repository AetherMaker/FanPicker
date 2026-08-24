#if canImport(UIKit) && canImport(Photos)
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit

@MainActor
final class PhotoKitRecentPhotoResourceProvider: RecentPhotoResourceProvider {
    private final class DataRequestToken: @unchecked Sendable {
        var id = PHInvalidImageRequestID
        var continuation: CheckedContinuation<RecentPhotoImageData, Error>?
        var isCancelled = false
        var isComplete = false
    }

    private let identifier: String
    private let imageManager = PHImageManager.default()
    private let resourceExporter = PhotoKitResourceExporter()

    init(identifier: String) {
        self.identifier = identifier
    }

    func loadImageData(
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoImageData {
        guard let asset = resolveAsset() else {
            throw RecentPhotoResourceError.unavailable
        }

        let token = DataRequestToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !token.isCancelled, !Task.isCancelled else {
                    continuation.resume(
                        throwing: RecentPhotoResourceError.cancelled
                    )
                    return
                }

                token.continuation = continuation
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .none
                options.isNetworkAccessAllowed = networkAccess == .allowed
                options.version = version.photoKitVersion

                token.id = imageManager.requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { [token] data, typeIdentifier, orientation, info in
                    Task { @MainActor [weak self, token] in
                        guard let self, !token.isComplete else { return }
                        let isCancelled = info?[PHImageCancelledKey] as? Bool
                            == true
                        let error = info?[PHImageErrorKey] as? Error
                        let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool
                            == true

                        if isCancelled {
                            finish(
                                token,
                                with: .failure(
                                    RecentPhotoResourceError.cancelled
                                )
                            )
                        } else if isInCloud && networkAccess == .localOnly {
                            finish(
                                token,
                                with: .failure(
                                    RecentPhotoResourceError.networkAccessRequired
                                )
                            )
                        } else if let error {
                            finish(
                                token,
                                with: .failure(mapPhotoResourceError(error))
                            )
                        } else if let data {
                            finish(
                                token,
                                with: .success(
                                    RecentPhotoImageData(
                                        data: data,
                                        typeIdentifier: typeIdentifier,
                                        orientation: orientation
                                    )
                                )
                            )
                        } else {
                            finish(
                                token,
                                with: .failure(
                                    RecentPhotoResourceError.unavailable
                                )
                            )
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, token] in
                guard let self, !token.isComplete else { return }
                token.isCancelled = true
                if token.id != PHInvalidImageRequestID {
                    imageManager.cancelImageRequest(token.id)
                }
                finish(
                    token,
                    with: .failure(RecentPhotoResourceError.cancelled)
                )
            }
        }
    }

    func exportResource(
        to destinationURL: URL,
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoExport {
        guard let asset = resolveAsset(),
              let resource = selectResource(for: asset, version: version) else {
            throw RecentPhotoResourceError.unavailable
        }
        return try await resourceExporter.export(
            resource,
            to: destinationURL,
            networkAccess: networkAccess
        )
    }

    private func resolveAsset() -> PHAsset? {
        PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    private func selectResource(
        for asset: PHAsset,
        version: RecentPhotoImageVersion
    ) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        switch version {
        case .current:
            return resources.first { $0.type == .fullSizePhoto }
                ?? resources.first { $0.type == .photo }
        case .original:
            return resources.first { $0.type == .photo }
                ?? resources.first { $0.type == .fullSizePhoto }
        }
    }

    private func finish(
        _ token: DataRequestToken,
        with result: Result<RecentPhotoImageData, Error>
    ) {
        guard !token.isComplete, let continuation = token.continuation else {
            return
        }
        token.isComplete = true
        token.continuation = nil
        continuation.resume(with: result)
    }
}

private extension RecentPhotoImageVersion {
    var photoKitVersion: PHImageRequestOptionsVersion {
        switch self {
        case .current:
            .current
        case .original:
            .original
        }
    }
}
#endif

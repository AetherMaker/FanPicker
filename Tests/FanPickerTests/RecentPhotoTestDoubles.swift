#if canImport(UIKit)
import Foundation
import ImageIO
import UIKit
@testable import FanPicker

@MainActor
final class MockRecentPhotoResourceProvider: RecentPhotoResourceProvider {
    var imageData = RecentPhotoImageData(
        data: Data([1, 2, 3]),
        typeIdentifier: "public.jpeg",
        orientation: .up
    )
    var imageDataError: RecentPhotoResourceError?
    var exportError: RecentPhotoResourceError?
    private(set) var loadRequests: [(
        RecentPhotoImageVersion,
        RecentPhotoImagePolicy.NetworkAccess
    )] = []
    private(set) var exportRequests: [(
        URL,
        RecentPhotoImageVersion,
        RecentPhotoImagePolicy.NetworkAccess
    )] = []

    func loadImageData(
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoImageData {
        loadRequests.append((version, networkAccess))
        if let imageDataError {
            throw imageDataError
        }
        return imageData
    }

    func exportResource(
        to destinationURL: URL,
        version: RecentPhotoImageVersion,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoExport {
        exportRequests.append((destinationURL, version, networkAccess))
        if let exportError {
            throw exportError
        }
        return RecentPhotoExport(
            url: destinationURL,
            typeIdentifier: imageData.typeIdentifier,
            originalFilename: "photo.jpg",
            byteCount: Int64(imageData.data.count)
        )
    }
}

#if canImport(Photos)
@MainActor
final class MockRecentPhotoLibraryClient: RecentPhotoLibraryClient {
    var accessState: RecentPhotoLibraryAccess
    var authorizationResult: RecentPhotoLibraryAccess
    var descriptors: [RecentPhotoLibraryAssetDescriptor]
    var onLibraryChange: (@MainActor () -> Void)?
    var resourceProviders: [String: MockRecentPhotoResourceProvider] = [:]

    private(set) var authorizationRequestCount = 0
    private(set) var fetchLimits: [Int] = []
    private(set) var cacheRequests: [(
        identifiers: [String],
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy
    )] = []
    private(set) var previewRequestIDs: [String] = []
    private(set) var cancellationCount = 0
    private(set) var cacheClearCount = 0
    private var previewCallbacks: [
        String: [@MainActor (RecentPhotoPreviewEvent) -> Void]
    ] = [:]

    init(
        accessState: RecentPhotoLibraryAccess = .authorized,
        descriptors: [RecentPhotoLibraryAssetDescriptor] = []
    ) {
        self.accessState = accessState
        authorizationResult = accessState
        self.descriptors = descriptors
    }

    func requestAuthorization() async -> RecentPhotoLibraryAccess {
        authorizationRequestCount += 1
        accessState = authorizationResult
        return authorizationResult
    }

    func fetchRecentAssets(
        limit: Int
    ) -> [RecentPhotoLibraryAssetDescriptor] {
        fetchLimits.append(limit)
        return Array(descriptors.prefix(max(limit, 0)))
    }

    func replaceCachedAssets(
        with identifiers: [String],
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy
    ) {
        cacheRequests.append((identifiers, targetSize, policy))
    }

    func requestPreview(
        for identifier: String,
        targetSize: CGSize,
        policy: RecentPhotoImagePolicy,
        onEvent: @escaping @MainActor (RecentPhotoPreviewEvent) -> Void
    ) {
        previewRequestIDs.append(identifier)
        previewCallbacks[identifier, default: []].append(onEvent)
    }

    func cancelPreviewRequests() {
        cancellationCount += 1
    }

    func clearCachedImages() {
        cacheClearCount += 1
    }

    func makeResourceProvider(
        for identifier: String,
        policy: RecentPhotoImagePolicy
    ) -> any RecentPhotoResourceProvider {
        if let provider = resourceProviders[identifier] {
            return provider
        }
        let provider = MockRecentPhotoResourceProvider()
        resourceProviders[identifier] = provider
        return provider
    }

    func send(_ event: RecentPhotoPreviewEvent, for identifier: String) {
        previewCallbacks[identifier]?.forEach { $0(event) }
    }

    func notifyLibraryChange() {
        onLibraryChange?()
    }
}
#endif
#endif

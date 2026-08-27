#if canImport(UIKit) && canImport(Photos)
import Photos
import Testing
import UIKit
@testable import FanPicker

@Suite("Recent photo source")
struct RecentPhotoSourceTests {
    @Test("Supplied photos can reveal without library access")
    @MainActor
    func suppliedPhotosCanReveal() {
        let assets = makeAssets()
        let source = RecentPhotoSource(assets: assets)

        #expect(source.canReveal)
        #expect(source.assets.map(\.id) == assets.map(\.id))
        guard case .authorized = source.accessState else {
            Issue.record("Expected supplied photos to be authorized")
            return
        }
    }

    @Test("An empty supplied source cannot reveal")
    @MainActor
    func emptySourceCannotReveal() {
        let source = RecentPhotoSource(assets: [])

        #expect(!source.canReveal)
        #expect(source.assets.isEmpty)
    }

    @Test("Library preparation leaves supplied photos unchanged")
    @MainActor
    func preparationPreservesSuppliedPhotos() async {
        let assets = makeAssets()
        let source = RecentPhotoSource(assets: assets)

        await source.preload(configuration: .reference)
        await source.prepareForUserAction(configuration: .reference)
        await source.reload(configuration: .reference)

        #expect(source.canReveal)
        #expect(!source.isLoading)
        #expect(source.assets.map(\.id) == assets.map(\.id))
    }

    @Test("PhotoKit authorization states preserve their meaning", arguments: [
        (PHAuthorizationStatus.notDetermined, RecentPhotoSource.AccessState.notDetermined),
        (.restricted, .restricted),
        (.denied, .denied),
        (.authorized, .authorized),
        (.limited, .limited),
    ])
    @MainActor
    func mapsAuthorization(
        status: PHAuthorizationStatus,
        expected: RecentPhotoSource.AccessState
    ) {
        #expect(RecentPhotoSource.mapAuthorization(status) == expected)
    }

    @Test("Preview sizing includes display scale and animation headroom")
    @MainActor
    func previewTargetUsesRenderedPixelSize() {
        let target = RecentPhotoSource.previewTargetSize(
            configuration: .reference,
            displayScale: 3
        )

        #expect(target == CGSize(width: 387, height: 387))
    }

    @Test("Preview sizing never undersamples configured display points")
    @MainActor
    func previewTargetClampsScaleAndOverscan() {
        var configuration = FanPickerConfiguration.reference
        configuration.imagePolicy.displayOverscan = 0.5

        let target = RecentPhotoSource.previewTargetSize(
            configuration: configuration,
            displayScale: 0.5
        )

        #expect(target == CGSize(width: 112, height: 112))
    }

    @Test("Preview loading upgrades degraded images to final quality")
    @MainActor
    func progressivePreviewLoading() async {
        let client = makeClient(ids: ["one"])
        let source = RecentPhotoSource(libraryClient: client)
        let degraded = UIImage()
        let final = UIImage()

        await source.preload(configuration: .reference, displayScale: 3)
        client.send(.progress(0.4), for: "one")
        client.send(.image(degraded, .degraded), for: "one")

        #expect(source.isLoading)
        #expect(source.canReveal)
        #expect(source.assets[0].image === degraded)
        #expect(source.assets[0].imageQuality == .degraded)
        #expect(source.assets[0].loadingProgress == 0.4)

        client.send(.image(final, .final), for: "one")
        client.send(.completed(nil), for: "one")

        #expect(!source.isLoading)
        #expect(source.assets[0].image === final)
        #expect(source.assets[0].imageQuality == .final)
        #expect(source.assets[0].loadingProgress == nil)
        #expect(source.loadingFailures.isEmpty)
    }

    @Test("A failed final preview preserves its usable degraded image")
    @MainActor
    func degradedPreviewSurvivesFailure() async {
        let client = makeClient(ids: ["one"])
        let source = RecentPhotoSource(libraryClient: client)
        let degraded = UIImage()
        let failure = RecentPhotoLoadingFailure.photoLibrary(
            code: 17,
            message: "Unavailable"
        )

        await source.preload(configuration: .reference)
        client.send(.image(degraded, .degraded), for: "one")
        client.send(.completed(failure), for: "one")

        #expect(!source.isLoading)
        #expect(source.canReveal)
        #expect(source.assets[0].image === degraded)
        #expect(source.assets[0].loadingFailure == failure)
        #expect(source.loadingFailures == [failure])
    }

    @Test("A slow preview does not block the scrolling reveal")
    @MainActor
    func slowPreviewDoesNotBlockScrollingReveal() async {
        let client = makeClient(ids: ["one", "two", "three", "four"])
        let source = RecentPhotoSource(libraryClient: client)
        let configuration = FanPickerConfiguration(
            scrolling: FanPickerScrollingConfiguration()
        )

        await source.preload(configuration: configuration)
        #expect(!source.canReveal)

        client.send(.image(UIImage(), .final), for: "one")
        client.send(.completed(nil), for: "one")

        #expect(source.canReveal)
        #expect(source.revealAssets.count == 4)
    }

    @Test("Local-only loading exposes a cloud download requirement")
    @MainActor
    func localOnlyCloudFailure() async {
        let client = makeClient(ids: ["cloud"])
        let source = RecentPhotoSource(libraryClient: client)

        await source.preload(configuration: .reference)
        client.send(.completed(.networkAccessRequired), for: "cloud")

        #expect(!source.canReveal)
        #expect(source.loadingFailures == [.networkAccessRequired])
    }

    @Test("Cancellation invalidates callbacks from the old load")
    @MainActor
    func cancellationInvalidatesCallbacks() async {
        let client = makeClient(ids: ["one"])
        let source = RecentPhotoSource(libraryClient: client)
        let lateImage = UIImage()

        await source.preload(configuration: .reference)
        let cancellationsBeforeStopping = client.cancellationCount
        source.cancelLoading()
        client.send(.image(lateImage, .final), for: "one")
        client.send(.completed(nil), for: "one")

        #expect(!source.isLoading)
        #expect(client.cancellationCount == cancellationsBeforeStopping + 1)
        #expect(source.assets[0].image !== lateImage)
        #expect(source.assets[0].imageQuality == .placeholder)
    }

    @Test("Preparing during an active preload does not restart it")
    @MainActor
    func preparationDoesNotRestartLoading() async {
        let client = makeClient(ids: ["one"])
        let source = RecentPhotoSource(libraryClient: client)

        await source.preload(configuration: .reference)
        await source.prepareForUserAction(configuration: .reference)

        #expect(source.isLoading)
        #expect(client.fetchLimits.count == 1)
        #expect(client.previewRequestIDs == ["one"])
    }

    @Test("Scrolling sources request previews around the visible window")
    @MainActor
    func scrollingSourceLoadsLazily() async {
        let ids = (0..<12).map { "asset-\($0)" }
        let client = makeClient(ids: ids)
        let source = RecentPhotoSource(libraryClient: client)
        var configuration = FanPickerConfiguration.reference
        configuration.scrolling = FanPickerScrollingConfiguration(
            assetLimit: 20,
            prefetchDistance: 3
        )

        await source.preload(configuration: configuration)

        #expect(client.fetchLimits == [20])
        #expect(client.previewRequestIDs == Array(ids.prefix(7)))

        source.prepareAssets(near: 8)

        #expect(client.previewRequestIDs == ids)
        #expect(client.cacheRequests.last?.identifiers == Array(ids[5...11]))
    }

    @Test("Photo library changes reload the latest assets")
    @MainActor
    func libraryChangesReloadAssets() async throws {
        let client = makeClient(ids: ["one"])
        let source = RecentPhotoSource(libraryClient: client)

        await source.preload(configuration: .reference)
        client.send(.completed(nil), for: "one")
        client.descriptors = [
            RecentPhotoLibraryAssetDescriptor(id: "two", creationDate: nil),
        ]
        client.notifyLibraryChange()
        // Poll because the reload is debounced.
        for _ in 0..<40 where client.fetchLimits.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(client.fetchLimits.count == 2)
        #expect(source.assets.map(\.id) == ["two"])
        #expect(client.previewRequestIDs == ["one", "two"])
    }

    @Test("Clearing image caches is forwarded to the library client")
    @MainActor
    func clearingCachesIsForwarded() {
        let client = makeClient(ids: [])
        let source = RecentPhotoSource(libraryClient: client)

        source.clearCachedImages()

        #expect(client.cacheClearCount == 1)
    }

    @Test("PhotoKit cloud and cancellation errors stay actionable")
    @MainActor
    func photoKitErrorsAreMapped() {
        let networkError = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.networkAccessRequired.rawValue
        )
        let cancellationError = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.userCancelled.rawValue
        )

        #expect(
            RecentPhotoImagePipeline.loadingFailure(networkError)
                == .networkAccessRequired
        )
        #expect(
            mapPhotoResourceError(networkError)
                == .networkAccessRequired
        )
        #expect(
            RecentPhotoImagePipeline.loadingFailure(cancellationError)
                == .cancelled
        )
        #expect(
            mapPhotoResourceError(cancellationError)
                == .cancelled
        )
    }

    @MainActor
    private func makeAssets() -> [RecentPhotoAsset] {
        (0..<4).map { index in
            RecentPhotoAsset(id: "asset-\(index)", image: UIImage())
        }
    }

    @MainActor
    private func makeClient(ids: [String]) -> MockRecentPhotoLibraryClient {
        MockRecentPhotoLibraryClient(
            descriptors: ids.map {
                RecentPhotoLibraryAssetDescriptor(id: $0, creationDate: nil)
            }
        )
    }
}
#endif

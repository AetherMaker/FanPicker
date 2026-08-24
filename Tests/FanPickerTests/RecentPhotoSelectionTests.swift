#if canImport(UIKit)
import Testing
import UIKit
@testable import FanPicker

@Suite("Photo selection identity")
struct RecentPhotoSelectionTests {
    @Test("Repeated selections of one asset have distinct identities")
    @MainActor
    func repeatedSelectionsAreDistinct() {
        let asset = RecentPhotoAsset(id: "asset", image: UIImage())
        let first = RecentPhotoSelection(asset: asset)
        let second = RecentPhotoSelection(asset: asset)

        #expect(first.asset.id == second.asset.id)
        #expect(first.id != second.id)
    }

    @Test("Display upgrades wait until a hero transition finishes")
    @MainActor
    func imageUpgradeWaitsForHero() {
        let initial = UIImage()
        let degraded = UIImage()
        let final = UIImage()
        let asset = RecentPhotoAsset(id: "asset", image: initial)

        asset.beginImageFreeze()
        asset.applyPreview(degraded, quality: .degraded)
        asset.applyPreview(final, quality: .final)

        #expect(asset.image === initial)
        #expect(asset.imageQuality == .final)

        asset.endImageFreeze()

        #expect(asset.image === final)
        #expect(asset.imageQuality == .final)
    }

    @Test("A degraded callback cannot replace final display quality")
    @MainActor
    func finalQualityDoesNotRegress() {
        let final = UIImage()
        let degraded = UIImage()
        let asset = RecentPhotoAsset(id: "asset", image: final)

        asset.applyPreview(degraded, quality: .degraded)

        #expect(asset.image === final)
        #expect(asset.imageQuality == .final)
    }

    @Test("Library previews progress from placeholder to final quality")
    @MainActor
    func libraryPreviewProgressesToFinal() {
        let placeholder = UIImage()
        let degraded = UIImage()
        let final = UIImage()
        let asset = RecentPhotoAsset(
            id: "asset",
            placeholder: placeholder,
            creationDate: nil,
            imagePolicy: .production,
            resourceProvider: MockRecentPhotoResourceProvider()
        )

        #expect(!asset.isDisplayReady)
        #expect(asset.imageQuality == .placeholder)

        asset.applyLoadingProgress(1.5)
        asset.applyPreview(degraded, quality: .degraded)

        #expect(asset.isDisplayReady)
        #expect(asset.image === degraded)
        #expect(asset.imageQuality == .degraded)
        #expect(asset.loadingProgress == 1)

        asset.applyPreview(final, quality: .final)

        #expect(asset.image === final)
        #expect(asset.imageQuality == .final)
        #expect(asset.loadingProgress == nil)
    }

    @Test("Supplied assets report unavailable original data")
    @MainActor
    func suppliedAssetHasNoLibraryResource() async {
        let asset = RecentPhotoAsset(id: "asset", image: UIImage())

        do {
            _ = try await asset.loadImageData()
            Issue.record("Expected supplied image data to be unavailable")
        } catch let error as RecentPhotoResourceError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Supplied assets can provide production resources")
    @MainActor
    func suppliedAssetCanProvideResources() async throws {
        let provider = MockRecentPhotoResourceProvider()
        var policy = RecentPhotoImagePolicy.production
        policy.networkAccess = .localOnly
        let asset = RecentPhotoAsset(
            id: "asset",
            image: UIImage(),
            imagePolicy: policy,
            resourceProvider: provider
        )
        let destination = URL(fileURLWithPath: "/tmp/custom-photo.jpg")

        let imageData = try await asset.loadImageData(version: .original)
        let export = try await asset.exportResource(
            to: destination,
            version: .current,
            networkAccess: .allowed
        )

        #expect(imageData.data == provider.imageData.data)
        #expect(provider.loadRequests.count == 1)
        #expect(provider.loadRequests[0].0 == .original)
        #expect(provider.loadRequests[0].1 == .localOnly)
        #expect(export.url == destination)
        #expect(provider.exportRequests.count == 1)
        #expect(provider.exportRequests[0].0 == destination)
        #expect(provider.exportRequests[0].1 == .current)
        #expect(provider.exportRequests[0].2 == .allowed)
    }
}
#endif

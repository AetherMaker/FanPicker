#if canImport(UIKit) && canImport(Photos)
import Observation
@preconcurrency import Photos
import UIKit

/// Loads recent photos and display previews.
@MainActor
@Observable
public final class RecentPhotoSource {
    /// Current photo-library permission state.
    public enum AccessState: Sendable, Equatable {
        /// The user has not made a choice.
        case notDetermined
        /// System policy blocks access.
        case restricted
        /// The user denied access.
        case denied
        /// The app can read the full photo library.
        case authorized
        /// The app can read photos selected by the user.
        case limited
    }

    /// Current photo-library permission state.
    public private(set) var accessState: AccessState
    /// Fetched assets, including previews still loading.
    public private(set) var assets: [RecentPhotoAsset]
    /// Whether preview requests are active.
    public private(set) var isLoading = false

    private enum Backend {
        case photoLibrary
        case supplied
    }

    private let backend: Backend
    private let libraryClient: (any RecentPhotoLibraryClient)?
    private var loadGeneration = UUID()
    private var assetDescriptors: [RecentPhotoLibraryAssetDescriptor] = []
    private var requestedAssetIDs: Set<String> = []
    private var pendingAssetIDs: Set<String> = []
    private var cachedRange: Range<Int>?
    private var lastConfiguration: FanPickerConfiguration?
    private var lastDisplayScale: CGFloat = 1
    private var libraryChangeTask: Task<Void, Never>?
    private var isSuspended = false

    /// Creates a source backed by the system photo library.
    public init() {
        let libraryClient = RecentPhotoImagePipeline()
        backend = .photoLibrary
        self.libraryClient = libraryClient
        assets = []
        accessState = Self.mapAccess(libraryClient.accessState)
        observeLibraryChanges()
    }

    /// Creates a source from supplied assets without photo-library access.
    ///
    /// - Parameter assets: Assets to show in their existing order.
    public init(assets: [RecentPhotoAsset]) {
        backend = .supplied
        libraryClient = nil
        self.assets = assets
        accessState = .authorized
    }

    init(libraryClient: any RecentPhotoLibraryClient) {
        backend = .photoLibrary
        self.libraryClient = libraryClient
        assets = []
        accessState = Self.mapAccess(libraryClient.accessState)
        observeLibraryChanges()
    }

    /// Whether photo access is available and at least one preview is ready.
    public var canReveal: Bool {
        !revealAssets.isEmpty
            && (accessState == .authorized || accessState == .limited)
    }

    /// Failures from the current preview requests.
    public var loadingFailures: [RecentPhotoLoadingFailure] {
        assets.compactMap(\.loadingFailure)
    }
}

extension RecentPhotoSource {
    /// Loads previews when photo access is already available.
    ///
    /// This method does not request permission.
    ///
    /// - Parameters:
    ///   - configuration: Picker configuration used to size previews.
    ///   - displayScale: Current display scale.
    public func preload(
        configuration: FanPickerConfiguration,
        displayScale: CGFloat = 1
    ) async {
        lastConfiguration = configuration
        lastDisplayScale = displayScale
        guard case .photoLibrary = backend, let libraryClient else { return }
        isSuspended = false
        accessState = Self.mapAccess(libraryClient.accessState)
        guard accessState == .authorized || accessState == .limited else { return }
        await reload(
            configuration: configuration,
            displayScale: displayScale
        )
    }

    /// Requests permission when needed, then loads previews.
    ///
    /// Call this in response to a user action.
    ///
    /// - Parameters:
    ///   - configuration: Picker configuration used to size previews.
    ///   - displayScale: Current display scale.
    public func prepareForUserAction(
        configuration: FanPickerConfiguration,
        displayScale: CGFloat = 1
    ) async {
        lastConfiguration = configuration
        lastDisplayScale = displayScale
        guard case .photoLibrary = backend, let libraryClient else { return }
        isSuspended = false
        accessState = Self.mapAccess(await libraryClient.requestAuthorization())
        guard accessState == .authorized || accessState == .limited else { return }
        guard !isLoading else { return }
        await reload(
            configuration: configuration,
            displayScale: displayScale
        )
    }

    /// Fetches the latest assets and reloads their previews.
    ///
    /// - Parameters:
    ///   - configuration: Picker configuration used to size previews.
    ///   - displayScale: Current display scale.
    public func reload(
        configuration: FanPickerConfiguration,
        displayScale: CGFloat = 1
    ) async {
        guard case .photoLibrary = backend, let libraryClient else { return }

        let generation = beginReload(
            configuration: configuration,
            displayScale: displayScale,
            libraryClient: libraryClient
        )
        let fetchedAssets = libraryClient.fetchRecentAssets(
            limit: configuration.scrolling?.resolvedAssetLimit
                ?? configuration.itemCount
        )
        assetDescriptors = fetchedAssets

        let targetSize = Self.previewTargetSize(
            configuration: configuration,
            displayScale: displayScale
        )

        let placeholder = RecentPhotoPlaceholder.image(size: targetSize)
        let loaded = fetchedAssets.map { asset in
            RecentPhotoAsset(
                id: asset.id,
                placeholder: placeholder,
                creationDate: asset.creationDate,
                imagePolicy: configuration.imagePolicy,
                resourceProvider: libraryClient.makeResourceProvider(
                    for: asset.id,
                    policy: configuration.imagePolicy
                )
            )
        }
        assets = loaded
        guard !fetchedAssets.isEmpty else {
            isLoading = false
            return
        }

        let initialCount = min(
            fetchedAssets.count,
            max(
                configuration.itemCount
                    + (configuration.scrolling?.resolvedPrefetchDistance ?? 0),
                configuration.itemCount
            )
        )
        requestPreviews(
            in: 0..<initialCount,
            generation: generation,
            configuration: configuration,
            targetSize: targetSize
        )
    }

    func prepareAssets(near index: Int) {
        guard case .photoLibrary = backend,
              let configuration = lastConfiguration,
              let scrolling = configuration.scrolling,
              !assetDescriptors.isEmpty else {
            return
        }

        let safeIndex = min(max(index, 0), assetDescriptors.count - 1)
        let lowerBound = max(safeIndex - scrolling.resolvedPrefetchDistance, 0)
        let upperBound = min(
            safeIndex + scrolling.resolvedPrefetchDistance + 1,
            assetDescriptors.count
        )
        let range = lowerBound..<upperBound
        let targetSize = Self.previewTargetSize(
            configuration: configuration,
            displayScale: lastDisplayScale
        )
        updateCachedRange(
            range,
            targetSize: targetSize,
            configuration: configuration
        )
        requestPreviews(
            in: range,
            generation: loadGeneration,
            configuration: configuration,
            targetSize: targetSize
        )
    }
}

private extension RecentPhotoSource {
    func beginReload(
        configuration: FanPickerConfiguration,
        displayScale: CGFloat,
        libraryClient: any RecentPhotoLibraryClient
    ) -> UUID {
        lastConfiguration = configuration
        lastDisplayScale = displayScale
        isLoading = true
        loadGeneration = UUID()
        libraryClient.cancelPreviewRequests()
        assetDescriptors.removeAll()
        requestedAssetIDs.removeAll()
        pendingAssetIDs.removeAll()
        cachedRange = nil
        return loadGeneration
    }

    private func requestPreviews(
        in range: Range<Int>,
        generation: UUID,
        configuration: FanPickerConfiguration,
        targetSize: CGSize
    ) {
        guard let libraryClient else { return }
        let safeRange = range.clamped(to: assetDescriptors.indices)
        guard !safeRange.isEmpty else {
            isLoading = !pendingAssetIDs.isEmpty
            return
        }

        updateCachedRange(
            safeRange,
            targetSize: targetSize,
            configuration: configuration
        )

        for index in safeRange {
            let photoAsset = assetDescriptors[index]
            guard requestedAssetIDs.insert(photoAsset.id).inserted else { continue }
            let displayAsset = assets[index]
            pendingAssetIDs.insert(photoAsset.id)
            isLoading = true
            libraryClient.requestPreview(
                for: photoAsset.id,
                targetSize: targetSize,
                policy: configuration.imagePolicy
            ) { [weak self, weak displayAsset] event in
                guard let self,
                      let displayAsset,
                      loadGeneration == generation else {
                    return
                }

                switch event {
                case let .image(image, quality):
                    displayAsset.applyPreview(image, quality: quality)
                case let .progress(progress):
                    displayAsset.applyLoadingProgress(progress)
                case let .completed(failure):
                    displayAsset.finishLoading(failure: failure)
                    pendingAssetIDs.remove(photoAsset.id)
                    if pendingAssetIDs.isEmpty {
                        isLoading = false
                    }
                }
            }
        }
        isLoading = !pendingAssetIDs.isEmpty
    }

    private func updateCachedRange(
        _ range: Range<Int>,
        targetSize: CGSize,
        configuration: FanPickerConfiguration
    ) {
        guard cachedRange != range, let libraryClient else { return }
        cachedRange = range
        libraryClient.replaceCachedAssets(
            with: range.map { assetDescriptors[$0].id },
            targetSize: targetSize,
            policy: configuration.imagePolicy
        )
    }
}

extension RecentPhotoSource {
    /// Cancels preview requests and automatic library reloads.
    public func cancelLoading() {
        guard case .photoLibrary = backend else { return }
        isSuspended = true
        libraryChangeTask?.cancel()
        libraryChangeTask = nil
        loadGeneration = UUID()
        requestedAssetIDs.removeAll()
        pendingAssetIDs.removeAll()
        cachedRange = nil
        isLoading = false
        libraryClient?.cancelPreviewRequests()
    }

    /// Stops PhotoKit image caching for this source.
    public func clearCachedImages() {
        guard case .photoLibrary = backend else { return }
        libraryClient?.clearCachedImages()
    }
}

private extension RecentPhotoSource {
    private func observeLibraryChanges() {
        libraryClient?.onLibraryChange = { [weak self] in
            self?.scheduleLibraryReload()
        }
    }

    private func scheduleLibraryReload() {
        guard !isSuspended, let lastConfiguration else { return }
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            await reload(
                configuration: lastConfiguration,
                displayScale: lastDisplayScale
            )
        }
    }
}

extension RecentPhotoSource {
    var revealAssets: [RecentPhotoAsset] {
        guard let configuration = lastConfiguration,
              configuration.scrolling != nil else {
            return assets.filter(\.isDisplayReady)
        }
        let initialCount = min(max(configuration.itemCount, 0), assets.count)
        // Do not let one slow preview block the initial fan.
        guard initialCount > 0,
              assets.prefix(initialCount).contains(where: \.isDisplayReady) else {
            return []
        }
        return assets
    }
}

private extension Range where Bound == Int {
    func clamped(to bounds: Range<Int>) -> Range<Int> {
        let lower = Swift.max(lowerBound, bounds.lowerBound)
        let upper = Swift.max(
            Swift.min(upperBound, bounds.upperBound),
            lower
        )
        return lower..<upper
    }
}
#endif

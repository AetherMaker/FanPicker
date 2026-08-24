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
    private var pendingAssetIDs: Set<String> = []
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

        lastConfiguration = configuration
        lastDisplayScale = displayScale
        isLoading = true
        loadGeneration = UUID()
        let generation = loadGeneration
        libraryClient.cancelPreviewRequests()
        pendingAssetIDs.removeAll()
        let fetchedAssets = libraryClient.fetchRecentAssets(
            limit: configuration.itemCount
        )

        let targetSize = Self.previewTargetSize(
            configuration: configuration,
            displayScale: displayScale
        )

        libraryClient.replaceCachedAssets(
            with: fetchedAssets.map(\.id),
            targetSize: targetSize,
            policy: configuration.imagePolicy
        )

        let placeholder = placeholderImage(size: targetSize)
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
        pendingAssetIDs = Set(fetchedAssets.map(\.id))
        guard !pendingAssetIDs.isEmpty else {
            isLoading = false
            return
        }

        for (photoAsset, displayAsset) in zip(fetchedAssets, loaded) {
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
    }

    /// Cancels preview requests and automatic library reloads.
    public func cancelLoading() {
        guard case .photoLibrary = backend else { return }
        isSuspended = true
        libraryChangeTask?.cancel()
        libraryChangeTask = nil
        loadGeneration = UUID()
        pendingAssetIDs.removeAll()
        isLoading = false
        libraryClient?.cancelPreviewRequests()
    }

    /// Stops PhotoKit image caching for this source.
    public func clearCachedImages() {
        guard case .photoLibrary = backend else { return }
        libraryClient?.clearCachedImages()
    }

    private func placeholderImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            let symbolSize = min(size.width, size.height) * 0.28
            let configuration = UIImage.SymbolConfiguration(
                pointSize: symbolSize,
                weight: .regular
            )
            guard let symbol = UIImage(
                systemName: "photo",
                withConfiguration: configuration
            )?.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) else {
                return
            }
            symbol.draw(
                at: CGPoint(
                    x: (size.width - symbol.size.width) / 2,
                    y: (size.height - symbol.size.height) / 2
                )
            )
        }
    }

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

    private static func mapAccess(
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

    var revealAssets: [RecentPhotoAsset] {
        assets.filter(\.isDisplayReady)
    }
}
#endif

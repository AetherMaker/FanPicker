#if canImport(UIKit)
import SwiftUI
import UIKit

/// Values and views used to build your composer.
public struct RecentPhotoPickerContext {
    /// Whether the recent-photo interaction is open or closing.
    public let isActive: Bool
    /// Whether photo previews are loading.
    public let isLoadingPhotos: Bool
    /// Preview requests that did not complete.
    public let photoLoadingFailures: [RecentPhotoLoadingFailure]
    /// Marks where FanPicker renders its `+`/`X` button.
    public let trigger: RecentPhotoTrigger

    let attachmentNamespace: Namespace.ID
    let attachmentTransition: AttachmentTransitionSession?
    let configuration: FanPickerConfiguration
    let onAttachmentDestinationReady: (UUID) -> Void

    /// Returns `true` while an attachment flight is being prepared or running.
    public func isTransitioningAttachment(id: UUID) -> Bool {
        attachmentTransition?.id == id
    }

    /// Whether a selected photo is flying into the composer.
    /// Open custom composer clipping while this is `true`.
    public var isAttachingPhoto: Bool {
        attachmentTransition != nil
    }

    func isStagingAttachment(id: UUID) -> Bool {
        attachmentTransition?.id == id
            && attachmentTransition?.phase == .staged
    }

    func attachmentDestinationReady(id: UUID) {
        onAttachmentDestinationReady(id)
    }
}

/// Adds the recent-photo interaction to your composer.
@MainActor
public struct RecentPhotoQuickPicker<Composer: View>: View {
    private let configuration: FanPickerConfiguration
    private let onTapTrigger: () -> Void
    private let onPhotoLoading: () -> Void
    private let onPhotoAccessUnavailable: (RecentPhotoSource.AccessState) -> Void
    private let isSelectionAllowed: (RecentPhotoAsset) -> Bool
    private let onSelect: (RecentPhotoSelection) -> Void
    private let onScrollLockChanged: (Bool) -> Void
    private let composer: (RecentPhotoPickerContext) -> Composer

    @State private var source: RecentPhotoSource
    @State private var controller = FanPickerController()
    @State private var attachmentTransition: AttachmentTransitionSession?
    @State private var permissionRequestID: UUID?
    @State private var photoLoadingFeedbackToken = 0
    @State private var isTriggerPressed = false
    @State private var resolvedGeometry = ResolvedFanPickerGeometry()
    @State private var scrollingRow = ScrollableRecentRowController()
    @Namespace private var attachmentNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    /// Creates a recent-photo picker around your composer.
    ///
    /// - Parameters:
    ///   - configuration: Sizes, timing values, and image policy.
    ///   - source: Photo source. Pass `nil` to use the system photo library.
    ///   - onTapTrigger: Runs when the closed `+` button is tapped.
    ///   - onPhotoLoading: Runs when a hold occurs before previews are ready.
    ///   - onPhotoAccessUnavailable: Runs when photo access is denied or
    ///     restricted.
    ///   - isSelectionAllowed: Decides whether an asset can be selected.
    ///   - onSelect: Runs after selection. Add the value to your attachment
    ///     model immediately without animating the cell insertion.
    ///   - onScrollLockChanged: Reports whether the host scroll view should be
    ///     disabled.
    ///   - composer: Builds the composer with FanPicker's context.
    public init(
        configuration: FanPickerConfiguration = .reference,
        source: RecentPhotoSource? = nil,
        onTapTrigger: @escaping () -> Void = {},
        onPhotoLoading: @escaping () -> Void = {},
        onPhotoAccessUnavailable: @escaping (
            RecentPhotoSource.AccessState
        ) -> Void = { _ in },
        isSelectionAllowed: @escaping (RecentPhotoAsset) -> Bool = { _ in true },
        onSelect: @escaping (RecentPhotoSelection) -> Void,
        onScrollLockChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder composer: @escaping (RecentPhotoPickerContext) -> Composer
    ) {
        self.configuration = configuration
        self.onTapTrigger = onTapTrigger
        self.onPhotoLoading = onPhotoLoading
        self.onPhotoAccessUnavailable = onPhotoAccessUnavailable
        self.isSelectionAllowed = isSelectionAllowed
        self.onSelect = onSelect
        self.onScrollLockChanged = onScrollLockChanged
        self.composer = composer
        _source = State(initialValue: source ?? RecentPhotoSource())
    }

    public var body: some View {
        composer(context)
            .overlayPreferenceValue(FanPickerTriggerAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    let geometry = resolve(anchor: anchor, proxy: proxy)

                    ZStack {
                        if let presentation = overlayPresentation, geometry.isValid {
                            RecentFanOverlay(
                                presentation: presentation,
                                configuration: configuration,
                                attachmentNamespace: attachmentNamespace,
                                attachmentTransition: attachmentTransition,
                                globalOrigin: geometry.composerRect.origin,
                                reduceMotion: reduceMotion,
                                committingAssetID: committingAssetID,
                                scrollingRow: scrollingRow,
                                onTapAsset: commit,
                                onVisibleIndexChanged: source.prepareAssets
                            )
                            .transition(revealTransition)
                            .onAppear {
                                controller.syncRevealClock(
                                    configuration: configuration
                                )
                            }
                        }
                        if voiceOverEnabled,
                           let presentation = controller.presentation,
                           geometry.isValid {
                            RecentPhotoAccessibilityOverlay(
                                presentation: presentation,
                                configuration: configuration,
                                globalOrigin: geometry.composerRect.origin,
                                onSelect: commit
                            )
                        }
                        if geometry.isValid {
                            triggerControl
                                .position(
                                    x: geometry.triggerRect.midX
                                        - geometry.composerRect.minX,
                                    y: geometry.triggerRect.midY
                                        - geometry.composerRect.minY
                                )
                                .zIndex(1_000)
                        }
                    }
                    .onAppear {
                        updateGeometry(geometry)
                    }
                    .onChange(of: geometry) { _, next in
                        updateGeometry(next)
                    }
                }
            }
            .sensoryFeedback(
                .impact(weight: .light, intensity: 0.7),
                trigger: controller.revealFeedbackToken
            )
            .sensoryFeedback(
                .selection,
                trigger: controller.hoverFeedbackToken
            )
            .sensoryFeedback(
                .impact(weight: .light, intensity: 0.45),
                trigger: photoLoadingFeedbackToken
            )
            .sensoryFeedback(
                .impact(weight: .light, intensity: 0.5),
                trigger: scrollingRow.stackFeedbackToken
            )
            .onChange(of: isScrollLocked) { _, isLocked in
                onScrollLockChanged(isLocked)
            }
            .task {
                await source.preload(
                    configuration: configuration,
                    displayScale: displayScale
                )
            }
            .onChange(of: scenePhase) { _, next in
                if next == .active {
                    Task {
                        await source.preload(
                            configuration: configuration,
                            displayScale: displayScale
                        )
                    }
                } else {
                    cancelTransientState()
                    source.cancelLoading()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                source.clearCachedImages()
            }
            .onDisappear {
                onScrollLockChanged(false)
                cancelTransientState()
                source.cancelLoading()
            }
    }

    private var context: RecentPhotoPickerContext {
        RecentPhotoPickerContext(
            isActive: controller.isActive,
            isLoadingPhotos: source.isLoading,
            photoLoadingFailures: source.loadingFailures,
            trigger: RecentPhotoTrigger(),
            attachmentNamespace: attachmentNamespace,
            attachmentTransition: attachmentTransition,
            configuration: configuration,
            onAttachmentDestinationReady: attachmentDestinationReady
        )
    }

    private var triggerControl: some View {
        RecentPhotoTriggerControl(
            isActive: controller.showsCloseTrigger,
            configuration: configuration,
            onRecognized: beginInteraction,
            onDrag: { point in
                updateHoldDrag(at: point)
            },
            onRelease: finishInteraction,
            onTap: handleTriggerTap,
            onPressChanged: { isTriggerPressed = $0 },
            onAccessibilityReveal: beginInteraction
        )
        .allowsHitTesting(attachmentTransition == nil)
    }

    private func beginInteraction() {
        guard attachmentTransition == nil else { return }

        guard source.canReveal else {
            if source.isLoading {
                photoLoadingFeedbackToken += 1
                onPhotoLoading()
                return
            }

            guard permissionRequestID == nil else { return }
            let requestID = UUID()
            permissionRequestID = requestID

            Task { @MainActor in
                await source.prepareForUserAction(
                    configuration: configuration,
                    displayScale: displayScale
                )
                guard permissionRequestID == requestID else { return }
                permissionRequestID = nil

                switch source.accessState {
                case .restricted, .denied:
                    onPhotoAccessUnavailable(source.accessState)
                case .notDetermined, .authorized, .limited:
                    break
                }
            }
            return
        }

        if reduceMotion {
            withAnimation(.smooth(duration: 0.12)) {
                controller.begin(
                    assets: source.revealAssets,
                    configuration: configuration,
                    reduceMotion: true
                )
            }
        } else {
            controller.begin(
                assets: source.revealAssets,
                configuration: configuration
            )
        }
        configureScrollingRow()
    }

    private func finishInteraction() {
        scrollingRow.stopEdgeTracking()
        guard let selection = controller.releaseSelection() else { return }
        commit(selection)
    }

    private func commit(_ selection: RecentPhotoAsset) {
        guard isSelectionAllowed(selection),
              attachmentTransition == nil,
              let sourcePresentation = controller.frozenPresentation() else {
            return
        }
        let photoSelection = RecentPhotoSelection(asset: selection)
        let transition = AttachmentTransitionSession(
            id: photoSelection.id,
            assetID: selection.id,
            asset: selection,
            sourcePresentation: sourcePresentation,
            sourceSize: configuration.recentSize * selectedVisualScale,
            sourceCornerRadius: configuration.recentCornerRadius
                * selectedVisualScale
        )

        selection.beginImageFreeze()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            attachmentTransition = transition
        }
        // Keep host layout animation outside the matched-geometry transaction.
        onSelect(photoSelection)
    }

    private func attachmentDestinationReady(_ attachmentID: UUID) {
        guard let transition = attachmentTransition,
              transition.id == attachmentID,
              transition.phase == .staged else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            prepareAttachmentFlight(sessionID: transition.id)
        }
    }

    private func prepareAttachmentFlight(sessionID: UUID) {
        guard let transition = attachmentTransition,
              transition.id == sessionID,
              transition.phase == .staged else {
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            attachmentTransition = transition.preparingFlight()
        }

        Task { @MainActor in
            await Task.yield()
            beginAttachmentFlight(sessionID: sessionID)
        }
    }

    private func beginAttachmentFlight(sessionID: UUID) {
        guard let transition = attachmentTransition,
              transition.id == sessionID,
              transition.phase == .prepared else {
            return
        }
        let flyingTransition = transition.startingFlight()

        withAnimation(
            flightAnimation,
            completionCriteria: .logicallyComplete
        ) {
            attachmentTransition = flyingTransition
            controller.commitSelection()
        } completion: {
            guard attachmentTransition?.id == transition.id else { return }
            transition.asset.endImageFreeze()
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                attachmentTransition = nil
                scrollingRow.reset()
            }
        }
    }

    private func handleTriggerTap() {
        if controller.isActive {
            if let session = controller.presentation?.session {
                scrollingRow.prepareDismissal(
                    revealItemCount: session.revealMotionItemCount,
                    usesCurrentLayout: controller.isOpen
                )
            }
            if reduceMotion {
                withAnimation(.smooth(duration: 0.12)) {
                    controller.cancelImmediately()
                    scrollingRow.reset()
                }
            } else {
                controller.dismiss(configuration: configuration)
            }
        } else {
            onTapTrigger()
        }
    }

    private var flightAnimation: Animation {
        if reduceMotion {
            .smooth(duration: 0.12)
        } else {
            .spring(
                duration: configuration.flightDuration,
                bounce: configuration.flightBounce
            )
        }
    }

    private var selectedVisualScale: CGFloat {
        reduceMotion
            ? min(configuration.hoverScale, 1.04)
            : configuration.hoverScale
    }

    private var overlayPresentation: FanPickerController.Presentation? {
        attachmentTransition?.sourcePresentation ?? controller.presentation
    }

    private var committingAssetID: String? {
        guard attachmentTransition?.phase == .flying else { return nil }
        return attachmentTransition?.assetID
    }

    private var isScrollLocked: Bool {
        isTriggerPressed || controller.isActive || attachmentTransition != nil
    }

    private var revealTransition: AnyTransition {
        guard reduceMotion else { return .identity }
        return .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading))
    }

    private func updateGeometry(_ geometry: ResolvedFanPickerGeometry) {
        let changedDuringInteraction = resolvedGeometry.isValid
            && geometry.isValid
            && resolvedGeometry.differs(from: geometry)
            && controller.isActive
            && attachmentTransition == nil

        resolvedGeometry = geometry
        controller.updateGeometry(geometry)
        configureScrollingRow()
        if !geometry.isValid || changedDuringInteraction {
            cancelTransientState()
        }
    }

    private func cancelTransientState() {
        permissionRequestID = nil
        controller.cancelImmediately()
        attachmentTransition?.asset.endImageFreeze()
        attachmentTransition = nil
        scrollingRow.reset()
    }

    private func configureScrollingRow() {
        guard configuration.scrolling != nil,
              attachmentTransition == nil,
              let session = controller.presentation?.session,
              resolvedGeometry.isValid else {
            return
        }
        scrollingRow.configure(
            sessionID: session.id,
            geometry: resolvedGeometry,
            assetCount: session.assets.count,
            configuration: configuration
        )
        if let layout = scrollingRow.layout {
            source.prepareAssets(
                near: layout.trailingVisibleIndex(offset: scrollingRow.offset)
            )
        }
    }

    private func updateHoldDrag(at point: CGPoint) {
        if configuration.scrolling != nil,
           controller.isOpen,
           let session = controller.presentation?.session {
            // Do not select a card moving under a stationary finger.
            let assetID = scrollingRow.isAutoScrolling
                ? nil
                : scrollingRow.hitTest(
                    point: point,
                    currentID: controller.presentation?.highlightedID,
                    assets: session.assets,
                    configuration: configuration
                )
            controller.updateHover(assetID: assetID)
        } else {
            controller.updateHover(at: point, configuration: configuration)
        }

        guard configuration.scrolling != nil else { return }
        scrollingRow.updateEdgeLocation(
            point,
            canScroll: { controller.isOpen },
            onScroll: { _ in
                controller.updateHover(assetID: nil)
                if let layout = scrollingRow.layout {
                    source.prepareAssets(
                        near: layout.trailingVisibleIndex(
                            offset: scrollingRow.offset
                        )
                    )
                }
            }
        )
    }

    private func resolve(
        anchor: Anchor<CGRect>?,
        proxy: GeometryProxy
    ) -> ResolvedFanPickerGeometry {
        ResolvedFanPickerGeometry(
            composerRect: proxy.frame(in: .global),
            triggerRect: anchor.map {
                let localRect = proxy[$0]
                let globalOrigin = proxy.frame(in: .global).origin
                return localRect.offsetBy(
                    dx: globalOrigin.x,
                    dy: globalOrigin.y
                )
            } ?? .zero
        )
    }
}
#endif

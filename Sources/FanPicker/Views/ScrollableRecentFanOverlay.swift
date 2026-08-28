#if canImport(UIKit)
import SwiftUI

struct ScrollableRecentFanOverlay: View {
    let presentation: FanPickerController.Presentation
    let configuration: FanPickerConfiguration
    let attachmentNamespace: Namespace.ID
    let attachmentTransition: AttachmentTransitionSession?
    let globalOrigin: CGPoint
    let reduceMotion: Bool
    let committingAssetID: String?
    let scrollingRow: ScrollableRecentRowController
    let onTapAsset: (RecentPhotoAsset) -> Void
    let onVisibleIndexChanged: (Int) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            NativeScrollableRecentFanOverlay(
                presentation: presentation,
                configuration: configuration,
                attachmentNamespace: attachmentNamespace,
                attachmentTransition: attachmentTransition,
                globalOrigin: globalOrigin,
                reduceMotion: reduceMotion,
                committingAssetID: committingAssetID,
                scrollingRow: scrollingRow,
                onTapAsset: onTapAsset,
                onVisibleIndexChanged: onVisibleIndexChanged
            )
        } else {
            LegacyScrollableRecentFanOverlay(
                presentation: presentation,
                configuration: configuration,
                attachmentNamespace: attachmentNamespace,
                attachmentTransition: attachmentTransition,
                globalOrigin: globalOrigin,
                reduceMotion: reduceMotion,
                committingAssetID: committingAssetID,
                scrollingRow: scrollingRow,
                onTapAsset: onTapAsset,
                onVisibleIndexChanged: onVisibleIndexChanged
            )
        }
    }
}

private struct LegacyScrollableRecentFanOverlay: View {
    let presentation: FanPickerController.Presentation
    let configuration: FanPickerConfiguration
    let attachmentNamespace: Namespace.ID
    let attachmentTransition: AttachmentTransitionSession?
    let globalOrigin: CGPoint
    let reduceMotion: Bool
    let committingAssetID: String?
    let scrollingRow: ScrollableRecentRowController
    let onTapAsset: (RecentPhotoAsset) -> Void
    let onVisibleIndexChanged: (Int) -> Void

    @State private var motionRenderer = RevealMotionRenderer()
    @State private var isDragging = false
    @State private var lastReportedVisibleIndex: Int?

    private var context: RecentFanOverlayContext {
        RecentFanOverlayContext(
            presentation: presentation,
            configuration: configuration,
            attachmentTransition: attachmentTransition,
            reduceMotion: reduceMotion,
            committingAssetID: committingAssetID
        )
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: nil,
                paused: context.isSettled
            )
        ) { timeline in
            ZStack {
                ForEach(renderedIndices, id: \.self) { index in
                    if presentation.session.assets.indices.contains(index),
                       !context.isFlyingAttachment(
                           presentation.session.assets[index]
                       ) {
                        thumbnail(
                            presentation.session.assets[index],
                            index: index,
                            date: timeline.date
                        )
                    }
                }
            }
        }
        .simultaneousGesture(scrollGesture)
        .allowsHitTesting(context.allowsSelection)
        .accessibilityHidden(true)
        .onAppear(perform: reportVisibleIndex)
        .onChange(of: scrollingRow.offset) { _, _ in
            reportVisibleIndex()
        }
    }
}

private extension LegacyScrollableRecentFanOverlay {
    private func thumbnail(
        _ asset: RecentPhotoAsset,
        index: Int,
        date: Date
    ) -> some View {
        let context = context
        let motion = motionValue(index: index, date: date)
        let isStacked = stackedIndices.contains(index)
        let placement = stackPlacement(index: index)
        let visualScale = motion.scale
            * context.hoverScale(for: asset)
            * (placement?.scale ?? 1)
        let shadowStrength = stackShadowStrength(index: index)

        return Button {
            guard scrollingRow.allowsTap() else { return }
            if isStacked {
                scrollingRow.scrollToStart()
            } else if context.allowsSelection, asset.isDisplayReady {
                onTapAsset(asset)
            }
        } label: {
            thumbnailLabel(
                asset,
                visualScale: visualScale,
                opacity: motion.opacity * (placement?.opacity ?? 1),
                shadowStrength: shadowStrength,
                context: context
            )
        }
        .buttonStyle(.plain)
        .transition(.identity)
        .position(
            x: motion.center.x - globalOrigin.x,
            y: motion.center.y - globalOrigin.y
        )
        .zIndex(
            asset.id == presentation.highlightedID
                ? 1_000
                : Double(index)
        )
    }

    private func thumbnailLabel(
        _ asset: RecentPhotoAsset,
        visualScale: CGFloat,
        opacity: CGFloat,
        shadowStrength: CGFloat,
        context: RecentFanOverlayContext
    ) -> some View {
        let size = configuration.recentSize * visualScale
        let cornerRadius = configuration.recentCornerRadius * visualScale
        return RecentFanThumbnailImage(
            asset: asset,
            size: size,
            cornerRadius: cornerRadius
        )
        .recentFanMatchedGeometry(
            asset: asset,
            transition: attachmentTransition,
            namespace: attachmentNamespace
        )
        .shadow(
            color: shadowStrength > 0
                ? .black.opacity(0.18 * shadowStrength)
                : .clear,
            radius: 5,
            y: 2
        )
        .opacity(opacity)
        .opacity(context.isPreparedAttachment(asset) ? 0 : 1)
        .opacity(context.fadesForCommit(asset) ? 0 : 1)
        .animation(
            .easeOut(duration: configuration.nonSelectedFadeDuration),
            value: context.fadesForCommit(asset)
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
    }

    private func motionValue(index: Int, date: Date) -> RevealMotionValue {
        let session = presentation.session
        let fallback = scrollingRow.layout?.rawCenter(index: index, offset: 0)
            ?? CGPoint(
                x: session.geometry.triggerRect.midX,
                y: session.geometry.triggerRect.midY
            )
        return motionRenderer.value(
            presentation: presentation,
            configuration: configuration,
            index: index,
            target: RevealMotionTarget(
                destination: fallback,
                settledCenter: scrollingRow.layout?.center(
                    index: index,
                    offset: scrollingRow.offset
                ) ?? fallback,
                dismissalStart: scrollingRow.dismissalStartValues[index]
                    ?? RevealMotionValue(
                        center: fallback,
                        scale: 1,
                        opacity: 1
                    ),
                dismissalOrder: scrollingRow.dismissalIndices.firstIndex(
                    of: index
                ) ?? index
            ),
            date: date
        )
    }

    private var scrollGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                guard context.allowsScrolling else { return }
                if !isDragging {
                    isDragging = true
                    scrollingRow.beginDrag()
                }
                scrollingRow.updateDrag(translation: value.translation.width)
            }
            .onEnded { value in
                guard isDragging else { return }
                scrollingRow.endDrag(
                    predictedTranslation: value.predictedEndTranslation.width
                )
                isDragging = false
            }
    }

    private var renderedIndices: [Int] {
        let session = presentation.session
        switch presentation.phase {
        case .revealing, .frozen:
            return Array(0..<session.revealMotionItemCount)
        case .settled:
            return scrollingRow.layout?.renderedIndices(
                offset: scrollingRow.offset
            ) ?? Array(0..<session.revealMotionItemCount)
        case .dismissing:
            return scrollingRow.dismissalIndices.isEmpty
                ? Array(0..<session.revealMotionItemCount)
                : scrollingRow.dismissalIndices
        }
    }

    private var stackedIndices: Set<Int> {
        guard case .settled = presentation.phase else { return [] }
        return Set(
            scrollingRow.layout?.stackedIndices(offset: scrollingRow.offset) ?? []
        )
    }

    private func stackPlacement(
        index: Int
    ) -> ScrollableRecentRowLayout.StackPlacement? {
        guard case .settled = presentation.phase else { return nil }
        return scrollingRow.layout?.stackPlacement(
            index: index,
            offset: scrollingRow.offset
        )
    }

    private func stackShadowStrength(index: Int) -> CGFloat {
        guard case .settled = presentation.phase,
              let layout = scrollingRow.layout else {
            return 0
        }
        return layout.stackShadowStrength(
            index: index,
            offset: scrollingRow.offset
        )
    }

    private func reportVisibleIndex() {
        guard let layout = scrollingRow.layout else { return }
        let index = layout.trailingVisibleIndex(offset: scrollingRow.offset)
        guard index != lastReportedVisibleIndex else { return }
        lastReportedVisibleIndex = index
        onVisibleIndexChanged(index)
    }
}
#endif

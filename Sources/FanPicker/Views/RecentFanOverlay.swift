#if canImport(UIKit)
import SwiftUI

struct RecentFanOverlay: View {
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
        if configuration.scrolling != nil {
            ScrollableRecentFanOverlay(
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
            FixedRecentFanOverlay(
                presentation: presentation,
                configuration: configuration,
                attachmentNamespace: attachmentNamespace,
                attachmentTransition: attachmentTransition,
                globalOrigin: globalOrigin,
                reduceMotion: reduceMotion,
                committingAssetID: committingAssetID,
                onTapAsset: onTapAsset
            )
        }
    }
}

private struct FixedRecentFanOverlay: View {
    let presentation: FanPickerController.Presentation
    let configuration: FanPickerConfiguration
    let attachmentNamespace: Namespace.ID
    let attachmentTransition: AttachmentTransitionSession?
    let globalOrigin: CGPoint
    let reduceMotion: Bool
    let committingAssetID: String?
    let onTapAsset: (RecentPhotoAsset) -> Void

    @State private var motionRenderer = RevealMotionRenderer()

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
            let session = presentation.session
            let destinations = session.geometry.recentRects(
                count: session.assets.count,
                configuration: configuration
            )

            ZStack {
                ForEach(
                    Array(session.assets.enumerated()),
                    id: \.element.id
                ) { index, asset in
                    if destinations.indices.contains(index),
                       !context.isFlyingAttachment(asset) {
                        thumbnail(
                            asset,
                            index: index,
                            destination: destinations[index],
                            date: timeline.date
                        )
                    }
                }
            }
        }
        .allowsHitTesting(context.allowsInteraction)
        .accessibilityHidden(true)
    }

    private func thumbnail(
        _ asset: RecentPhotoAsset,
        index: Int,
        destination: CGRect,
        date: Date
    ) -> some View {
        let context = context
        let center = CGPoint(x: destination.midX, y: destination.midY)
        let motion = motionRenderer.value(
            presentation: presentation,
            configuration: configuration,
            index: index,
            target: RevealMotionTarget(
                destination: center,
                settledCenter: center,
                dismissalStart: nil,
                dismissalOrder: index
            ),
            date: date
        )
        let visualScale = motion.scale * context.hoverScale(for: asset)

        return Button {
            guard context.allowsInteraction else { return }
            onTapAsset(asset)
        } label: {
            thumbnailLabel(
                asset,
                visualScale: visualScale,
                opacity: motion.opacity,
                context: context
            )
        }
        .buttonStyle(.plain)
        .position(
            x: motion.center.x - globalOrigin.x,
            y: motion.center.y - globalOrigin.y
        )
        .zIndex(
            asset.id == presentation.highlightedID
                ? 100
                : Double(presentation.session.assets.count - index)
        )
    }

    private func thumbnailLabel(
        _ asset: RecentPhotoAsset,
        visualScale: CGFloat,
        opacity: CGFloat,
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
}
#endif

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
    let onTapAsset: (RecentPhotoAsset) -> Void

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: nil,
                paused: isSettled
            )
        ) { context in
            let session = presentation.session
            let destinations = session.geometry.recentRects(
                count: session.assets.count,
                configuration: configuration
            )

            ZStack {
                ForEach(Array(session.assets.enumerated()), id: \.element.id) {
                    index,
                    asset in
                    if destinations.indices.contains(index),
                       !isFlyingAttachment(asset) {
                        thumbnail(
                            asset,
                            index: index,
                            destination: destinations[index],
                            date: context.date
                        )
                    }
                }
            }
        }
        .allowsHitTesting(allowsTapSelection)
        .accessibilityHidden(true)
    }

    private func thumbnail(
        _ asset: RecentPhotoAsset,
        index: Int,
        destination: CGRect,
        date: Date
    ) -> some View {
        let session = presentation.session
        let motion = motionValue(
            index: index,
            destination: destination,
            date: date
        )
        let hoverScale = asset.id == presentation.highlightedID
            ? resolvedHoverScale
            : 1
        let visualScale = motion.scale * hoverScale
        let visualSize = configuration.recentSize * visualScale
        let cornerRadius = configuration.recentCornerRadius * visualScale
        let fadesForCommit = committingAssetID != nil
            && committingAssetID != asset.id

        let matchedImage = matchedThumbnail(
            thumbnailImage(
                asset,
                visualSize: visualSize,
                cornerRadius: cornerRadius
            ),
            asset: asset
        )

        return Button {
            guard allowsTapSelection else { return }
            onTapAsset(asset)
        } label: {
            matchedImage
                .opacity(motion.opacity)
                .opacity(isPreparedAttachment(asset) ? 0 : 1)
                .opacity(fadesForCommit ? 0 : 1)
                .animation(
                    .easeOut(duration: configuration.nonSelectedFadeDuration),
                    value: fadesForCommit
                )
                .contentShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
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
                : Double(session.assets.count - index)
        )
    }

    @ViewBuilder
    private func matchedThumbnail<Thumbnail: View>(
        _ thumbnail: Thumbnail,
        asset: RecentPhotoAsset
    ) -> some View {
        if let transition = attachmentTransition,
           transition.assetID == asset.id {
            thumbnail
                .matchedGeometryEffect(
                    id: transition.id,
                    in: attachmentNamespace,
                    properties: .position,
                    isSource: true
                )
        } else {
            thumbnail
        }
    }

    private func thumbnailImage(
        _ asset: RecentPhotoAsset,
        visualSize: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        Image(uiImage: asset.image)
            .resizable()
            .scaledToFill()
            .frame(width: visualSize, height: visualSize)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
    }

    private var isSettled: Bool {
        switch presentation.phase {
        case .settled, .frozen:
            true
        case .revealing, .dismissing:
            false
        }
    }

    private var allowsTapSelection: Bool {
        guard attachmentTransition == nil else { return false }
        if case .settled = presentation.phase {
            return true
        }
        return false
    }

    private func isPreparedAttachment(_ asset: RecentPhotoAsset) -> Bool {
        attachmentTransition?.assetID == asset.id
            && attachmentTransition?.phase == .prepared
    }

    private func isFlyingAttachment(_ asset: RecentPhotoAsset) -> Bool {
        attachmentTransition?.assetID == asset.id
            && attachmentTransition?.phase == .flying
    }

    private var resolvedHoverScale: CGFloat {
        reduceMotion ? min(configuration.hoverScale, 1.04) : configuration.hoverScale
    }

    private func motionValue(
        index: Int,
        destination: CGRect,
        date: Date
    ) -> RevealMotionValue {
        let session = presentation.session
        let timeline = RevealMotionTimeline(configuration: configuration)
        let source = CGPoint(
            x: session.geometry.triggerRect.midX,
            y: session.geometry.triggerRect.midY
        )
        let destinationCenter = CGPoint(
            x: destination.midX,
            y: destination.midY
        )

        switch presentation.phase {
        case .revealing:
            return timeline.value(
                source: source,
                destination: destinationCenter,
                index: index,
                time: max(date.timeIntervalSince(session.startDate), 0)
            )
        case .settled:
            return RevealMotionValue(
                center: destinationCenter,
                scale: 1,
                opacity: 1
            )
        case let .frozen(revealElapsed):
            return timeline.value(
                source: source,
                destination: destinationCenter,
                index: index,
                time: revealElapsed
            )
        case let .dismissing(startDate, initialRevealElapsed):
            let start = timeline.value(
                source: source,
                destination: destinationCenter,
                index: index,
                time: initialRevealElapsed
            )
            return timeline.dismissalValue(
                from: start,
                source: source,
                destination: destinationCenter,
                index: index,
                time: max(date.timeIntervalSince(startDate), 0)
            )
        }
    }
}
#endif

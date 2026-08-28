#if canImport(UIKit)
import SwiftUI

private struct NativeCardTransform {
    let scale: CGFloat
    let opacity: CGFloat
    let offset: CGSize
}

@available(iOS 18.0, *)
struct NativeScrollableRecentFanOverlay: View {
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
    @State private var scrollPosition = ScrollPosition(x: 0)
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
            if let layout = scrollingRow.layout {
                ScrollView(.horizontal) {
                    HStack(spacing: layout.itemSpacing) {
                        ForEach(
                            Array(presentation.session.assets.enumerated()),
                            id: \.element.id
                        ) { index, asset in
                            thumbnail(
                                asset,
                                index: index,
                                date: timeline.date,
                                layout: layout
                            )
                        }
                    }
                    .padding(.leading, leadingInset(layout: layout))
                    .padding(.trailing, layout.terminalAlignmentInset)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(
                    for: CGFloat.self,
                    of: { geometry in
                        max(
                            geometry.contentOffset.x
                                + geometry.contentInsets.leading,
                            0
                        )
                    },
                    action: updateScrollOffset
                )
                .scrollDisabled(!context.allowsScrolling)
                .frame(
                    width: layout.viewport.width,
                    height: rowViewportHeight
                )
                .position(
                    x: layout.viewport.midX - globalOrigin.x,
                    y: layout.rowCenterY - globalOrigin.y
                )
                .accessibilityHidden(true)
                .onAppear {
                    scrollingRow.activateNativeScrolling()
                    reportVisibleIndex()
                }
                .onChange(of: scrollingRow.scrollRequest.id) { _, _ in
                    let request = scrollingRow.scrollRequest
                    if request.animated {
                        withAnimation(.easeOut(duration: 0.32)) {
                            scrollPosition.scrollTo(x: request.offset)
                        }
                    } else {
                        scrollPosition.scrollTo(x: request.offset)
                    }
                }
            }
        }
        .allowsHitTesting(context.allowsSelection)
    }
}

@available(iOS 18.0, *)
private extension NativeScrollableRecentFanOverlay {
    @ViewBuilder
    private func thumbnail(
        _ asset: RecentPhotoAsset,
        index: Int,
        date: Date,
        layout: ScrollableRecentRowLayout
    ) -> some View {
        if context.isFlyingAttachment(asset) {
            Color.clear
                .frame(
                    width: configuration.recentSize,
                    height: configuration.recentSize
                )
        } else {
            renderedThumbnail(
                asset,
                index: index,
                date: date,
                layout: layout
            )
        }
    }

    private func renderedThumbnail(
        _ asset: RecentPhotoAsset,
        index: Int,
        date: Date,
        layout: ScrollableRecentRowLayout
    ) -> some View {
        let context = context
        let motion = motionValue(index: index, date: date, layout: layout)
        let shadowStrength = stackShadowStrength(index: index, layout: layout)
        let isPinning = usesPinnedLayout

        return Button {
            guard scrollingRow.allowsTap() else { return }
            if isStacked(index: index, layout: layout) {
                scrollingRow.scrollToStart()
            } else if context.allowsSelection, asset.isDisplayReady {
                onTapAsset(asset)
            }
        } label: {
            thumbnailLabel(
                asset,
                index: index,
                motion: motion,
                shadowStrength: shadowStrength,
                context: context
            )
        }
        .buttonStyle(.plain)
        .frame(
            width: configuration.recentSize,
            height: configuration.recentSize
        )
        .visualEffect { effect, proxy in
            let transform = Self.cardTransform(
                proxy: proxy,
                index: index,
                motion: motion,
                layout: layout,
                isPinning: isPinning
            )
            return effect
                .scaleEffect(transform.scale, anchor: .center)
                .offset(transform.offset)
                .opacity(Double(transform.opacity))
        }
        .zIndex(
            asset.id == presentation.highlightedID
                ? 1_000
                : Double(index)
        )
    }

    private func thumbnailLabel(
        _ asset: RecentPhotoAsset,
        index: Int,
        motion: RevealMotionValue,
        shadowStrength: CGFloat,
        context: RecentFanOverlayContext
    ) -> some View {
        RecentFanThumbnailImage(
            asset: asset,
            size: configuration.recentSize,
            cornerRadius: configuration.recentCornerRadius
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
        .scaleEffect(motion.scale * context.hoverScale(for: asset))
        .opacity(motion.opacity * visibility(index: index))
        .opacity(context.isPreparedAttachment(asset) ? 0 : 1)
        .opacity(context.fadesForCommit(asset) ? 0 : 1)
        .animation(
            .easeOut(duration: configuration.nonSelectedFadeDuration),
            value: context.fadesForCommit(asset)
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: configuration.recentCornerRadius,
                style: .continuous
            )
        )
    }

    nonisolated private static func cardTransform(
        proxy: GeometryProxy,
        index: Int,
        motion: RevealMotionValue,
        layout: ScrollableRecentRowLayout,
        isPinning: Bool
    ) -> NativeCardTransform {
        let rawCenter = CGPoint(
            x: proxy.frame(in: .global).midX,
            y: proxy.frame(in: .global).midY
        )
        guard isPinning else {
            return NativeCardTransform(
                scale: 1,
                opacity: 1,
                offset: CGSize(
                    width: motion.center.x - rawCenter.x,
                    height: motion.center.y - rawCenter.y
                )
            )
        }

        let capture = layout.stackCapture(rawCenter: rawCenter)
        let currentOffset = layout.clampedOffset(
            layout.leadingCenterX
                + CGFloat(index) * layout.itemPitch
                - rawCenter.x
        )
        let placement = layout.stackPlacement(
            index: index,
            offset: currentOffset
        )
        return NativeCardTransform(
            scale: placement?.scale ?? 1,
            opacity: placement?.opacity ?? 1,
            offset: CGSize(width: capture.center.x - rawCenter.x, height: 0)
        )
    }

    private func motionValue(
        index: Int,
        date: Date,
        layout: ScrollableRecentRowLayout
    ) -> RevealMotionValue {
        let destination = finalCenter(index: index, layout: layout)
        return motionRenderer.value(
            presentation: presentation,
            configuration: configuration,
            index: index,
            target: RevealMotionTarget(
                destination: destination,
                settledCenter: destination,
                dismissalStart: scrollingRow.dismissalStartValues[index]
                    ?? RevealMotionValue(
                        center: destination,
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

    private func finalCenter(
        index: Int,
        layout: ScrollableRecentRowLayout
    ) -> CGPoint {
        CGPoint(
            x: layout.leadingCenterX + CGFloat(index) * layout.itemPitch,
            y: layout.rowCenterY
        )
    }

    private func stackShadowStrength(
        index: Int,
        layout: ScrollableRecentRowLayout
    ) -> CGFloat {
        guard case .settled = presentation.phase else { return 0 }
        return layout.stackShadowStrength(
            index: index,
            offset: scrollingRow.offset
        )
    }

    private func visibility(index: Int) -> CGFloat {
        switch presentation.phase {
        case .revealing, .frozen:
            index < presentation.session.revealMotionItemCount ? 1 : 0
        case .settled:
            1
        case .dismissing:
            scrollingRow.dismissalIndices.contains(index) ? 1 : 0
        }
    }

    private func isStacked(
        index: Int,
        layout: ScrollableRecentRowLayout
    ) -> Bool {
        guard let top = layout.stackedThrough(offset: scrollingRow.offset) else {
            return false
        }
        return index <= top
    }

    private var usesPinnedLayout: Bool {
        switch presentation.phase {
        case .settled:
            true
        case .revealing, .frozen, .dismissing:
            false
        }
    }

    private var rowViewportHeight: CGFloat {
        configuration.recentSize * max(configuration.hoverScale, 1)
            + configuration.hoverHitExpansion * 2
    }

    private func leadingInset(
        layout: ScrollableRecentRowLayout
    ) -> CGFloat {
        max(
            layout.leadingCenterX
                - layout.viewport.minX
                - configuration.recentSize / 2,
            0
        )
    }

    private func updateScrollOffset(
        oldValue _: CGFloat,
        newValue: CGFloat
    ) {
        scrollingRow.updateNativeOffset(newValue)
        reportVisibleIndex()
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

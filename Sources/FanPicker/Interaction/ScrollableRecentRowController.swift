#if canImport(UIKit)
import Foundation
import Observation
import QuartzCore

@MainActor
@Observable
final class ScrollableRecentRowController {
    struct ScrollRequest: Equatable {
        let id: Int
        let offset: CGFloat
        let animated: Bool
    }

    private(set) var offset: CGFloat = 0
    private(set) var layout: ScrollableRecentRowLayout?
    private(set) var dismissalStartValues: [Int: RevealMotionValue] = [:]
    private(set) var dismissalIndices: [Int] = []
    private(set) var scrollRequest = ScrollRequest(id: 0, offset: 0, animated: false)
    private(set) var stackFeedbackToken = 0
    // Disable selection while cards move under a stationary finger.
    private(set) var isAutoScrolling = false

    @ObservationIgnored
    private var sessionID: UUID?
    @ObservationIgnored
    private var dragStartOffset: CGFloat = 0
    @ObservationIgnored
    private var edgeLocation: CGPoint?
    @ObservationIgnored
    private let edgeTicker = DisplayLinkTicker()
    @ObservationIgnored
    private let momentumTicker = DisplayLinkTicker()
    @ObservationIgnored
    private var suppressesTapUntil = Date.distantPast
    @ObservationIgnored
    private var usesNativeScrolling = false

    func configure(
        sessionID: UUID,
        geometry: ResolvedFanPickerGeometry,
        assetCount: Int,
        configuration: FanPickerConfiguration
    ) {
        guard let scrolling = configuration.scrolling else {
            reset()
            return
        }
        let revealCount = min(max(configuration.itemCount, 1), assetCount)
        let destinations = geometry.recentRects(
            count: revealCount,
            configuration: configuration
        )
        guard let first = destinations.first else {
            reset()
            return
        }

        let nextLayout = ScrollableRecentRowLayout(
            viewport: geometry.composerRect,
            rowCenterY: first.midY,
            leadingCenterX: first.midX,
            itemSize: configuration.recentSize,
            itemSpacing: configuration.recentSpacing,
            assetCount: assetCount,
            stackDepth: scrolling.resolvedStackDepth
        )
        let startsNewSession = self.sessionID != sessionID
        self.sessionID = sessionID
        scrollingConfiguration = scrolling
        layout = nextLayout
        offset = startsNewSession ? 0 : nextLayout.clampedOffset(offset)
        if startsNewSession {
            usesNativeScrolling = false
            scrollRequest = ScrollRequest(
                id: scrollRequest.id + 1,
                offset: 0,
                animated: false
            )
            dismissalStartValues.removeAll()
            dismissalIndices.removeAll()
        }
    }

    func activateNativeScrolling() {
        stopMomentum()
        usesNativeScrolling = true
    }

    func updateNativeOffset(_ newOffset: CGFloat) {
        guard usesNativeScrolling else { return }
        applyOffset(newOffset)
    }

    func beginDrag() {
        stopMomentum()
        dragStartOffset = offset
    }

    func updateDrag(translation: CGFloat) {
        guard let layout else { return }
        let next = layout.clampedOffset(dragStartOffset - translation)
        if abs(next - dragStartOffset) > 3 {
            suppressesTapUntil = Date.now.addingTimeInterval(0.12)
        }
        applyOffset(next)
    }

    func endDrag(predictedTranslation: CGFloat) {
        guard let layout else { return }
        let projected = layout.clampedOffset(
            dragStartOffset - predictedTranslation
        )
        let maximumTravel = max(layout.viewport.width * 1.25, layout.itemPitch)
        let target = min(
            max(projected, offset - maximumTravel),
            offset + maximumTravel
        )
        let distance = abs(target - offset)
        let duration = min(max(0.20 + distance / 1_600, 0.20), 0.42)
        startMomentum(to: target, duration: duration)
    }

    func scrollToStart() {
        if usesNativeScrolling {
            requestNativeScroll(to: 0, animated: true)
        } else {
            startMomentum(to: 0, duration: 0.32)
        }
    }

    func allowsTap() -> Bool {
        !momentumTicker.isRunning && Date.now >= suppressesTapUntil
    }

    func hitTest(
        point: CGPoint,
        currentID: String?,
        assets: [RecentPhotoAsset],
        configuration: FanPickerConfiguration
    ) -> String? {
        guard let layout else { return nil }
        let visible = layout.visibleMainIndices(offset: offset)
        if let currentID,
           let currentIndex = assets.firstIndex(where: { $0.id == currentID }),
           let rect = layout.selectableRect(index: currentIndex, offset: offset),
           rect.insetBy(
               dx: -configuration.hoverStickyExpansion,
               dy: -configuration.hoverStickyExpansion
           ).contains(point) {
            return currentID
        }
        return visible.first { index in
            assets.indices.contains(index)
                && assets[index].isDisplayReady
                && layout.selectableRect(index: index, offset: offset)?
                .insetBy(
                    dx: -configuration.hoverHitExpansion,
                    dy: -configuration.hoverHitExpansion
                )
                .contains(point) == true
        }.map { assets[$0].id }
    }

    func prepareDismissal(
        revealItemCount: Int,
        usesCurrentLayout: Bool
    ) {
        guard let layout else { return }
        let indices = usesCurrentLayout
            ? layout.renderedIndices(offset: offset)
            : Array(0..<min(max(revealItemCount, 0), layout.assetCount))
        dismissalIndices = indices
        dismissalStartValues = Dictionary(
            uniqueKeysWithValues: indices.map { index in
                let placement = layout.stackPlacement(index: index, offset: offset)
                return (
                    index,
                    RevealMotionValue(
                        center: layout.center(index: index, offset: offset),
                        scale: placement?.scale ?? 1,
                        opacity: placement?.opacity ?? 1
                    )
                )
            }
        )
        stopEdgeTracking()
        stopMomentum()
    }

    func updateEdgeLocation(
        _ location: CGPoint,
        canScroll: @escaping @MainActor () -> Bool,
        onScroll: @escaping @MainActor (CGPoint) -> Void
    ) {
        edgeLocation = location
        guard !edgeTicker.isRunning else { return }
        stopMomentum()
        edgeTicker.start { [weak self] link in
            guard let self,
                  canScroll(),
                  let layout = self.layout,
                  let location = self.edgeLocation else {
                self?.isAutoScrolling = false
                return
            }
            let velocity = self.edgeVelocity(at: location, layout: layout)
            guard velocity != 0 else {
                self.isAutoScrolling = false
                return
            }
            let frameDuration = link.targetTimestamp - link.timestamp
            let next = layout.clampedOffset(
                self.offset + velocity * frameDuration
            )
            guard next != self.offset else {
                self.isAutoScrolling = false
                return
            }
            self.isAutoScrolling = true
            if self.usesNativeScrolling {
                self.requestNativeScroll(to: next)
            } else {
                self.applyOffset(next)
            }
            onScroll(location)
        }
    }

    func stopEdgeTracking() {
        edgeLocation = nil
        isAutoScrolling = false
        edgeTicker.stop()
    }

    func reset() {
        stopEdgeTracking()
        stopMomentum()
        sessionID = nil
        usesNativeScrolling = false
        offset = 0
        layout = nil
        dismissalStartValues.removeAll()
        dismissalIndices.removeAll()
    }

    @ObservationIgnored
    private var scrollingConfiguration: FanPickerScrollingConfiguration?
}

private extension ScrollableRecentRowController {
    private func edgeVelocity(
        at point: CGPoint,
        layout: ScrollableRecentRowLayout
    ) -> CGFloat {
        guard let scrolling = scrollingConfiguration,
              point.y >= layout.rowCenterY - layout.itemSize,
              point.y <= layout.rowCenterY + layout.itemSize else {
            return 0
        }
        let zone = scrolling.resolvedEdgeActivationWidth
        if point.x > layout.viewport.maxX - zone {
            let progress = min(
                max((point.x - (layout.viewport.maxX - zone)) / zone, 0),
                1
            )
            return scrolling.resolvedMaximumEdgeScrollSpeed
                * progress * progress
        }
        if point.x < layout.viewport.minX + zone {
            let progress = min(
                max(((layout.viewport.minX + zone) - point.x) / zone, 0),
                1
            )
            return -scrolling.resolvedMaximumEdgeScrollSpeed
                * progress * progress
        }
        return 0
    }

    private func startMomentum(
        to proposedOffset: CGFloat,
        duration: TimeInterval
    ) {
        guard let layout else { return }
        stopMomentum()

        let startOffset = offset
        let targetOffset = layout.clampedOffset(proposedOffset)
        guard startOffset != targetOffset else { return }

        let resolvedDuration = max(duration, 0.01)
        suppressesTapUntil = Date.now.addingTimeInterval(resolvedDuration + 0.05)
        let startTime = CACurrentMediaTime()
        momentumTicker.start { [weak self] link in
            guard let self else { return }
            let progress = min(
                max((link.targetTimestamp - startTime) / resolvedDuration, 0),
                1
            )
            let remaining = 1 - progress
            self.applyOffset(
                startOffset
                    + (targetOffset - startOffset)
                    * (1 - remaining * remaining * remaining)
            )
            if progress >= 1 {
                self.momentumTicker.stop()
            }
        }
    }

    private func stopMomentum() {
        momentumTicker.stop()
    }

    private func requestNativeScroll(
        to proposedOffset: CGFloat,
        animated: Bool = false
    ) {
        guard let layout else { return }
        let nextOffset = layout.clampedOffset(proposedOffset)
        applyOffset(nextOffset)
        scrollRequest = ScrollRequest(
            id: scrollRequest.id + 1,
            offset: nextOffset,
            animated: animated
        )
    }

    private func applyOffset(_ proposedOffset: CGFloat) {
        guard let layout else { return }
        let next = layout.clampedOffset(proposedOffset)
        guard next != offset else { return }
        // Card zero is already at the stack position before scrolling starts.
        let previousTop = layout.stackedThrough(offset: offset) ?? 0
        offset = next
        if (layout.stackedThrough(offset: next) ?? 0) != previousTop {
            stackFeedbackToken += 1
        }
    }

}

#endif

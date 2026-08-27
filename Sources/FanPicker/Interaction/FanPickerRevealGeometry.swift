#if canImport(UIKit)
import CoreGraphics
import Foundation

enum FanPickerRevealGeometry {
    static func openingMotionItemCount(
        geometry: ResolvedFanPickerGeometry,
        revealItemCount: Int,
        assetCount: Int,
        configuration: FanPickerConfiguration
    ) -> Int {
        guard configuration.scrolling != nil,
              revealItemCount > 0,
              revealItemCount < assetCount,
              let first = geometry.recentRects(
                count: revealItemCount,
                configuration: configuration
              ).first else {
            return revealItemCount
        }

        let pitch = configuration.recentSize + configuration.recentSpacing
        var count = revealItemCount
        var nextMinX = first.minX + CGFloat(revealItemCount) * pitch
        while count < assetCount, nextMinX < geometry.composerRect.maxX {
            count += 1
            nextMinX += pitch
        }
        return count
    }

    static func visualRects(
        for session: FanPickerController.RevealSession,
        configuration: FanPickerConfiguration,
        now: Date,
        isRevealing: Bool
    ) -> [CGRect] {
        let destinations = session.geometry.recentRects(
            count: session.revealItemCount,
            configuration: configuration
        )
        guard isRevealing else { return destinations }

        let source = CGPoint(
            x: session.geometry.triggerRect.midX,
            y: session.geometry.triggerRect.midY
        )
        let elapsed = max(now.timeIntervalSince(session.startDate), 0)
        let timeline = RevealMotionTimeline(configuration: configuration)

        return destinations.enumerated().map { index, destination in
            let motion = timeline.value(
                source: source,
                destination: CGPoint(x: destination.midX, y: destination.midY),
                index: index,
                time: elapsed
            )
            let size = configuration.recentSize * motion.scale
            return CGRect(
                x: motion.center.x - size / 2,
                y: motion.center.y - size / 2,
                width: size,
                height: size
            )
        }
    }
}
#endif

#if canImport(UIKit)
import SwiftUI

struct RevealMotionTarget {
    let destination: CGPoint
    let settledCenter: CGPoint
    let dismissalStart: RevealMotionValue?
    let dismissalOrder: Int
}

@MainActor
final class RevealMotionRenderer {
    private struct RevealSample {
        let source: CGPoint
        let destination: CGPoint
        let index: Int
        let time: TimeInterval
        let itemCount: Int
    }

    private struct DismissalSample {
        let source: CGPoint
        let target: RevealMotionTarget
        let index: Int
        let time: TimeInterval
        let initialRevealElapsed: TimeInterval
    }

    private var sessionID: UUID?
    private var dismissalKey: Date?
    private var revealTimelines:
        [Int: (destination: CGPoint, timeline: KeyframeTimeline<RevealMotionValue>)] = [:]
    private var dismissalTimelines: [Int: KeyframeTimeline<RevealMotionValue>] = [:]

    func value(
        presentation: FanPickerController.Presentation,
        configuration: FanPickerConfiguration,
        index: Int,
        target: RevealMotionTarget,
        date: Date
    ) -> RevealMotionValue {
        let session = presentation.session
        let timeline = RevealMotionTimeline(configuration: configuration)
        let source = CGPoint(
            x: session.geometry.triggerRect.midX,
            y: session.geometry.triggerRect.midY
        )
        resetIfNeeded(session: session, phase: presentation.phase)

        switch presentation.phase {
        case .revealing:
            return revealValue(
                timeline: timeline,
                sample: RevealSample(
                    source: source,
                    destination: target.destination,
                    index: index,
                    time: max(date.timeIntervalSince(session.startDate), 0),
                    itemCount: session.revealItemCount
                )
            )
        case let .frozen(revealElapsed):
            return revealValue(
                timeline: timeline,
                sample: RevealSample(
                    source: source,
                    destination: target.destination,
                    index: index,
                    time: revealElapsed,
                    itemCount: session.revealItemCount
                )
            )
        case .settled:
            return RevealMotionValue(
                center: target.settledCenter,
                scale: 1,
                opacity: 1
            )
        case let .dismissing(startDate, initialRevealElapsed):
            return dismissalValue(
                timeline: timeline,
                configuration: configuration,
                sample: DismissalSample(
                    source: source,
                    target: target,
                    index: index,
                    time: max(date.timeIntervalSince(startDate), 0),
                    initialRevealElapsed: initialRevealElapsed
                )
            )
        }
    }

    private func revealValue(
        timeline: RevealMotionTimeline,
        sample: RevealSample
    ) -> RevealMotionValue {
        guard sample.index < sample.itemCount else {
            return timeline.trailingPeekValue(
                destination: sample.destination,
                fanItemCount: sample.itemCount,
                time: sample.time
            )
        }
        if sample.time >= timeline.itemDuration(index: sample.index) {
            return RevealMotionValue(
                center: sample.destination,
                scale: 1,
                opacity: 1
            )
        }

        let cached: KeyframeTimeline<RevealMotionValue>
        if let entry = revealTimelines[sample.index],
           entry.destination == sample.destination {
            cached = entry.timeline
        } else {
            cached = timeline.revealTimeline(
                source: sample.source,
                destination: sample.destination,
                index: sample.index
            )
            revealTimelines[sample.index] = (sample.destination, cached)
        }
        return cached.value(time: min(max(sample.time, 0), cached.duration))
    }

    private func dismissalValue(
        timeline: RevealMotionTimeline,
        configuration: FanPickerConfiguration,
        sample: DismissalSample
    ) -> RevealMotionValue {
        if sample.time >= configuration.dismissalDuration {
            return RevealMotionValue(
                center: sample.source,
                scale: configuration.revealInitialScale,
                opacity: 0
            )
        }
        let cached = dismissalTimelines[sample.index] ?? {
            let start = sample.target.dismissalStart ?? timeline.value(
                source: sample.source,
                destination: sample.target.destination,
                index: sample.index,
                time: sample.initialRevealElapsed
            )
            let built = timeline.dismissalTimeline(
                from: start,
                source: sample.source,
                destination: sample.target.dismissalStart != nil
                    ? start.center
                    : sample.target.destination,
                index: sample.target.dismissalOrder
            )
            dismissalTimelines[sample.index] = built
            return built
        }()
        return cached.value(time: min(sample.time, cached.duration))
    }

    private func resetIfNeeded(
        session: FanPickerController.RevealSession,
        phase: FanPickerController.PresentationPhase
    ) {
        if sessionID != session.id {
            sessionID = session.id
            dismissalKey = nil
            revealTimelines.removeAll()
            dismissalTimelines.removeAll()
        }
        if case let .dismissing(startDate, _) = phase, dismissalKey != startDate {
            dismissalKey = startDate
            dismissalTimelines.removeAll()
        }
    }
}
#endif

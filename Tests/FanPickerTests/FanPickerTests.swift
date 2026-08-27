import CoreGraphics
import Foundation
import Testing
@testable import FanPicker

@Suite("Reveal motion")
struct RevealMotionTests {
    private let configuration = FanPickerConfiguration.reference
    private let source = CGPoint(x: 24, y: 220)
    private let destinations = [
        CGPoint(x: 52, y: 112),
        CGPoint(x: 142, y: 112),
        CGPoint(x: 232, y: 112),
        CGPoint(x: 322, y: 112),
    ]

    #if canImport(UIKit)
    @Test("The cached renderer matches the direct timeline")
    @MainActor
    func cachedRendererMatchesDirectTimeline() {
        let renderer = RevealMotionRenderer()
        let timeline = RevealMotionTimeline(configuration: configuration)
        let session = FanPickerController.RevealSession(
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            assets: [],
            frozenAssets: [],
            revealItemCount: destinations.count,
            revealMotionItemCount: destinations.count,
            geometry: ResolvedFanPickerGeometry(
                composerRect: CGRect(x: 0, y: 80, width: 400, height: 200),
                triggerRect: CGRect(
                    x: source.x - 22,
                    y: source.y - 22,
                    width: 44,
                    height: 44
                )
            )
        )

        for (index, destination) in destinations.enumerated() {
            for fraction in [0.0, 0.2, 0.5, 0.8, 1.0, 1.4] {
                let time = configuration.revealDuration * fraction
                let expected = timeline.value(
                    source: source,
                    destination: destination,
                    index: index,
                    time: time
                )
                for _ in 0..<2 {
                    let value = renderer.value(
                        presentation: FanPickerController.Presentation(
                            session: session,
                            phase: .frozen(revealElapsed: time),
                            highlightedID: nil
                        ),
                        configuration: configuration,
                        index: index,
                        target: RevealMotionTarget(
                            destination: destination,
                            settledCenter: destination,
                            dismissalStart: nil,
                            dismissalOrder: index
                        ),
                        date: .now
                    )
                    #expect(abs(value.center.x - expected.center.x) < 0.0001)
                    #expect(abs(value.center.y - expected.center.y) < 0.0001)
                    #expect(abs(value.scale - expected.scale) < 0.0001)
                    #expect(abs(value.opacity - expected.opacity) < 0.0001)
                }
            }
        }
    }

    @Test("The cached renderer matches the direct dismissal")
    @MainActor
    func cachedRendererMatchesDirectDismissal() {
        let renderer = RevealMotionRenderer()
        let timeline = RevealMotionTimeline(configuration: configuration)
        let dismissalStartDate = Date(timeIntervalSinceReferenceDate: 10)
        let session = FanPickerController.RevealSession(
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            assets: [],
            frozenAssets: [],
            revealItemCount: destinations.count,
            revealMotionItemCount: destinations.count,
            geometry: ResolvedFanPickerGeometry(
                composerRect: CGRect(x: 0, y: 80, width: 400, height: 200),
                triggerRect: CGRect(
                    x: source.x - 22,
                    y: source.y - 22,
                    width: 44,
                    height: 44
                )
            )
        )
        let start = RevealMotionValue(
            center: destinations[1],
            scale: 0.95,
            opacity: 0.8
        )

        for fraction in [0.0, 0.3, 0.7, 1.0, 1.3] {
            let time = configuration.dismissalDuration * fraction
            let expected = timeline.dismissalValue(
                from: start,
                source: source,
                destination: start.center,
                index: 1,
                time: time
            )
            let value = renderer.value(
                presentation: FanPickerController.Presentation(
                    session: session,
                    phase: .dismissing(
                        startDate: dismissalStartDate,
                        initialRevealElapsed: configuration.revealDuration
                    ),
                    highlightedID: nil
                ),
                configuration: configuration,
                index: 1,
                target: RevealMotionTarget(
                    destination: destinations[1],
                    settledCenter: destinations[1],
                    dismissalStart: start,
                    dismissalOrder: 1
                ),
                date: dismissalStartDate.addingTimeInterval(time)
            )
            #expect(abs(value.center.x - expected.center.x) < 0.0001)
            #expect(abs(value.center.y - expected.center.y) < 0.0001)
            #expect(abs(value.scale - expected.scale) < 0.0001)
            #expect(abs(value.opacity - expected.opacity) < 0.0001)
        }
    }
    #endif

    @Test("Every item starts behind the trigger")
    func startsAtTrigger() {
        let timeline = RevealMotionTimeline(configuration: configuration)

        for (index, destination) in destinations.enumerated() {
            let value = timeline.value(
                source: source,
                destination: destination,
                index: index,
                time: 0
            )

            #expect(value.center == source)
            #expect(value.scale == configuration.revealInitialScale)
            #expect(value.opacity == 0)
        }
    }

    @Test("Every item lands exactly in its slot")
    func landsInDestination() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let end = timeline.duration(itemCount: destinations.count)

        for (index, destination) in destinations.enumerated() {
            let value = timeline.value(
                source: source,
                destination: destination,
                index: index,
                time: end
            )

            #expect(value.center == destination)
            #expect(abs(value.scale - 1) < 0.0001)
            #expect(abs(value.opacity - 1) < 0.0001)
        }
    }

    @Test("The fourth item stays within the measured reference timing window")
    func usesMeasuredRevealDuration() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let duration = timeline.duration(itemCount: destinations.count)

        #expect(duration >= 0.46)
        #expect(duration <= 0.49)
    }

    @Test("The trailing peek enters quietly within the fan timeline")
    func trailingPeekUsesRestrainedMotion() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let destination = CGPoint(x: 412, y: 112)
        let duration = timeline.duration(itemCount: destinations.count)
        let initial = timeline.trailingPeekValue(
            destination: destination,
            fanItemCount: destinations.count,
            time: 0
        )
        let final = timeline.trailingPeekValue(
            destination: destination,
            fanItemCount: destinations.count,
            time: duration
        )

        #expect(initial.center.x == destination.x + 12)
        #expect(initial.center.y == destination.y)
        #expect(initial.opacity == 0)
        #expect(final.center == destination)
        #expect(final.scale == 1)
        #expect(final.opacity == 1)
    }

    @Test("The launch passes above the final row")
    func overshootsVertically() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let value = timeline.value(
            source: source,
            destination: destinations[0],
            index: 0,
            time: configuration.revealDuration * 0.25
        )

        #expect(value.center.y < destinations[0].y)
    }

    @Test("The stack opens toward the top right")
    func opensStackTowardTopRight() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let time = configuration.revealDuration * 0.20

        let leading = timeline.value(
            source: source,
            destination: destinations[0],
            index: 0,
            time: time
        )
        let trailing = timeline.value(
            source: source,
            destination: destinations[3],
            index: 3,
            time: time
        )

        #expect(leading.center != source)
        #expect(trailing.center != source)
        #expect(leading.opacity > 0)
        #expect(trailing.opacity > 0)
        #expect(trailing.center.x > leading.center.x)
        #expect(trailing.center.y < leading.center.y)
    }

    @Test("The row passes its slots before settling back")
    func overshootsHorizontally() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let anticipationTime = configuration.revealDuration * 0.55

        for (index, destination) in destinations.enumerated() {
            let value = timeline.value(
                source: source,
                destination: destination,
                index: index,
                time: anticipationTime
            )

            #expect(value.center.x > destination.x)
            #expect(value.center.x - destination.x >= 2)
            #expect(value.center.x - destination.x <= 4)
            #expect(abs(value.center.y - destination.y) < 0.001)
        }
    }

    @Test("The settle starts without a hard kick")
    func startsSettleSoftly() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let startTime = configuration.revealDuration * 0.55
        let start = timeline.value(
            source: source,
            destination: destinations[0],
            index: 0,
            time: startTime
        )
        let nextFrame = timeline.value(
            source: source,
            destination: destinations[0],
            index: 0,
            time: startTime + 1.0 / 60.0
        )

        #expect(abs(nextFrame.center.x - start.center.x) < 2.5)
    }

    @Test("Dismissal leaves the row gently without moving right")
    func dismissalStartsSoftly() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let frameDuration = 1.0 / 60.0

        for (index, destination) in destinations.enumerated() {
            let settled = RevealMotionValue(
                center: destination,
                scale: 1,
                opacity: 1
            )
            let nextFrame = timeline.dismissalValue(
                from: settled,
                source: source,
                destination: destination,
                index: index,
                time: frameDuration
            )
            let firstFrameTravel = distance(
                from: settled.center,
                to: nextFrame.center
            )

            #expect(nextFrame.center.x <= settled.center.x)
            #expect(firstFrameTravel > 1)
            #expect(firstFrameTravel < 12)

            stride(
                from: frameDuration,
                through: timeline.dismissalDuration(itemCount: destinations.count),
                by: frameDuration
            ).forEach { time in
                let value = timeline.dismissalValue(
                    from: settled,
                    source: source,
                    destination: destination,
                    index: index,
                    time: time
                )
                #expect(value.center.x <= destination.x)
            }
        }
    }

    @Test("Dismissal follows the shared fan path")
    func dismissalUsesSharedPath() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let settled = RevealMotionValue(
            center: destinations[3],
            scale: 1,
            opacity: 1
        )
        let gathered = timeline.dismissalValue(
            from: settled,
            source: source,
            destination: destinations[3],
            index: 3,
            time: configuration.dismissalDuration * 0.24
        )

        #expect(gathered.center.x < destinations[3].x)
        #expect(gathered.center.y < destinations[3].y)
        #expect(gathered.opacity == 1)
    }

    @Test("Dismissal keeps moving through both path joins")
    func dismissalMaintainsMomentum() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let frameDuration = 1.0 / 120.0
        let joins = [
            configuration.dismissalDuration * 0.24,
            configuration.dismissalDuration * 0.48,
        ]

        for (index, destination) in destinations.enumerated() {
            let settled = RevealMotionValue(
                center: destination,
                scale: 1,
                opacity: 1
            )

            for join in joins {
                let before = timeline.dismissalValue(
                    from: settled,
                    source: source,
                    destination: destination,
                    index: index,
                    time: join - frameDuration
                )
                let at = timeline.dismissalValue(
                    from: settled,
                    source: source,
                    destination: destination,
                    index: index,
                    time: join
                )
                let after = timeline.dismissalValue(
                    from: settled,
                    source: source,
                    destination: destination,
                    index: index,
                    time: join + frameDuration
                )
                let incoming = distance(from: before.center, to: at.center)
                let outgoing = distance(from: at.center, to: after.center)
                let momentumRatio = min(incoming, outgoing) / max(incoming, outgoing)

                #expect(incoming > 0.25)
                #expect(outgoing > 0.25)
                #expect(
                    momentumRatio > 0.35,
                    "Item \(index) loses momentum at \(join) seconds: \(incoming) in, \(outgoing) out."
                )
            }
        }
    }

    @Test("Dismissal stays within the measured reference timing window")
    func dismissalUsesReferenceDuration() {
        let duration = RevealMotionTimeline(configuration: configuration)
            .dismissalDuration(itemCount: destinations.count)

        #expect(duration >= 0.20)
        #expect(duration <= 0.22)
    }

    @Test("Dismissal ends behind the trigger")
    func dismissalEndsAtTrigger() {
        let timeline = RevealMotionTimeline(configuration: configuration)
        let end = timeline.dismissalDuration(itemCount: destinations.count)

        for (index, destination) in destinations.enumerated() {
            let value = timeline.dismissalValue(
                from: RevealMotionValue(
                    center: destination,
                    scale: 1,
                    opacity: 1
                ),
                source: source,
                destination: destination,
                index: index,
                time: end
            )

            #expect(value.center == source)
            #expect(value.scale == configuration.revealInitialScale)
            #expect(value.opacity == 0)
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

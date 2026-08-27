import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct RevealMotionValue: Animatable, Equatable {
    var center: CGPoint
    var scale: CGFloat
    var opacity: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(center.x, center.y),
                AnimatablePair(scale, opacity)
            )
        }
        set {
            center = CGPoint(x: newValue.first.first, y: newValue.first.second)
            scale = newValue.second.first
            opacity = newValue.second.second
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct RevealMotionTimeline {
    let configuration: FanPickerConfiguration

    private struct Waypoints {
        let launch: CGPoint
        let spread: CGPoint
        let anticipation: CGPoint
    }

    func value(
        source: CGPoint,
        destination: CGPoint,
        index: Int,
        time: TimeInterval
    ) -> RevealMotionValue {
        if time <= 0 {
            return RevealMotionValue(
                center: source,
                scale: configuration.revealInitialScale,
                opacity: 0
            )
        }

        if time >= itemDuration(index: index) {
            return RevealMotionValue(center: destination, scale: 1, opacity: 1)
        }

        let timeline = revealTimeline(
            source: source,
            destination: destination,
            index: index
        )
        return timeline.value(time: min(max(time, 0), timeline.duration))
    }

    func itemDuration(index: Int) -> TimeInterval {
        configuration.revealDuration
            + Double(max(index, 0)) * configuration.revealItemStagger
    }

    func duration(itemCount: Int) -> TimeInterval {
        configuration.revealDuration
            + Double(max(itemCount - 1, 0)) * configuration.revealItemStagger
    }

    func trailingPeekValue(
        destination: CGPoint,
        fanItemCount: Int,
        time: TimeInterval
    ) -> RevealMotionValue {
        let revealDuration = duration(itemCount: fanItemCount)
        let startTime = revealDuration * 0.46
        guard time > startTime, revealDuration > startTime else {
            return RevealMotionValue(
                center: CGPoint(x: destination.x + 12, y: destination.y),
                scale: 0.96,
                opacity: 0
            )
        }

        let progress = min(
            max((time - startTime) / (revealDuration - startTime), 0),
            1
        )
        let eased = progress * progress * (3 - 2 * progress)
        return RevealMotionValue(
            center: CGPoint(
                x: destination.x + 12 * (1 - eased),
                y: destination.y
            ),
            scale: 0.96 + 0.04 * eased,
            opacity: eased
        )
    }

    func dismissalValue(
        from start: RevealMotionValue,
        source: CGPoint,
        destination: CGPoint,
        index: Int,
        time: TimeInterval
    ) -> RevealMotionValue {
        if time <= 0 {
            return start
        }

        let itemDuration = configuration.dismissalDuration
        if time >= itemDuration {
            return RevealMotionValue(
                center: source,
                scale: configuration.revealInitialScale,
                opacity: 0
            )
        }

        let timeline = dismissalTimeline(
            from: start,
            source: source,
            destination: destination,
            index: index
        )
        return timeline.value(time: min(max(time, 0), timeline.duration))
    }

    func dismissalDuration(itemCount: Int) -> TimeInterval {
        itemCount > 0 ? configuration.dismissalDuration : 0
    }

    func revealTimeline(
        source: CGPoint,
        destination: CGPoint,
        index: Int
    ) -> KeyframeTimeline<RevealMotionValue> {
        let safeIndex = max(index, 0)
        let stagger = Double(safeIndex) * configuration.revealItemStagger
        let launchDuration = configuration.revealDuration * 0.20
        let spreadDuration = configuration.revealDuration * 0.23
        let anticipationDuration = configuration.revealDuration * 0.12
        let settleDuration = configuration.revealDuration
            - launchDuration
            - spreadDuration
            - anticipationDuration
            + stagger
        let waypoints = waypoints(
            source: source,
            destination: destination,
            index: safeIndex
        )

        return KeyframeTimeline(
            initialValue: RevealMotionValue(
                center: source,
                scale: configuration.revealInitialScale,
                opacity: 0
            )
        ) {
            KeyframeTrack(\.center) {
                CubicKeyframe(
                    waypoints.launch,
                    duration: launchDuration,
                    startVelocity: .zero
                )
                CubicKeyframe(waypoints.spread, duration: spreadDuration)
                CubicKeyframe(
                    waypoints.anticipation,
                    duration: anticipationDuration
                )
                SpringKeyframe(
                    destination,
                    duration: settleDuration,
                    spring: Spring(
                        duration: settleDuration,
                        bounce: configuration.revealSettleBounce
                    )
                )
            }

            KeyframeTrack(\.scale) {
                CubicKeyframe(0.68, duration: launchDuration)
                CubicKeyframe(0.96, duration: spreadDuration)
                CubicKeyframe(
                    configuration.revealPeakScale,
                    duration: anticipationDuration
                )
                SpringKeyframe(
                    1,
                    duration: settleDuration,
                    spring: Spring(
                        duration: settleDuration,
                        bounce: configuration.revealSettleBounce
                    )
                )
            }

            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: launchDuration * 0.25)
                LinearKeyframe(
                    1,
                    duration: launchDuration * 0.75
                        + spreadDuration
                        + anticipationDuration
                        + settleDuration
                )
            }
        }
    }

    func dismissalTimeline(
        from start: RevealMotionValue,
        source: CGPoint,
        destination: CGPoint,
        index: Int
    ) -> KeyframeTimeline<RevealMotionValue> {
        let safeIndex = max(index, 0)
        let gatherDuration = configuration.dismissalDuration * 0.24
        let stackDuration = configuration.dismissalDuration * 0.24
        let tuckDuration = configuration.dismissalDuration
            - gatherDuration
            - stackDuration
        let waypoints = waypoints(
            source: source,
            destination: destination,
            index: safeIndex
        )
        let initialCenterVelocity = CGPoint(
            x: (waypoints.spread.x - start.center.x) / gatherDuration * 0.40,
            y: (waypoints.spread.y - start.center.y) / gatherDuration * 0.40
        )
        let gatherCenterVelocity = CGPoint(
            x: (waypoints.spread.x - start.center.x) / gatherDuration * 1.60,
            y: (waypoints.spread.y - start.center.y) / gatherDuration * 1.60
        )
        let tuckCenterVelocity = CGPoint(
            x: (source.x - waypoints.launch.x) / tuckDuration * 0.75,
            y: (source.y - waypoints.launch.y) / tuckDuration * 0.75
        )
        let initialScaleVelocity = (0.96 - start.scale) / gatherDuration * 0.40
        let gatherScaleVelocity = (0.96 - start.scale) / gatherDuration * 1.60
        let tuckScaleVelocity = (
            configuration.revealInitialScale - 0.68
        ) / tuckDuration * 0.75

        return KeyframeTimeline(initialValue: start) {
            KeyframeTrack(\.center) {
                CubicKeyframe(
                    waypoints.spread,
                    duration: gatherDuration,
                    startVelocity: initialCenterVelocity,
                    endVelocity: gatherCenterVelocity
                )
                CubicKeyframe(
                    waypoints.launch,
                    duration: stackDuration,
                    startVelocity: gatherCenterVelocity,
                    endVelocity: tuckCenterVelocity
                )
                CubicKeyframe(
                    source,
                    duration: tuckDuration,
                    startVelocity: tuckCenterVelocity,
                    endVelocity: .zero
                )
            }

            KeyframeTrack(\.scale) {
                CubicKeyframe(
                    0.96,
                    duration: gatherDuration,
                    startVelocity: initialScaleVelocity,
                    endVelocity: gatherScaleVelocity
                )
                CubicKeyframe(
                    0.68,
                    duration: stackDuration,
                    startVelocity: gatherScaleVelocity,
                    endVelocity: tuckScaleVelocity
                )
                CubicKeyframe(
                    configuration.revealInitialScale,
                    duration: tuckDuration,
                    startVelocity: tuckScaleVelocity,
                    endVelocity: 0
                )
            }

            KeyframeTrack(\.opacity) {
                LinearKeyframe(
                    start.opacity,
                    duration: gatherDuration + stackDuration
                )
                LinearKeyframe(0, duration: tuckDuration)
            }
        }
    }

    private func waypoints(
        source: CGPoint,
        destination: CGPoint,
        index: Int
    ) -> Waypoints {
        let fanOffset = CGFloat(max(index, 0))

        return Waypoints(
            launch: CGPoint(
                x: source.x + 8 + fanOffset * 5,
                y: destination.y - configuration.revealApex - fanOffset * 4
            ),
            spread: CGPoint(
                x: interpolate(source.x, destination.x, progress: 0.84)
                    + fanOffset * 2,
                y: destination.y
                    - configuration.revealApex * 0.34
                    - fanOffset * 3
            ),
            anticipation: CGPoint(
                x: destination.x + horizontalOvershoot,
                y: destination.y
            )
        )
    }

    private var horizontalOvershoot: CGFloat {
        min(max(configuration.recentSpacing * 0.3, 2), 4)
    }

    private func interpolate(
        _ start: CGFloat,
        _ end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}

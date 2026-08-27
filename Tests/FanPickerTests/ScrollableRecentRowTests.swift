#if canImport(UIKit)
import Testing
import UIKit
@testable import FanPicker

@Suite("Scrolling recent-photo row")
struct ScrollableRecentRowTests {
    private let layout = ScrollableRecentRowLayout(
        viewport: CGRect(x: 20, y: 700, width: 390, height: 64),
        rowCenterY: 620,
        leadingCenterX: 70,
        itemSize: 80,
        itemSpacing: 10,
        assetCount: 20,
        stackDepth: 3
    )

    @Test("The initial row has no pinned stack")
    func initialRowIsUnstacked() {
        #expect(layout.stackedIndices(offset: 0).isEmpty)
        #expect(layout.visibleMainIndices(offset: 0) == [0, 1, 2, 3, 4])
        #expect(layout.center(index: 0, offset: 0) == CGPoint(x: 70, y: 620))
    }

    @Test("Photos collect in a bounded leading stack")
    func stackStaysBounded() {
        let offset = layout.itemPitch * 5

        #expect(layout.stackedIndices(offset: offset) == [3, 4, 5])
        #expect(layout.visibleMainIndices(offset: offset).first == 6)
        #expect(layout.selectableRect(index: 5, offset: offset) == nil)
        #expect(layout.selectableRect(index: 6, offset: offset) != nil)
    }

    @Test("Collected photos form a graded pile at the leading edge")
    func collectedPhotosFormAGradedPile() {
        let offset = layout.itemPitch * 2
        let topIndex = 2

        #expect(layout.stackedIndices(offset: offset) == [0, 1, 2])
        for index in 0...topIndex {
            let center = layout.center(index: index, offset: offset)
            #expect(center.x == layout.leadingCenterX)
            #expect(center.y == layout.rowCenterY)
        }

        let deep = layout.stackPlacement(index: 0, offset: offset)
        let middle = layout.stackPlacement(index: 1, offset: offset)
        let top = layout.stackPlacement(index: 2, offset: offset)
        #expect(top?.scale == 1)
        #expect(abs((middle?.scale ?? 0) - 0.95) < 0.0001)
        #expect(abs((deep?.scale ?? 0) - 0.90) < 0.0001)
        #expect(deep?.opacity == 1)
    }

    @Test("Each incoming photo travels above the existing stack")
    func incomingPhotoBecomesTopCard() {
        #expect(layout.zIndex(index: 0) < layout.zIndex(index: 1))
        #expect(layout.zIndex(index: 1) < layout.zIndex(index: 2))
        #expect(layout.zIndex(index: 2) < layout.zIndex(index: 3))
    }

    @Test("A photo reaches the pinned frame without a position jump")
    func pinningIsContinuous() {
        let threshold = layout.itemPitch * 2
        let before = layout.center(index: 2, offset: threshold - 0.01)
        let pinned = layout.center(index: 2, offset: threshold)

        #expect(abs(before.x - pinned.x) < 0.02)
        #expect(abs(before.y - pinned.y) < 0.01)
    }

    @Test("Stack capture decelerates into the pinned frame")
    func stackCaptureEasesPosition() {
        let distance = layout.stackCaptureDistance
        let entering = layout.stackCapture(
            rawCenter: CGPoint(
                x: layout.leadingCenterX + distance,
                y: layout.rowCenterY
            )
        )
        let halfway = layout.stackCapture(
            rawCenter: CGPoint(
                x: layout.leadingCenterX + distance / 2,
                y: layout.rowCenterY
            )
        )
        let pinned = layout.stackCapture(
            rawCenter: CGPoint(
                x: layout.leadingCenterX,
                y: layout.rowCenterY
            )
        )

        #expect(entering.center.x == layout.leadingCenterX + distance)
        #expect(entering.progress == 0)
        #expect(halfway.center.x > layout.leadingCenterX)
        #expect(halfway.center.x < layout.leadingCenterX + distance / 2)
        #expect(halfway.center.y == layout.rowCenterY)
        #expect(halfway.progress == 0.5)
        #expect(pinned.center.x == layout.leadingCenterX)
        #expect(pinned.center.y == layout.rowCenterY)
        #expect(pinned.progress == 1)
    }

    @Test("The incoming photo compresses the current stack top")
    func incomingPhotoPushesTopCardDown() {
        let offset = layout.itemPitch - layout.stackCaptureDistance / 2
        let currentTop = layout.stackPlacement(index: 0, offset: offset)

        #expect((currentTop?.scale ?? 1) < 1)
        #expect((currentTop?.scale ?? 0) > 0.95)
        #expect(layout.stackPlacement(index: 1, offset: offset) == nil)
    }

    @Test("The final photo remains visible at the aligned scroll boundary")
    func finalPhotoStopsInsideViewport() {
        let center = layout.rawCenter(
            index: layout.assetCount - 1,
            offset: layout.maximumOffset
        )
        let trailingCenter = layout.viewport.maxX - layout.itemSize / 2

        #expect(center.x <= trailingCenter)
        #expect(trailingCenter - center.x == layout.terminalAlignmentInset)
        #expect(layout.clampedOffset(.greatestFiniteMagnitude) == layout.maximumOffset)
    }

    @Test("The terminal offset finishes a card exactly on the stack")
    func terminalOffsetAlignsStack() {
        guard let top = layout.stackedThrough(offset: layout.maximumOffset) else {
            Issue.record("Expected a terminal stack")
            return
        }
        let capture = layout.stackCapture(
            rawCenter: layout.rawCenter(
                index: top,
                offset: layout.maximumOffset
            )
        )

        #expect(capture.center.x == layout.leadingCenterX)
        #expect(capture.center.y == layout.rowCenterY)
        #expect(capture.progress == 1)

        let placement = layout.stackPlacement(
            index: top,
            offset: layout.maximumOffset
        )
        #expect(placement?.scale == 1)
        #expect(placement?.opacity == 1)
    }

    @Test("The deepest stack card fades as a new card seats")
    func stackFadesDeepestCardContinuously() {
        let midCapture = layout.itemPitch * 4 - layout.stackCaptureDistance / 2
        let fading = layout.stackPlacement(index: 1, offset: midCapture)
        #expect((fading?.opacity ?? 1) > 0)
        #expect((fading?.opacity ?? 1) < 1)

        let seated = layout.stackPlacement(index: 1, offset: layout.itemPitch * 4)
        #expect(seated?.opacity == 0)
        #expect(
            layout.stackPlacement(index: 2, offset: layout.itemPitch * 4)?
                .opacity == 1
        )
    }

    @Test("The pile shadow forms and clears without jumps")
    func stackShadowIsContinuous() {
        #expect(layout.stackShadowStrength(index: 0, offset: 0) == 0)

        let midCapture = layout.itemPitch - layout.stackCaptureDistance / 2
        #expect(layout.stackShadowStrength(index: 0, offset: midCapture) == 0.5)
        #expect(layout.stackShadowStrength(index: 1, offset: midCapture) == 0.5)

        let deepOffset = layout.itemPitch * 2
        #expect(layout.stackShadowStrength(index: 2, offset: deepOffset) == 1)
        #expect(layout.stackShadowStrength(index: 4, offset: deepOffset) == 0)
    }

    @Test("Collecting and releasing cards ticks the stack haptic")
    @MainActor
    func stackChangesTickHaptics() {
        let controller = ScrollableRecentRowController()
        controller.configure(
            sessionID: UUID(),
            geometry: ResolvedFanPickerGeometry(
                composerRect: CGRect(x: 20, y: 700, width: 390, height: 100),
                triggerRect: CGRect(x: 36, y: 730, width: 44, height: 44)
            ),
            assetCount: 20,
            configuration: FanPickerConfiguration(
                scrolling: FanPickerScrollingConfiguration()
            )
        )
        guard let pitch = controller.layout?.itemPitch else {
            Issue.record("Expected a configured layout")
            return
        }
        let baseline = controller.stackFeedbackToken

        controller.beginDrag()
        controller.updateDrag(translation: -(pitch + 5))
        #expect(controller.stackFeedbackToken == baseline + 1)

        controller.updateDrag(translation: -(pitch + 10))
        #expect(controller.stackFeedbackToken == baseline + 1)

        controller.updateDrag(translation: -(pitch * 2 + 5))
        #expect(controller.stackFeedbackToken == baseline + 2)

        controller.updateDrag(translation: -(pitch + 5))
        #expect(controller.stackFeedbackToken == baseline + 3)
    }

    @Test("Dismissal starts from the stack's visual state")
    @MainActor
    func dismissalCapturesStackState() {
        let controller = ScrollableRecentRowController()
        controller.configure(
            sessionID: UUID(),
            geometry: ResolvedFanPickerGeometry(
                composerRect: CGRect(x: 20, y: 700, width: 390, height: 100),
                triggerRect: CGRect(x: 36, y: 730, width: 44, height: 44)
            ),
            assetCount: 20,
            configuration: FanPickerConfiguration(
                scrolling: FanPickerScrollingConfiguration()
            )
        )
        guard let rowLayout = controller.layout else {
            Issue.record("Expected a configured layout")
            return
        }
        controller.beginDrag()
        controller.updateDrag(translation: -rowLayout.itemPitch * 3)
        controller.prepareDismissal(revealItemCount: 4, usesCurrentLayout: true)

        guard let top = rowLayout.stackedThrough(offset: controller.offset) else {
            Issue.record("Expected a stacked photo")
            return
        }
        let topStart = controller.dismissalStartValues[top]
        let buriedStart = controller.dismissalStartValues[top - 1]
        #expect(topStart?.scale == 1)
        #expect((buriedStart?.scale ?? 1) < 1)
        #expect(buriedStart?.center == topStart?.center)
    }

    @Test("The native row requests an exact return to its leading edge")
    @MainActor
    func nativeReturnToStartUsesAPointRequest() {
        let controller = ScrollableRecentRowController()
        let configuration = FanPickerConfiguration(
            scrolling: FanPickerScrollingConfiguration()
        )
        controller.configure(
            sessionID: UUID(),
            geometry: ResolvedFanPickerGeometry(
                composerRect: CGRect(x: 20, y: 700, width: 390, height: 100),
                triggerRect: CGRect(x: 36, y: 730, width: 44, height: 44)
            ),
            assetCount: 20,
            configuration: configuration
        )
        controller.activateNativeScrolling()
        controller.updateNativeOffset(180)
        let requestID = controller.scrollRequest.id

        controller.scrollToStart()

        #expect(controller.offset == 0)
        #expect(controller.scrollRequest.offset == 0)
        #expect(controller.scrollRequest.id == requestID + 1)
    }

}

@Suite("Scrolling configuration")
struct ScrollingConfigurationTests {
    @Test("Invalid values resolve to safe limits")
    func invalidValuesResolveSafely() {
        let configuration = FanPickerScrollingConfiguration(
            assetLimit: -1,
            prefetchDistance: -2,
            stackDepth: 0,
            edgeActivationWidth: 0,
            maximumEdgeScrollSpeed: -1
        )

        #expect(configuration.resolvedAssetLimit == 0)
        #expect(configuration.resolvedPrefetchDistance == 0)
        #expect(configuration.resolvedStackDepth == 1)
        #expect(configuration.resolvedEdgeActivationWidth == 1)
        #expect(configuration.resolvedMaximumEdgeScrollSpeed == 0)
    }
}
#endif

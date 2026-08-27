#if canImport(UIKit)
import Testing
import UIKit
@testable import FanPicker

@Suite("Picker controller")
struct FanPickerControllerTests {
    private let configuration = FanPickerConfiguration.reference
    private let geometry = ResolvedFanPickerGeometry(
        composerRect: CGRect(x: 20, y: 700, width: 390, height: 64),
        triggerRect: CGRect(x: 32, y: 712, width: 40, height: 40)
    )
    private let startDate = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("Hit testing follows an item while reveal is still running")
    @MainActor
    func selectsDuringReveal() {
        let controller = makeController()
        let assets = makeAssets()
        let elapsed = 0.18

        controller.begin(
            assets: assets,
            configuration: configuration,
            now: startDate
        )
        controller.updateHover(
            at: revealCenter(index: 2, elapsed: elapsed),
            configuration: configuration,
            now: startDate.addingTimeInterval(elapsed)
        )

        #expect(controller.releaseSelection()?.id == assets[2].id)
        #expect(controller.hoverFeedbackToken == 1)
        controller.cancelImmediately()
    }

    @Test("Release presentation freezes the sampled reveal time")
    @MainActor
    func freezesReleasePresentation() {
        let controller = makeController()
        let assets = makeAssets()
        let elapsed = 0.16
        let releaseDate = startDate.addingTimeInterval(elapsed)

        controller.begin(
            assets: assets,
            configuration: configuration,
            now: startDate
        )
        controller.updateHover(
            at: revealCenter(index: 1, elapsed: elapsed),
            configuration: configuration,
            now: releaseDate
        )

        guard let presentation = controller.frozenPresentation(now: releaseDate),
              case let .frozen(revealElapsed) = presentation.phase else {
            Issue.record("Expected a frozen reveal presentation")
            controller.cancelImmediately()
            return
        }

        #expect(abs(revealElapsed - elapsed) < 0.0001)
        #expect(presentation.highlightedID == assets[1].id)
        controller.cancelImmediately()
    }

    @Test("A second hold cannot replace an active reveal")
    @MainActor
    func rejectsActiveSessionReentry() {
        let controller = makeController()
        let assets = makeAssets()

        controller.begin(
            assets: assets,
            configuration: configuration,
            now: startDate
        )
        guard case let .revealing(firstSession, _) = controller.state else {
            Issue.record("Expected an active reveal")
            return
        }

        controller.begin(
            assets: Array(assets.reversed()),
            configuration: configuration,
            now: startDate.addingTimeInterval(0.05)
        )
        guard case let .revealing(currentSession, _) = controller.state else {
            Issue.record("Expected the original reveal to remain active")
            controller.cancelImmediately()
            return
        }

        #expect(currentSession.id == firstSession.id)
        #expect(controller.revealFeedbackToken == 1)
        controller.cancelImmediately()
    }

    @Test("Reduce Motion opens without a ballistic reveal")
    @MainActor
    func opensImmediatelyForReduceMotion() {
        let controller = makeController()

        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )

        guard case .open = controller.state else {
            Issue.record("Expected the picker to open immediately")
            return
        }
        #expect(controller.isActive)
        #expect(controller.showsCloseTrigger)
        controller.cancelImmediately()
    }

    @Test("A visible trailing peek participates in the scrolling reveal")
    @MainActor
    func scrollingRevealIncludesTrailingPeek() {
        let controller = makeController()
        let assets = (0..<8).map { index in
            RecentPhotoAsset(id: "scrolling-asset-\(index)", image: UIImage())
        }
        var scrollingConfiguration = configuration
        scrollingConfiguration.scrolling = FanPickerScrollingConfiguration()

        controller.begin(
            assets: assets,
            configuration: scrollingConfiguration,
            now: startDate
        )

        guard case let .revealing(session, _) = controller.state else {
            Issue.record("Expected an active reveal")
            return
        }
        #expect(session.revealItemCount == 4)
        #expect(session.revealMotionItemCount == 5)
        controller.cancelImmediately()
    }

    @Test("Commit clears the reveal synchronously")
    @MainActor
    func commitsToIdle() {
        let controller = makeController()

        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            now: startDate
        )
        controller.commitSelection()

        guard case .idle = controller.state else {
            Issue.record("Expected commit to clear transient state")
            return
        }
        #expect(!controller.isActive)
        #expect(controller.presentation == nil)
    }

    @Test("Visible previews do not swap during an active fan")
    @MainActor
    func activeFanFreezesPreviewUpgrades() {
        let controller = makeController()
        let initial = UIImage()
        let replacement = UIImage()
        let asset = RecentPhotoAsset(id: "asset", image: initial)

        controller.begin(
            assets: [asset],
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )
        asset.applyPreview(replacement, quality: .final)

        #expect(asset.image === initial)

        controller.cancelImmediately()

        #expect(asset.image === replacement)
    }

    @Test("A selected preview stays frozen through controller commit")
    @MainActor
    func selectedPreviewRemainsFrozenForFlight() {
        let controller = makeController()
        let initial = UIImage()
        let replacement = UIImage()
        let asset = RecentPhotoAsset(id: "asset", image: initial)

        controller.begin(
            assets: [asset],
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )
        asset.beginImageFreeze()
        asset.applyPreview(replacement, quality: .final)
        controller.commitSelection()

        #expect(asset.image === initial)

        asset.endImageFreeze()

        #expect(asset.image === replacement)
    }

    @Test("Dismissal preserves the current reveal sample")
    @MainActor
    func dismissesFromCurrentPresentation() {
        let controller = makeController()
        let elapsed = 0.17

        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            now: startDate
        )
        controller.dismiss(
            configuration: configuration,
            now: startDate.addingTimeInterval(elapsed)
        )

        guard case let .dismissing(session) = controller.state else {
            Issue.record("Expected a dismissing session")
            return
        }
        #expect(abs(session.initialRevealElapsed - elapsed) < 0.0001)
        #expect(controller.isActive)
        #expect(!controller.showsCloseTrigger)
        #expect(controller.releaseSelection() == nil)
        controller.cancelImmediately()
    }

    @Test("Releasing outside keeps the picker open")
    @MainActor
    func releaseOutsidePreservesOpenPicker() {
        let controller = makeController()

        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )
        controller.updateHover(
            at: CGPoint(x: -1_000, y: -1_000),
            configuration: configuration,
            now: startDate
        )

        #expect(controller.releaseSelection() == nil)
        #expect(controller.isActive)
        #expect(controller.showsCloseTrigger)
        guard case .open = controller.state else {
            Issue.record("Expected the picker to remain open")
            return
        }
        controller.cancelImmediately()
    }

    @Test("Sticky hit geometry prevents boundary flicker")
    @MainActor
    func hoverUsesHysteresis() {
        let controller = makeController()
        let assets = makeAssets()
        let rects = geometry.recentRects(
            count: assets.count,
            configuration: configuration
        )

        controller.begin(
            assets: assets,
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )
        controller.updateHover(
            at: CGPoint(x: rects[0].midX, y: rects[0].midY),
            configuration: configuration,
            now: startDate
        )
        controller.updateHover(
            at: CGPoint(
                x: rects[0].maxX + configuration.recentSpacing * 0.75,
                y: rects[0].midY
            ),
            configuration: configuration,
            now: startDate
        )

        #expect(controller.releaseSelection()?.id == assets[0].id)
        #expect(controller.hoverFeedbackToken == 1)

        controller.updateHover(
            at: CGPoint(x: rects[1].midX, y: rects[1].midY),
            configuration: configuration,
            now: startDate
        )
        #expect(controller.releaseSelection()?.id == assets[1].id)
        #expect(controller.hoverFeedbackToken == 2)
        controller.cancelImmediately()
    }

    @MainActor
    private func makeController() -> FanPickerController {
        let controller = FanPickerController()
        controller.updateGeometry(geometry)
        return controller
    }

    @MainActor
    private func makeAssets() -> [RecentPhotoAsset] {
        (0..<4).map { index in
            RecentPhotoAsset(id: "asset-\(index)", image: UIImage())
        }
    }

    private func revealCenter(index: Int, elapsed: TimeInterval) -> CGPoint {
        let destination = geometry.recentRects(
            count: 4,
            configuration: configuration
        )[index]
        let source = CGPoint(
            x: geometry.triggerRect.midX,
            y: geometry.triggerRect.midY
        )

        return RevealMotionTimeline(configuration: configuration).value(
            source: source,
            destination: CGPoint(
                x: destination.midX,
                y: destination.midY
            ),
            index: index,
            time: elapsed
        ).center
    }
}
#endif

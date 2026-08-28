#if canImport(UIKit)
import Testing
import UIKit
@testable import FanPicker

@Suite("Recent fan interaction gating")
struct RecentFanOverlayContextTests {
    private let configuration = FanPickerConfiguration.reference
    private let geometry = ResolvedFanPickerGeometry(
        composerRect: CGRect(x: 20, y: 700, width: 390, height: 64),
        triggerRect: CGRect(x: 32, y: 712, width: 40, height: 40)
    )
    private let startDate = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("Selection is available while the fan is revealing")
    @MainActor
    func selectionDuringReveal() {
        let controller = makeController()
        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            now: startDate
        )

        guard let presentation = controller.presentation else {
            Issue.record("Expected a reveal presentation")
            return
        }
        let context = makeContext(presentation: presentation)

        #expect(context.allowsSelection)
        #expect(!context.allowsScrolling)
        controller.cancelImmediately()
    }

    @Test("Selection and scrolling are available after the fan settles")
    @MainActor
    func interactionAfterSettling() {
        let controller = makeController()
        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            reduceMotion: true,
            now: startDate
        )

        guard let presentation = controller.presentation else {
            Issue.record("Expected a settled presentation")
            return
        }
        let context = makeContext(presentation: presentation)

        #expect(context.allowsSelection)
        #expect(context.allowsScrolling)
        controller.cancelImmediately()
    }

    @Test("Interaction is unavailable while the fan dismisses")
    @MainActor
    func noInteractionDuringDismissal() {
        let controller = makeController()
        controller.begin(
            assets: makeAssets(),
            configuration: configuration,
            now: startDate
        )
        controller.dismiss(
            configuration: configuration,
            now: startDate.addingTimeInterval(0.1)
        )

        guard let presentation = controller.presentation else {
            Issue.record("Expected a dismissal presentation")
            return
        }
        let context = makeContext(presentation: presentation)

        #expect(!context.allowsSelection)
        #expect(!context.allowsScrolling)
        controller.cancelImmediately()
    }

    @Test("An attachment transition blocks additional interaction")
    @MainActor
    func noInteractionDuringAttachmentTransition() {
        let controller = makeController()
        let assets = makeAssets()
        controller.begin(
            assets: assets,
            configuration: configuration,
            now: startDate
        )

        guard let presentation = controller.presentation else {
            Issue.record("Expected a reveal presentation")
            return
        }
        let transition = AttachmentTransitionSession(
            id: UUID(),
            assetID: assets[0].id,
            asset: assets[0],
            sourcePresentation: presentation,
            sourceSize: configuration.recentSize,
            sourceCornerRadius: configuration.recentCornerRadius
        )
        let context = makeContext(
            presentation: presentation,
            attachmentTransition: transition
        )

        #expect(!context.allowsSelection)
        #expect(!context.allowsScrolling)
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

    private func makeContext(
        presentation: FanPickerController.Presentation,
        attachmentTransition: AttachmentTransitionSession? = nil
    ) -> RecentFanOverlayContext {
        RecentFanOverlayContext(
            presentation: presentation,
            configuration: configuration,
            attachmentTransition: attachmentTransition,
            reduceMotion: false,
            committingAssetID: nil
        )
    }
}
#endif

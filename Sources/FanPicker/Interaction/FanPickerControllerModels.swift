#if canImport(UIKit)
import Foundation

extension FanPickerController {
    struct RevealSession {
        let id = UUID()
        var startDate: Date
        let assets: [RecentPhotoAsset]
        let frozenAssets: [RecentPhotoAsset]
        let revealItemCount: Int
        let revealMotionItemCount: Int
        let geometry: ResolvedFanPickerGeometry
    }

    struct DismissSession {
        let reveal: RevealSession
        let startDate: Date
        let initialRevealElapsed: TimeInterval
        let highlightedID: String?
    }

    enum PresentationPhase {
        case revealing
        case settled
        case frozen(revealElapsed: TimeInterval)
        case dismissing(startDate: Date, initialRevealElapsed: TimeInterval)
    }

    struct Presentation {
        let session: RevealSession
        let phase: PresentationPhase
        let highlightedID: String?
    }

    enum State {
        case idle
        case revealing(RevealSession, highlightedID: String?)
        case open(RevealSession, highlightedID: String?)
        case dismissing(DismissSession)
    }
}
#endif

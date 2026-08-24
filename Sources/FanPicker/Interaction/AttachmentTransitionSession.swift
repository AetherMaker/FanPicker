#if canImport(UIKit)
import Foundation

struct AttachmentTransitionSession {
    enum Phase: Equatable {
        case staged
        case prepared
        case flying
    }

    let id: UUID
    let assetID: String
    let asset: RecentPhotoAsset
    let sourcePresentation: FanPickerController.Presentation
    let sourceSize: CGFloat
    let sourceCornerRadius: CGFloat
    let phase: Phase

    func startingFlight() -> Self {
        Self(
            id: id,
            assetID: assetID,
            asset: asset,
            sourcePresentation: sourcePresentation,
            sourceSize: sourceSize,
            sourceCornerRadius: sourceCornerRadius,
            phase: .flying
        )
    }

    func preparingFlight() -> Self {
        Self(
            id: id,
            assetID: assetID,
            asset: asset,
            sourcePresentation: sourcePresentation,
            sourceSize: sourceSize,
            sourceCornerRadius: sourceCornerRadius,
            phase: .prepared
        )
    }

    private init(
        id: UUID,
        assetID: String,
        asset: RecentPhotoAsset,
        sourcePresentation: FanPickerController.Presentation,
        sourceSize: CGFloat,
        sourceCornerRadius: CGFloat,
        phase: Phase
    ) {
        self.id = id
        self.assetID = assetID
        self.asset = asset
        self.sourcePresentation = sourcePresentation
        self.sourceSize = sourceSize
        self.sourceCornerRadius = sourceCornerRadius
        self.phase = phase
    }

    init(
        id: UUID,
        assetID: String,
        asset: RecentPhotoAsset,
        sourcePresentation: FanPickerController.Presentation,
        sourceSize: CGFloat,
        sourceCornerRadius: CGFloat
    ) {
        self.id = id
        self.assetID = assetID
        self.asset = asset
        self.sourcePresentation = sourcePresentation
        self.sourceSize = sourceSize
        self.sourceCornerRadius = sourceCornerRadius
        phase = .staged
    }
}
#endif

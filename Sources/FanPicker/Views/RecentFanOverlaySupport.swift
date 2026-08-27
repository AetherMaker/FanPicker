#if canImport(UIKit)
import SwiftUI

struct RecentFanOverlayContext {
    let presentation: FanPickerController.Presentation
    let configuration: FanPickerConfiguration
    let attachmentTransition: AttachmentTransitionSession?
    let reduceMotion: Bool
    let committingAssetID: String?

    var isSettled: Bool {
        switch presentation.phase {
        case .settled, .frozen:
            true
        case .revealing, .dismissing:
            false
        }
    }

    var allowsInteraction: Bool {
        guard attachmentTransition == nil else { return false }
        if case .settled = presentation.phase {
            return true
        }
        return false
    }

    var resolvedHoverScale: CGFloat {
        reduceMotion
            ? min(configuration.hoverScale, 1.04)
            : configuration.hoverScale
    }

    func hoverScale(for asset: RecentPhotoAsset) -> CGFloat {
        asset.id == presentation.highlightedID ? resolvedHoverScale : 1
    }

    func fadesForCommit(_ asset: RecentPhotoAsset) -> Bool {
        committingAssetID != nil && committingAssetID != asset.id
    }

    func isPreparedAttachment(_ asset: RecentPhotoAsset) -> Bool {
        attachmentTransition?.assetID == asset.id
            && attachmentTransition?.phase == .prepared
    }

    func isFlyingAttachment(_ asset: RecentPhotoAsset) -> Bool {
        attachmentTransition?.assetID == asset.id
            && attachmentTransition?.phase == .flying
    }
}

struct RecentFanThumbnailImage: View {
    let asset: RecentPhotoAsset
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(uiImage: asset.image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .opacity(asset.isDisplayReady ? 1 : 0.54)
    }
}

extension View {
    @ViewBuilder
    func recentFanMatchedGeometry(
        asset: RecentPhotoAsset,
        transition: AttachmentTransitionSession?,
        namespace: Namespace.ID
    ) -> some View {
        if let transition, transition.assetID == asset.id {
            matchedGeometryEffect(
                id: transition.id,
                in: namespace,
                properties: .position,
                isSource: true
            )
        } else {
            self
        }
    }
}
#endif

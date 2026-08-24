#if canImport(UIKit)
import SwiftUI

public extension View {
    /// Connects an attachment view to its selected recent-photo thumbnail.
    ///
    /// Apply this modifier to the real destination view after adding the
    /// selection to your model. FanPicker supplies the matched-geometry
    /// effect and runs the flight.
    ///
    /// - Parameters:
    ///   - id: The selection ID received by `onSelect`.
    ///   - context: The context passed to the composer builder.
    @ViewBuilder
    func fanPickerAttachmentTransition(
        id: UUID,
        context: RecentPhotoPickerContext
    ) -> some View {
        let transition = context.attachmentTransition
        let isTransitioning = transition?.id == id
        let isPrepared = isTransitioning && transition?.phase == .prepared
        let isFlying = isTransitioning && transition?.phase == .flying
        let configuration = context.configuration
        let preparedScale = transition.map {
            $0.sourceSize / configuration.attachmentSize
        } ?? 1
        let visualScale = isPrepared ? preparedScale : 1
        let unscaledCornerRadius = isPrepared
            ? (transition?.sourceCornerRadius ?? configuration.recentCornerRadius)
                / max(preparedScale, 0.001)
            : configuration.attachmentCornerRadius

        self
            .frame(
                width: configuration.attachmentSize,
                height: configuration.attachmentSize
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: unscaledCornerRadius,
                    style: .continuous
                )
            )
            .scaleEffect(visualScale)
            .matchedGeometryEffect(
                id: id,
                in: context.attachmentNamespace,
                properties: .position,
                isSource: !isTransitioning || isFlying
            )
            .opacity(isTransitioning && !isPrepared && !isFlying ? 0 : 1)
            .onAppear {
                guard isTransitioning else { return }
                context.attachmentDestinationReady(id: id)
            }
            .onChange(of: isTransitioning) { _, next in
                guard next else { return }
                context.attachmentDestinationReady(id: id)
            }
    }
}
#endif

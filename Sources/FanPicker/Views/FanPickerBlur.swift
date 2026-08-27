#if canImport(UIKit)
import SwiftUI

public extension View {
    /// Blurs composer content while the recent-photo picker is active.
    ///
    /// Place ``RecentPhotoPickerContext/trigger`` inside the composer where
    /// the button belongs. FanPicker renders the live control above this layer.
    ///
    /// - Parameters:
    ///   - context: The context provided by ``RecentPhotoQuickPicker``.
    ///   - clipShape: The shape that contains the composer.
    ///   - background: The background rendered below the composer.
    func fanPickerBlur<Background: View, ClipShape: Shape>(
        context: RecentPhotoPickerContext,
        clippedTo clipShape: ClipShape,
        @ViewBuilder background: () -> Background
    ) -> some View {
        FanPickerBlurLayer(
            content: self,
            background: background(),
            clipShape: clipShape,
            isActive: context.isActive && context.attachmentTransition == nil,
            isTransitioningAttachment: context.isAttachingPhoto,
            configuration: context.configuration
        )
    }
}

private struct FanPickerBlurLayer<
    Content: View,
    Background: View,
    ClipShape: Shape
>: View {
    let content: Content
    let background: Background
    let clipShape: ClipShape
    let isActive: Bool
    let isTransitioningAttachment: Bool
    let configuration: FanPickerConfiguration

    var body: some View {
        content
            .opacity(isActive ? configuration.composerBlurOpacity : 1)
            // Keep the background clipped while the content clip opens.
            .background(background.clipShape(clipShape))
            .clipShape(
                ComposerContentClip(
                    base: clipShape,
                    isOpen: isTransitioningAttachment
                )
            )
            .compositingGroup()
            .blur(radius: isActive ? configuration.composerBlurRadius : 0)
            .overlay {
                if isActive {
                    Color.clear
                        .contentShape(clipShape)
                        .onTapGesture {}
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(isActive)
            // Remove the blur before the attachment starts flying.
            .animation(
                isTransitioningAttachment ? nil : .smooth(duration: 0.09),
                value: isActive
            )
    }
}

/// Opens the composer's top edge for the attachment flight.
private struct ComposerContentClip<Base: Shape>: Shape {
    let base: Base
    let isOpen: Bool

    func path(in rect: CGRect) -> Path {
        guard isOpen else { return base.path(in: rect) }
        return Rectangle().path(
            in: CGRect(
                x: rect.minX,
                y: rect.minY - Self.flightHeadroom,
                width: rect.width,
                height: rect.height + Self.flightHeadroom
            )
        )
    }

    private static var flightHeadroom: CGFloat { 600 }
}
#endif

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
            isActive: context.isActive,
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
    let configuration: FanPickerConfiguration

    var body: some View {
        content
            .opacity(isActive ? configuration.composerBlurOpacity : 1)
            .background(background)
            .clipShape(clipShape)
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
            .animation(.smooth(duration: 0.09), value: isActive)
    }
}
#endif

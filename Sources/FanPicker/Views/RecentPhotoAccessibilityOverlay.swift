#if canImport(UIKit)
import SwiftUI

struct RecentPhotoAccessibilityOverlay: View {
    let presentation: FanPickerController.Presentation
    let configuration: FanPickerConfiguration
    let globalOrigin: CGPoint
    let onSelect: (RecentPhotoAsset) -> Void

    var body: some View {
        let session = presentation.session
        let destinations = session.geometry.recentRects(
            count: session.revealItemCount,
            configuration: configuration
        )

        ZStack {
            ForEach(
                Array(session.assets.prefix(session.revealItemCount).enumerated()),
                id: \.element.id
            ) { index, asset in
                if destinations.indices.contains(index) {
                    Button {
                        onSelect(asset)
                    } label: {
                        Color.clear
                            .frame(
                                width: configuration.recentSize,
                                height: configuration.recentSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: destinations[index].midX - globalOrigin.x,
                        y: destinations[index].midY - globalOrigin.y
                    )
                    .accessibilityLabel("Recent photo \(index + 1)")
                    .accessibilityHint("Adds this photo as an attachment")
                }
            }
        }
    }
}
#endif

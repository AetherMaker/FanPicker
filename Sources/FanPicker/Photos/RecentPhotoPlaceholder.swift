#if canImport(UIKit)
import UIKit

enum RecentPhotoPlaceholder {
    static func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            let symbolSize = min(size.width, size.height) * 0.28
            let configuration = UIImage.SymbolConfiguration(
                pointSize: symbolSize,
                weight: .regular
            )
            guard let symbol = UIImage(
                systemName: "photo",
                withConfiguration: configuration
            )?.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) else {
                return
            }
            symbol.draw(
                at: CGPoint(
                    x: (size.width - symbol.size.width) / 2,
                    y: (size.height - symbol.size.height) / 2
                )
            )
        }
    }
}
#endif

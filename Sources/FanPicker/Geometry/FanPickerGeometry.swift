#if canImport(UIKit)
import SwiftUI

struct FanPickerTriggerAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        value = nextValue() ?? value
    }
}

extension View {
    func fanPickerTriggerAnchor() -> some View {
        anchorPreference(
            key: FanPickerTriggerAnchorKey.self,
            value: .bounds
        ) { anchor in
            anchor
        }
    }
}

struct ResolvedFanPickerGeometry: Equatable {
    var composerRect: CGRect = .zero
    var triggerRect: CGRect = .zero

    var isValid: Bool {
        !composerRect.isEmpty && !triggerRect.isEmpty
    }

    func differs(
        from other: ResolvedFanPickerGeometry,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        rectDiffers(composerRect, from: other.composerRect, tolerance: tolerance)
            || rectDiffers(triggerRect, from: other.triggerRect, tolerance: tolerance)
    }

    func recentRects(
        count: Int,
        configuration: FanPickerConfiguration
    ) -> [CGRect] {
        guard count > 0, isValid else { return [] }

        let rowWidth = CGFloat(count) * configuration.recentSize
            + CGFloat(max(count - 1, 0)) * configuration.recentSpacing
        let leading = composerRect.midX - rowWidth / 2
        let centerY = triggerRect.minY
            - configuration.rowToControlGap
            - configuration.recentSize / 2

        return (0..<count).map { index in
            CGRect(
                x: leading + CGFloat(index)
                    * (configuration.recentSize + configuration.recentSpacing),
                y: centerY - configuration.recentSize / 2,
                width: configuration.recentSize,
                height: configuration.recentSize
            )
        }
    }

    private func rectDiffers(
        _ lhs: CGRect,
        from rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) > tolerance
            || abs(lhs.minY - rhs.minY) > tolerance
            || abs(lhs.width - rhs.width) > tolerance
            || abs(lhs.height - rhs.height) > tolerance
    }
}
#endif

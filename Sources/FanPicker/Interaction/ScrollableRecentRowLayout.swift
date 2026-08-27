#if canImport(UIKit)
import CoreGraphics
import Foundation

struct ScrollableRecentRowLayout: Equatable {
    struct StackCapture: Equatable {
        let center: CGPoint
        let progress: CGFloat
    }

    struct StackPlacement: Equatable {
        let scale: CGFloat
        let opacity: CGFloat
    }

    let viewport: CGRect
    let rowCenterY: CGFloat
    let leadingCenterX: CGFloat
    let itemSize: CGFloat
    let itemSpacing: CGFloat
    let assetCount: Int
    let stackDepth: Int

    var itemPitch: CGFloat {
        itemSize + itemSpacing
    }

    var naturalMaximumOffset: CGFloat {
        guard assetCount > 0 else { return 0 }
        let lastCenter = leadingCenterX + CGFloat(assetCount - 1) * itemPitch
        let trailingCenter = viewport.maxX - itemSize / 2
        return max(lastCenter - trailingCenter, 0)
    }

    var terminalAlignmentInset: CGFloat {
        guard naturalMaximumOffset > 0, itemPitch > 0 else { return 0 }
        let remainder = naturalMaximumOffset.truncatingRemainder(
            dividingBy: itemPitch
        )
        guard remainder > 0.001 else { return 0 }
        return itemPitch - remainder
    }

    var maximumOffset: CGFloat {
        naturalMaximumOffset + terminalAlignmentInset
    }

    var stackCaptureDistance: CGFloat {
        min(itemSize * 0.55, itemPitch * 0.6)
    }

    func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(max(offset, 0), maximumOffset)
    }

    func rawCenter(index: Int, offset: CGFloat) -> CGPoint {
        CGPoint(
            x: leadingCenterX + CGFloat(index) * itemPitch - clampedOffset(offset),
            y: rowCenterY
        )
    }

    func stackedThrough(offset: CGFloat) -> Int? {
        guard offset > 0, assetCount > 0, itemPitch > 0 else { return nil }
        return min(Int(floor(offset / itemPitch)), assetCount - 1)
    }

    func stackedIndices(offset: CGFloat) -> [Int] {
        guard let top = stackedThrough(offset: offset) else { return [] }
        let lower = max(top - max(stackDepth, 1) + 1, 0)
        return Array(lower...top)
    }

    func visibleMainIndices(offset: CGFloat) -> [Int] {
        guard assetCount > 0 else { return [] }
        let stackTop = stackedThrough(offset: offset) ?? -1
        return (max(stackTop + 1, 0)..<assetCount).filter { index in
            let center = rawCenter(index: index, offset: offset)
            return center.x >= leadingCenterX - itemSize / 2
                && center.x <= viewport.maxX + itemSize
        }
    }

    func renderedIndices(offset: CGFloat) -> [Int] {
        Array(Set(stackedIndices(offset: offset) + visibleMainIndices(offset: offset)))
            .sorted()
    }

    func center(index: Int, offset: CGFloat) -> CGPoint {
        stackCapture(rawCenter: rawCenter(index: index, offset: offset)).center
    }

    func stackCapture(rawCenter: CGPoint) -> StackCapture {
        let distance = rawCenter.x - leadingCenterX
        guard stackCaptureDistance > 0 else {
            return capture(
                centerX: max(rawCenter.x, leadingCenterX),
                rawCenterY: rawCenter.y,
                progress: distance <= 0 ? 1 : 0
            )
        }
        guard distance > 0 else {
            return capture(
                centerX: leadingCenterX,
                rawCenterY: rawCenter.y,
                progress: 1
            )
        }
        guard distance < stackCaptureDistance else {
            return capture(
                centerX: rawCenter.x,
                rawCenterY: rawCenter.y,
                progress: 0
            )
        }

        let remaining = distance / stackCaptureDistance
        let easedDistance = stackCaptureDistance
            * (-remaining * remaining * remaining + 2 * remaining * remaining)
        return capture(
            centerX: leadingCenterX + easedDistance,
            rawCenterY: rawCenter.y,
            progress: 1 - remaining
        )
    }

    func stackPlacement(index: Int, offset: CGFloat) -> StackPlacement? {
        guard let top = stackedThrough(offset: offset), index <= top else {
            return nil
        }
        let incoming = incomingProgress(top: top, offset: offset)
        let level = CGFloat(top - index) + incoming
        let retained = CGFloat(max(stackDepth, 1))
        let fadeProgress = min(max(level - (retained - 1), 0), 1)
        return StackPlacement(
            scale: 1 - stackScaleStep * min(level, retained),
            opacity: 1 - fadeProgress * fadeProgress * (3 - 2 * fadeProgress)
        )
    }

    func stackShadowStrength(index: Int, offset: CGFloat) -> CGFloat {
        guard let top = stackedThrough(offset: offset) else { return 0 }
        if let placement = stackPlacement(index: index, offset: offset) {
            let stackProgress = min(
                CGFloat(top) + incomingProgress(top: top, offset: offset),
                1
            )
            return stackProgress * placement.opacity
        }
        guard index == top + 1 else { return 0 }
        return stackCapture(
            rawCenter: rawCenter(index: index, offset: offset)
        ).progress
    }

    func zIndex(index: Int) -> Double {
        Double(index)
    }

    func selectableRect(index: Int, offset: CGFloat) -> CGRect? {
        if let top = stackedThrough(offset: offset), index <= top {
            return nil
        }
        let center = center(index: index, offset: offset)
        return CGRect(
            x: center.x - itemSize / 2,
            y: center.y - itemSize / 2,
            width: itemSize,
            height: itemSize
        )
    }

    var trailingVisibleIndex: Int {
        guard assetCount > 0 else { return 0 }
        return min(
            max(
                Int(ceil((viewport.maxX - leadingCenterX) / itemPitch)),
                0
            ),
            assetCount - 1
        )
    }

    func trailingVisibleIndex(offset: CGFloat) -> Int {
        guard assetCount > 0 else { return 0 }
        return min(
            max(
                Int(ceil((viewport.maxX - leadingCenterX + offset) / itemPitch)),
                0
            ),
            assetCount - 1
        )
    }

    private var stackScaleStep: CGFloat { 0.05 }

    private func capture(
        centerX: CGFloat,
        rawCenterY: CGFloat,
        progress: CGFloat
    ) -> StackCapture {
        StackCapture(
            center: CGPoint(x: centerX, y: rawCenterY),
            progress: progress
        )
    }

    private func incomingProgress(top: Int, offset: CGFloat) -> CGFloat {
        guard top + 1 < assetCount else { return 0 }
        return stackCapture(
            rawCenter: rawCenter(index: top + 1, offset: offset)
        ).progress
    }
}
#endif

#if canImport(UIKit)
import SwiftUI

/// FanPicker's `+`/`X` button and its tap, hold, and drag gestures.
public struct RecentPhotoTrigger: View {
    let isActive: Bool
    let configuration: FanPickerConfiguration
    let onRecognized: () -> Void
    let onDrag: (CGPoint) -> Void
    let onRelease: () -> Void
    let onTap: () -> Void
    let onPressChanged: (Bool) -> Void
    let onAccessibilityReveal: () -> Void

    @State private var didRecognizeHold = false
    @GestureState private var isPressed = false

    public var body: some View {
        Button(action: handleTap) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(isActive ? 45 : 0))
                .animation(.smooth(duration: 0.16), value: isActive)
        }
        .buttonStyle(.plain)
        .fanPickerTriggerAnchor()
        .simultaneousGesture(triggerGesture)
        .simultaneousGesture(pressTrackingGesture)
        .onChange(of: isPressed) { _, isPressed in
            onPressChanged(isPressed)
        }
        .accessibilityLabel(isActive ? "Close recent photos" : "Add attachment")
        .accessibilityHint(
            isActive
                ? "Tap to close recent photos."
                : "Tap for attachment options. Touch and hold for recent photos."
        )
        .accessibilityAction(named: Text("Choose a recent photo")) {
            onAccessibilityReveal()
        }
        .accessibilityIdentifier("fanpicker.trigger")
    }

    private var holdThenDrag: SequenceGesture<LongPressGesture, DragGesture> {
        LongPressGesture(
            minimumDuration: configuration.holdDuration,
            maximumDistance: configuration.maximumHoldMovement
        )
        .sequenced(
            before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .global
            )
        )
    }

    private var triggerGesture: some Gesture {
        holdThenDrag
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }

                if !didRecognizeHold {
                    didRecognizeHold = true
                    onRecognized()
                }
                if let drag {
                    onDrag(drag.location)
                }
            }
            .onEnded { value in
                if case let .second(true, drag) = value {
                    if let drag {
                        onDrag(drag.location)
                    }
                    onRelease()
                }
                Task { @MainActor in
                    await Task.yield()
                    didRecognizeHold = false
                }
            }
    }

    private var pressTrackingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, isPressed, _ in
                isPressed = true
            }
    }

    private func handleTap() {
        guard !didRecognizeHold else { return }
        onTap()
    }
}
#endif

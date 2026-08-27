# FanPicker

FanPicker is a SwiftUI control for quickly attaching recent photos. Hold the add button to reveal a fan of recent images, then drag or tap to select one.

## Requirements

- iOS 17 or later
- Swift 6.3

## Installation

Add this package in Xcode, or add it to `Package.swift`:

```swift
.package(
    url: "https://github.com/AetherMaker/FanPicker.git",
    from: "0.2.1"
)
```

Add `FanPicker` to your app target.

## Photo access

Add a photo-library usage description to your app's `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose recent photos to attach.</string>
```

FanPicker asks for access only after the user holds the add button. Limited photo-library access is supported.

## Usage

```swift
import FanPicker
import SwiftUI

struct ChatView: View {
    @State private var attachments: [RecentPhotoSelection] = []
    @State private var draft = ""
    @State private var isScrollLocked = false

    var body: some View {
        ScrollView {
            MessageList()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(isScrollLocked)
        .safeAreaInset(edge: .bottom) {
            RecentPhotoQuickPicker(
                onTapTrigger: openAttachmentMenu,
                onSelect: { attachments.append($0) },
                onScrollLockChanged: { isScrollLocked = $0 }
            ) { picker in
                let shape = RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )

                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(attachments) { attachment in
                                Image(uiImage: attachment.asset.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(.rect(cornerRadius: 14))
                                    .fanPickerAttachmentTransition(
                                        id: attachment.id,
                                        context: picker
                                    )
                            }
                        }
                    }

                    HStack {
                        picker.trigger
                        TextField("Message", text: $draft)
                    }
                }
                .padding(10)
                .fanPickerBlur(context: picker, clippedTo: shape) {
                    shape.fill(.regularMaterial)
                }
            }
        }
    }

    private func openAttachmentMenu() {}
}
```

`picker.trigger` marks where FanPicker renders its `+`/`X` button. Place it where the attachment button belongs. FanPicker keeps the live control sharp and interactive above the composer blur. Tapping it calls `onTapTrigger`; holding it opens recent photos. Use `onTapTrigger` to open your app's attachment menu or any other action.

Use `onScrollLockChanged` with the host scroll view. Normal scrolling and interactive keyboard dismissal remain enabled while FanPicker is closed.

`fanPickerBlur` blurs the composer as one layer while the picker is open. FanPicker renders the live trigger above that layer automatically.

Your app creates and positions the destination attachment view. Apply `fanPickerAttachmentTransition(id:context:)` to that view, as shown above. FanPicker connects it to the selected thumbnail and runs the hero animation. You do not need to add `matchedGeometryEffect` yourself.

Two rules keep that hero animation intact:

- In `onSelect`, animate your composer's growth if you want, but never the insertion of the attachment cell. A view that enters with a transition loses its matched geometry and jumps instead of flying.
- The photo flies in from the row above the composer. Any clipping of your own has to open while `picker.isAttachingPhoto` is `true`, or it cuts the photo's top edge mid-flight. `fanPickerBlur` handles this for the shape you pass it.

For uploads, use `loadImageData()` or `exportResource(to:)`. `asset.image` is the display preview.

## Demo

Open [Examples/FanPickerDemo/FanPickerDemo.xcodeproj](Examples/FanPickerDemo/FanPickerDemo.xcodeproj), select your own signing team, and run the app.

## Version 0.2.1

The live `+`/`X` trigger stays sharp and interactive while the composer is blurred.

## Version 0.2

Keep the destination attachment outside clipped containers during its flight. A package-owned flight overlay is planned for a later release.

## License

FanPicker is available under the MIT License. See [LICENSE](LICENSE).

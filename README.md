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
    from: "0.2.0"
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
                        Color.clear.frame(width: 40, height: 40)
                        TextField("Message", text: $draft)
                    }
                }
                .padding(10)
                .fanPickerBlur(context: picker, clippedTo: shape) {
                    shape.fill(.regularMaterial)
                }
                .overlay(alignment: .bottomLeading) {
                    picker.trigger.padding(10)
                }
            }
        }
    }

    private func openAttachmentMenu() {}
}
```

`picker.trigger` is FanPicker's `+`/`X` button. Place it where the attachment button belongs. Tapping it calls `onTapTrigger`; holding it opens recent photos. Use `onTapTrigger` to open your app's attachment menu or any other action.

Use `onScrollLockChanged` with the host scroll view. Normal scrolling and interactive keyboard dismissal remain enabled while FanPicker is closed.

`fanPickerBlur` blurs the composer as one layer while the picker is open. Keep `picker.trigger` above that layer so it stays sharp and interactive.

Your app creates and positions the destination attachment view. Apply `fanPickerAttachmentTransition(id:context:)` to that view, as shown above. FanPicker connects it to the selected thumbnail and runs the hero animation. You do not need to add `matchedGeometryEffect` yourself.

For uploads, use `loadImageData()` or `exportResource(to:)`. `asset.image` is the display preview.

## Demo

Open [Examples/FanPickerDemo/FanPickerDemo.xcodeproj](Examples/FanPickerDemo/FanPickerDemo.xcodeproj), select your own signing team, and run the app.

## Version 0.2

Keep the destination attachment outside clipped containers during its flight. A package-owned flight overlay is planned for a later release.

## License

FanPicker is available under the MIT License. See [LICENSE](LICENSE).

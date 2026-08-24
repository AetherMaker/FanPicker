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
    from: "0.1.0"
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

struct Composer: View {
    @State private var attachments: [RecentPhotoSelection] = []
    @State private var draft = ""

    var body: some View {
        RecentPhotoQuickPicker(
            onTapTrigger: openAttachmentMenu,
            onSelect: { attachments.append($0) }
        ) { picker in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    Image(uiImage: attachment.asset.image)
                        .resizable()
                        .scaledToFill()
                        .fanPickerAttachmentTransition(
                            id: attachment.id,
                            context: picker
                        )
                }

                HStack {
                    picker.trigger
                    TextField("Message", text: $draft)
                }
            }
        }
    }

    private func openAttachmentMenu() {}
}
```

`picker.trigger` is FanPicker's `+`/`X` button. Place it where the attachment button belongs. Tapping it calls `onTapTrigger`; holding it opens recent photos. Use `onTapTrigger` to open your app's attachment menu or any other action.

Your app creates and positions the destination attachment view. Apply `fanPickerAttachmentTransition(id:context:)` to that view, as shown above. FanPicker connects it to the selected thumbnail and runs the hero animation. You do not need to add `matchedGeometryEffect` yourself.

For uploads, use `loadImageData()` or `exportResource(to:)`. `asset.image` is the display preview.

## Demo

Open [Examples/FanPickerDemo/FanPickerDemo.xcodeproj](Examples/FanPickerDemo/FanPickerDemo.xcodeproj), select your own signing team, and run the app.

## Version 0.1

Keep the destination attachment outside clipped containers during its flight. A package-owned flight overlay is planned for a later release.

## License

FanPicker is available under the MIT License. See [LICENSE](LICENSE).

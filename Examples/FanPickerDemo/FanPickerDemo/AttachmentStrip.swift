import FanPicker
import SwiftUI

struct AttachmentStrip: View {
    let attachments: [RecentPhotoSelection]
    let picker: RecentPhotoPickerContext
    let onRemove: (UUID) -> Void

    private let configuration = FanPickerConfiguration.reference

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: configuration.attachmentSpacing) {
                ForEach(attachments) { attachment in
                    Image(uiImage: attachment.asset.image)
                        .resizable()
                        .scaledToFill()
                        .fanPickerAttachmentTransition(
                            id: attachment.id,
                            context: picker
                        )
                        .overlay(alignment: .topTrailing) {
                            if !picker.isTransitioningAttachment(id: attachment.id) {
                                Button {
                                    onRemove(attachment.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(
                                            width: configuration.closeBadgeSize,
                                            height: configuration.closeBadgeSize
                                        )
                                        .background(.black.opacity(0.75), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .accessibilityLabel("Remove attachment")
                            }
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(true)
        .frame(height: configuration.attachmentSize)
    }
}

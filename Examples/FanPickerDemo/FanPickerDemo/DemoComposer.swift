import FanPicker
import SwiftUI

struct DemoComposer: View {
    @Binding var draft: String
    @Binding var attachments: [RecentPhotoSelection]
    let picker: RecentPhotoPickerContext
    let isInputFocused: FocusState<Bool>.Binding

    var body: some View {
        composerContent
            .fanPickerBlur(
                context: picker,
                clippedTo: composerShape
            ) {
                composerShape.fill(.regularMaterial)
            }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                AttachmentStrip(
                    attachments: attachments,
                    picker: picker,
                    onRemove: remove
                )
            }

            HStack(spacing: 8) {
                picker.trigger

                TextField("Message", text: $draft)
                    .focused(isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                        .background(.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
    }

    private var composerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private func remove(_ id: UUID) {
        withAnimation(.smooth(duration: 0.2)) {
            attachments.removeAll { $0.id == id }
        }
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isInputFocused.wrappedValue = true
            return
        }
        draft = ""
    }
}

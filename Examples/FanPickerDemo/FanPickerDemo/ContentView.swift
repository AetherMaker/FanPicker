import FanPicker
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var attachments: [RecentPhotoSelection] = []
    @State private var draft = ""
    @State private var showingPhotoAccessAlert = false
    @State private var showingTapHelp = false
    @State private var isScrollLocked = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .onTapGesture {
                    isInputFocused = false
                }

            ScrollView {
                VStack(spacing: 8) {
                    Text("FanPicker")
                        .font(.title.bold())

                    Text("Hold + to choose a recent photo")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 96)
            }
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(isScrollLocked)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RecentPhotoQuickPicker(
                onTapTrigger: {
                    showingTapHelp = true
                },
                onPhotoAccessUnavailable: { _ in
                    showingPhotoAccessAlert = true
                },
                onSelect: { selection in
                    attachments.append(selection)
                },
                onScrollLockChanged: { isLocked in
                    isScrollLocked = isLocked
                }
            ) { picker in
                DemoComposer(
                    draft: $draft,
                    attachments: $attachments,
                    picker: picker,
                    isInputFocused: $isInputFocused
                )
            }
            .padding(12)
        }
        .alert("Add button tapped", isPresented: $showingTapHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use onTapTrigger to open your normal attachment menu.")
        }
        .alert("Photo access needed", isPresented: $showingPhotoAccessAlert) {
            Button("Not now", role: .cancel) {}
            Button("Open Settings", action: openSettings)
        } message: {
            Text("Allow photo access in Settings to show recent photos.")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ContentView()
}

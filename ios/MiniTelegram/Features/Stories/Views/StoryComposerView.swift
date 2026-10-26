import SwiftUI

/// Preview of the picked photo with an optional caption, then "Share" posts it for 24 hours.
struct StoryComposerView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoriesStore.shared
    @State private var caption = ""
    @FocusState private var captionFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.vertical, 56)
                .onTapGesture { captionFocused = false }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Text("New Story")
                        .font(AppTypography.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 38, height: 38)
                }
                .padding(.horizontal, AppSpacing.md)

                Spacer()

                HStack(spacing: 10) {
                    TextField("", text: $caption, prompt: Text("Add a caption…").foregroundColor(.white.opacity(0.6)), axis: .vertical)
                        .lineLimit(1...4)
                        .foregroundColor(.white)
                        .tint(.white)
                        .focused($captionFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .onChange(of: caption) { _, text in
                            if text.count > 200 { caption = String(text.prefix(200)) }
                        }

                    Button {
                        Task {
                            if await store.post(image: image, caption: caption) { dismiss() }
                        }
                    } label: {
                        ZStack {
                            Circle().fill(AppColors.accent)
                            if store.isPosting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 46, height: 46)
                    }
                    .disabled(store.isPosting)
                    .accessibilityLabel("Share story")
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Story", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

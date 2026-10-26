import SwiftUI
import PhotosUI

/// The row of story circles at the top of the chat list, like Telegram.
public struct StoriesBarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = StoriesStore.shared

    @State private var showingPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var composing: ComposedStoryImage?
    @State private var viewing: StoryViewerStart?

    public init() {}

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                myCircle

                ForEach(store.friendStories) { entry in
                    Button {
                        viewing = StoryViewerStart(id: entry.user_id)
                    } label: {
                        StoryCircle(
                            title: ContactNicknames.displayName(userId: entry.user_id, fallback: entry.display_name),
                            avatar: StoryRingAvatar(
                                name: entry.display_name,
                                avatarUrl: entry.avatar_url,
                                size: 58,
                                ring: entry.has_unseen ? .unseen : .seen
                            ),
                            emphasized: entry.has_unseen
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
        }
        .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    composing = ComposedStoryImage(image: image)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(item: $composing) { item in
            StoryComposerView(image: item.image)
        }
        .fullScreenCover(item: $viewing) { start in
            StoryViewerView(groups: store.feed, startUserId: start.id)
        }
        .alert("Story", isPresented: Binding(
            // The composer shows its own errors while it is open
            get: { store.errorMessage != nil && composing == nil && viewing == nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// One tap on my photo plays my story; the "+" badge is the only way to add another.
    private var myCircle: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    if let me = store.myStories {
                        viewing = StoryViewerStart(id: me.user_id)
                    } else {
                        showingPicker = true // nothing to watch yet: start my first story
                    }
                } label: {
                    StoryRingAvatar(
                        name: appState.currentUser?.displayName ?? "Me",
                        avatarUrl: appState.currentUser?.avatarUrl,
                        size: 58,
                        ring: store.myStories != nil ? .unseen : .none
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.myStories != nil ? "View my story" : "Add a story")

                Button {
                    showingPicker = true
                } label: {
                    Group {
                        if store.isPosting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(AppColors.accent))
                    .overlay(Circle().stroke(AppColors.background, lineWidth: 2.5))
                    .contentShape(Circle().inset(by: -8)) // bigger tap target than it looks
                }
                .buttonStyle(.plain)
                .disabled(store.isPosting)
                .accessibilityLabel("Add to my story")
            }

            Text("My Story")
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .frame(width: 66)
        }
    }
}

private struct StoryCircle<Avatar: View>: View {
    let title: String
    let avatar: Avatar
    let emphasized: Bool

    var body: some View {
        VStack(spacing: 4) {
            avatar
            Text(title)
                .font(.system(size: 11, weight: emphasized ? .semibold : .regular))
                .foregroundColor(emphasized ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)
                .frame(width: 66)
        }
    }
}

struct ComposedStoryImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct StoryViewerStart: Identifiable {
    /// The user whose stories open first
    let id: String
}

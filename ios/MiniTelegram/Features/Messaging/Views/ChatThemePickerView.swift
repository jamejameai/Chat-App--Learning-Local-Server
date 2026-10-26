import SwiftUI

/// Grid of the 30 chat themes, each shown as a tiny live preview of the chat.
public struct ChatThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let selected: ChatTheme
    let onSelect: (ChatTheme) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    public init(selected: ChatTheme, onSelect: @escaping (ChatTheme) -> Void) {
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ChatTheme.all) { theme in
                        Button {
                            onSelect(theme)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                ThemePreviewCard(theme: theme, isSelected: theme.id == selected.id)
                                Text(theme.name)
                                    .font(AppTypography.caption.weight(theme.id == selected.id ? .semibold : .regular))
                                    .foregroundColor(AppColors.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.background)
            .navigationTitle("Chat Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ThemePreviewCard: View {
    let theme: ChatTheme
    let isSelected: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(theme.incoming)
                    .frame(width: 52, height: 14)
                HStack {
                    Spacer()
                    Capsule()
                        .fill(LinearGradient(colors: theme.outgoing, startPoint: .leading, endPoint: .trailing))
                        .frame(width: 60, height: 14)
                }
                Capsule()
                    .fill(theme.incoming)
                    .frame(width: 38, height: 14)
            }
            .padding(10)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, AppColors.accent)
                    .padding(6)
            }
        }
    }
}

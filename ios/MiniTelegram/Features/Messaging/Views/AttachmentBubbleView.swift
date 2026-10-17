import SwiftUI
import QuickLook

public struct AttachmentBubbleView: View {
    public let attachment: MessageAttachment
    public let isOutgoing: Bool

    @State private var localURL: URL? = nil
    @State private var isLoading: Bool = false
    @State private var previewItem: PreviewItem? = nil

    public init(attachment: MessageAttachment, isOutgoing: Bool) {
        self.attachment = attachment
        self.isOutgoing = isOutgoing
    }

    private var isImage: Bool {
        attachment.mimeType.lowercased().hasPrefix("image/")
    }

    public var body: some View {
        Group {
            if isImage {
                imageAttachmentView
            } else {
                documentAttachmentView
            }
        }
        .onAppear {
            checkLocalFile()
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
    }

    // MARK: - Image Attachment View
    @ViewBuilder
    private var imageAttachmentView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let url = localURL, let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 240, maxHeight: 200)
                        .clipped()
                        .cornerRadius(AppCornerRadius.md)
                        .onTapGesture {
                            self.previewItem = PreviewItem(url: url)
                        }
                } else {
                    Rectangle()
                        .fill(isOutgoing ? Color.white.opacity(0.15) : AppColors.background)
                        .frame(width: 200, height: 150)
                        .cornerRadius(AppCornerRadius.md)
                        .overlay(
                            VStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: isOutgoing ? Color.white : AppColors.accent))
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(isOutgoing ? Color.white : AppColors.accent)

                                    Text(formattedByteSize(attachment.byteSize))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isOutgoing ? Color.white.opacity(0.8) : AppColors.textSecondary)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            downloadAndDecrypt()
                        }
                }
            }
        }
    }

    // MARK: - Document Attachment View
    @ViewBuilder
    private var documentAttachmentView: some View {
        HStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .fill(isOutgoing ? Color.white.opacity(0.2) : AppColors.accent.opacity(0.15))
                    .frame(width: 42, height: 42)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isOutgoing ? Color.white : AppColors.accent))
                        .scaleEffect(0.8)
                } else if localURL != nil {
                    Image(systemName: documentIcon(for: attachment.fileName))
                        .font(.system(size: 18))
                        .foregroundColor(isOutgoing ? Color.white : AppColors.accent)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isOutgoing ? Color.white : AppColors.accent)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(AppTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isOutgoing ? Color.white : AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(formattedByteSize(attachment.byteSize))
                    .font(.system(size: 10))
                    .foregroundColor(isOutgoing ? Color.white.opacity(0.7) : AppColors.textSecondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = localURL {
                self.previewItem = PreviewItem(url: url)
            } else {
                downloadAndDecrypt()
            }
        }
    }

    private func checkLocalFile() {
        if let path = attachment.localDecryptedPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                self.localURL = url
                return
            }
        }
        // Auto-download images on wifi/appear
        if isImage && !isLoading && localURL == nil {
            downloadAndDecrypt()
        }
    }

    private func downloadAndDecrypt() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                let decryptedUrl = try await AttachmentManager.shared.downloadAndDecryptAttachment(attachment: attachment)
                await MainActor.run {
                    self.localURL = decryptedUrl
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                print("[AttachmentBubbleView] Download error: \(error)")
            }
        }
    }

    private func formattedByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func documentIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "7z":
            return "archivebox.fill"
        case "mp3", "m4a", "wav":
            return "waveform"
        case "mp4", "mov":
            return "film.fill"
        case "txt", "md", "json":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }
}

// QuickLook preview helper
private struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as NSURL
        }
    }
}

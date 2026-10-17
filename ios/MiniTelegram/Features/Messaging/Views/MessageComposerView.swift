import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct MessageComposerView: View {
    @Binding public var text: String
    public let replyingTo: ChatMessage?
    public let onCancelReply: () -> Void
    public let onSend: () -> Void
    public let onSendAttachment: (URL, String, String) -> Void
    public let onSendVoiceNote: (URL, TimeInterval, [Float]) -> Void

    @StateObject private var recorder = AudioRecorderManager.shared
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingAttachmentDialog: Bool = false

    public init(
        text: Binding<String>,
        replyingTo: ChatMessage?,
        onCancelReply: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onSendAttachment: @escaping (URL, String, String) -> Void = { _, _, _ in },
        onSendVoiceNote: @escaping (URL, TimeInterval, [Float]) -> Void = { _, _, _ in }
    ) {
        self._text = text
        self.replyingTo = replyingTo
        self.onCancelReply = onCancelReply
        self.onSend = onSend
        self.onSendAttachment = onSendAttachment
        self.onSendVoiceNote = onSendVoiceNote
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.border)

            // Quoted Reply Banner
            if let reply = replyingTo {
                HStack(spacing: AppSpacing.xs) {
                    Rectangle()
                        .fill(AppColors.accent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("chat_replying_to", reply.senderName))
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(AppColors.accent)

                        Text(reply.text.isEmpty ? (reply.attachment?.fileName ?? "Attachment") : reply.text)
                            .font(AppTypography.caption)
                            .lineLimit(1)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Button(action: onCancelReply) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.surface)
            }

            // Input Row or Live Recording Row
            if recorder.isRecording {
                recordingBar
            } else {
                standardComposerBar
            }
        }
        .confirmationDialog("Attach", isPresented: $isShowingAttachmentDialog, titleVisibility: .visible) {
            Button("Files & Documents") {
                isShowingFileImporter = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleSelectedFile(url: url)
            case .failure(let error):
                print("[MessageComposerView] File picker error: \(error)")
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    let tempUrl = tempDir.appendingPathComponent(fileName)
                    try? data.write(to: tempUrl)
                    onSendAttachment(tempUrl, fileName, "image/jpeg")
                }
                await MainActor.run {
                    self.selectedPhotoItem = nil
                }
            }
        }
    }

    // MARK: - Standard Composer Bar
    private var standardComposerBar: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            // Photos Picker
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 36, height: 36)
            }

            // File Attachment Button
            Button(action: { isShowingFileImporter = true }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 36, height: 36)
            }

            // Text Field
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(L("chat_composer_placeholder"))
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 8)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 8)
                    .lineLimit(1...5)
            }
            .background(AppColors.surface)
            .cornerRadius(AppCornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.md)
                    .stroke(AppColors.border, lineWidth: 1)
            )

            // Right Action: Send Text OR Record Voice Note
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: startVoiceRecording) {
                    ZStack {
                        Circle()
                            .fill(AppColors.surface)
                            .frame(width: 36, height: 36)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 17))
                            .foregroundColor(AppColors.accent)
                    }
                }
            } else {
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 36, height: 36)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.white)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.background)
    }

    // MARK: - Voice Recording Bar
    private var recordingBar: some View {
        HStack(spacing: AppSpacing.sm) {
            // Cancel Recording
            Button(action: {
                recorder.cancelRecording()
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.statusError)
                    .frame(width: 36, height: 36)
            }

            // Blinking red dot & timer
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.statusError)
                    .frame(width: 10, height: 10)

                Text(formatRecordDuration(recorder.recordingDuration))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
            }

            // Live Waveform Mini-view
            HStack(spacing: 2) {
                let tail = recorder.liveWaveform.suffix(24)
                ForEach(0..<tail.count, id: \.self) { idx in
                    let sample = Array(tail)[idx]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppColors.accent)
                        .frame(width: 2.5, height: max(3.0, CGFloat(sample) * 20.0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            // Send Voice Note Button
            Button(action: finishAndSendVoiceNote) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 36, height: 36)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.white)
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.surface)
    }

    private func startVoiceRecording() {
        Task {
            let granted = await recorder.requestPermission()
            if granted {
                _ = recorder.startRecording()
            }
        }
    }

    private func finishAndSendVoiceNote() {
        if let result = recorder.stopRecording() {
            onSendVoiceNote(result.fileURL, result.duration, result.waveform)
        }
    }

    private func handleSelectedFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let fileName = url.lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")

        do {
            try FileManager.default.copyItem(at: url, to: destination)
            let mimeType = mimeTypeForPath(path: fileName)
            onSendAttachment(destination, fileName, mimeType)
        } catch {
            print("[MessageComposerView] File copy error: \(error)")
        }
    }

    private func formatRecordDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func mimeTypeForPath(path: String) -> String {
        let ext = (path as NSString).pathExtension
        if let utType = UTType(filenameExtension: ext),
           let mime = utType.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

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
    @Environment(\.chatTheme) private var theme

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
        // Floating: no bar behind it, just cards over the chat background
        VStack(spacing: 6) {
            if let reply = replyingTo {
                replyBanner(reply)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if recorder.isRecording {
                recordingBar
            } else {
                standardComposerBar
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: replyingTo?.id)
        .animation(.easeOut(duration: 0.18), value: recorder.isRecording)
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
        .onChange(of: selectedPhotoItem) { _, newItem in
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

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Reply Banner
    private func replyBanner(_ reply: ChatMessage) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Capsule()
                .fill(theme.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("chat_replying_to", reply.senderName))
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundColor(theme.accent)

                Text(reply.text.isEmpty ? (reply.attachment?.fileName ?? "Attachment") : reply.text)
                    .font(AppTypography.caption)
                    .lineLimit(1)
                    .foregroundColor(theme.surfaceText.opacity(0.6))
            }

            Spacer()

            Button(action: onCancelReply) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(theme.surfaceText.opacity(0.35))
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .fixedSize(horizontal: false, vertical: true) // keep the quote bar to the text's height
        .background(floatingCard(cornerRadius: 16))
    }

    // MARK: - Standard Composer Bar
    private var standardComposerBar: some View {
        let iconColor = theme.surfaceText.opacity(0.5)
        return HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 2) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Self.composerIcon("photo.on.rectangle.angled", color: iconColor)
                }
                .accessibilityLabel("Send photo")

                Button(action: { isShowingFileImporter = true }) {
                    Self.composerIcon("paperclip", color: iconColor)
                }
                .accessibilityLabel("Send file")

                TextField(
                    "",
                    text: $text,
                    prompt: Text(L("chat_composer_placeholder")).foregroundColor(theme.surfaceText.opacity(0.4)),
                    axis: .vertical
                )
                .font(AppTypography.body)
                .foregroundColor(theme.surfaceText)
                .tint(theme.accent)
                .lineLimit(1...5)
                .padding(.vertical, 10)
                .padding(.trailing, 12)
            }
            .padding(.leading, 4)
            .background(floatingCard(cornerRadius: 22))

            // Send text, or hold a voice note when empty
            Button(action: hasText ? onSend : startVoiceRecording) {
                Image(systemName: hasText ? "arrow.up" : "mic.fill")
                    .font(.system(size: hasText ? 18 : 19, weight: .bold))
                    .foregroundColor(theme.outgoingText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.actionGradient))
                    .shadow(color: (theme.outgoing.first ?? theme.accent).opacity(0.35), radius: 6, y: 2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(hasText ? "Send" : "Record voice message")
            .animation(.easeInOut(duration: 0.15), value: hasText)
        }
    }

    nonisolated private static func composerIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(color)
            .frame(width: 38, height: 44)
    }

    /// Opaque themed card with a soft shadow, so it reads clearly over any background
    private func floatingCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(theme.isDark ? 0.35 : 0.08), radius: 8, y: 2)
    }

    // MARK: - Voice Recording Bar
    private var recordingBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: AppSpacing.sm) {
                Button(action: {
                    recorder.cancelRecording()
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17))
                        .foregroundColor(AppColors.statusError)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Cancel recording")

                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.statusError)
                        .frame(width: 9, height: 9)

                    Text(formatRecordDuration(recorder.recordingDuration))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.surfaceText)
                }

                HStack(spacing: 2) {
                    let tail = recorder.liveWaveform.suffix(24)
                    ForEach(0..<tail.count, id: \.self) { idx in
                        let sample = Array(tail)[idx]
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.accent)
                            .frame(width: 2.5, height: max(3.0, CGFloat(sample) * 20.0))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .padding(.horizontal, 8)
            .background(floatingCard(cornerRadius: 22))

            Button(action: finishAndSendVoiceNote) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.outgoingText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.actionGradient))
            }
            .accessibilityLabel("Send voice message")
        }
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

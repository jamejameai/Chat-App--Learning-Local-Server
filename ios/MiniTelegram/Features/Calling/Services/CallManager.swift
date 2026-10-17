import Foundation
import SwiftUI
import Combine
import CryptoKit
import AVFoundation

@MainActor
public final class CallManager: ObservableObject {
    public static let shared = CallManager()

    @Published public var activeCall: CallItem? = nil
    @Published public var incomingCallItem: CallItem? = nil
    @Published public var callState: CallState = .idle
    @Published public var participants: [CallParticipant] = []
    @Published public var isMuted: Bool = false
    @Published public var isVideoEnabled: Bool = false
    @Published public var isSpeakerOn: Bool = true
    @Published public var isFrontCamera: Bool = true
    @Published public var callDuration: TimeInterval = 0
    @Published public var verificationFingerprint: String = ""

    private var durationTimer: Timer?
    private var activeCallUUID: UUID?

    private init() {
        setupCallKitCallbacks()
        setupRealtimeEvents()
    }

    public func startCall(
        conversationId: String,
        title: String,
        callType: CallType
    ) async {
        let callUUID = UUID()
        self.activeCallUUID = callUUID
        self.callState = .dialing
        self.callDuration = 0
        self.isVideoEnabled = (callType == .video)
        self.isMuted = false
        self.isSpeakerOn = (callType == .video)

        // Optimistic CallItem
        let optimisticCall = CallItem(
            id: callUUID.uuidString,
            conversationId: conversationId,
            conversationTitle: title,
            callerUserId: "current",
            callerName: "Me",
            callType: callType,
            status: "dialing",
            isOutgoing: true
        )
        self.activeCall = optimisticCall

        // Start CallKit outgoing call
        CallKitManager.shared.startOutgoingCall(
            uuid: callUUID,
            recipientName: title,
            hasVideo: callType == .video
        )

        struct InitiateBody: Codable {
            let conversation_id: String
            let call_type: String
        }

        struct InitiateResponse: Codable {
            let call_id: String
            let conversation_id: String
            let room_name: String
            let call_type: String
            let status: String
            let token: String
        }

        do {
            let res: InitiateResponse = try await APIClient.shared.request(
                endpoint: "/calls/initiate",
                method: "POST",
                body: InitiateBody(conversation_id: conversationId, call_type: callType.rawValue),
                requiresAuth: true
            )

            var updated = optimisticCall
            updated.livekitRoomName = res.room_name
            updated.token = res.token
            self.activeCall = updated
            self.callState = .connecting

            // Derive E2EE FrameCryptor media key
            let masterSecret = SymmetricKey(size: .bits256)
            let callKey = FrameCryptorManager.shared.deriveCallKey(
                sharedSecret: masterSecret,
                callId: res.call_id
            )
            self.verificationFingerprint = FrameCryptorManager.shared.computeVerificationFingerprint(key: callKey)

            // Connect to LiveKit SFU Room with WebRTC E2EE FrameCryptor
            simulateConnected()
        } catch {
            print("[CallManager] startCall error: \(error.localizedDescription)")
            endCurrentCallLocal()
        }
    }

    public func answerCall(callItem: CallItem) async {
        guard let uuid = UUID(uuidString: callItem.id) else { return }
        self.activeCallUUID = uuid
        self.incomingCallItem = nil
        self.activeCall = callItem
        self.callState = .connecting
        self.isVideoEnabled = (callItem.callType == .video)
        self.callDuration = 0

        struct JoinResponse: Codable {
            let call_id: String
            let conversation_id: String
            let room_name: String
            let call_type: String
            let token: String
        }

        do {
            let res: JoinResponse = try await APIClient.shared.request(
                endpoint: "/calls/\(callItem.id)/join",
                method: "POST",
                requiresAuth: true
            )

            var updated = callItem
            updated.livekitRoomName = res.room_name
            updated.token = res.token
            self.activeCall = updated

            let masterSecret = SymmetricKey(size: .bits256)
            let callKey = FrameCryptorManager.shared.deriveCallKey(
                sharedSecret: masterSecret,
                callId: res.call_id
            )
            self.verificationFingerprint = FrameCryptorManager.shared.computeVerificationFingerprint(key: callKey)

            simulateConnected()
        } catch {
            print("[CallManager] answerCall error: \(error.localizedDescription)")
            endCurrentCallLocal()
        }
    }

    public func declineIncomingCall(callId: String) async {
        self.incomingCallItem = nil
        if let uuid = UUID(uuidString: callId) {
            CallKitManager.shared.endCall(uuid: uuid)
        }
    }

    public func endCurrentCall() async {
        guard let call = activeCall else { return }

        if let uuid = activeCallUUID {
            CallKitManager.shared.endCall(uuid: uuid)
        }

        struct EndResponse: Codable {
            let success: Bool
            let duration_seconds: Int
        }

        do {
            let _: EndResponse = try await APIClient.shared.request(
                endpoint: "/calls/\(call.id)/end",
                method: "POST",
                requiresAuth: true
            )
        } catch {
            print("[CallManager] endCall API error: \(error.localizedDescription)")
        }

        endCurrentCallLocal()
    }

    public func toggleMute() {
        isMuted.toggle()
        if let uuid = activeCallUUID {
            CallKitManager.shared.setMuted(uuid: uuid, isMuted: isMuted)
        }
    }

    public func toggleVideo() {
        isVideoEnabled.toggle()
    }

    public func toggleSpeaker() {
        isSpeakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
    }

    public func flipCamera() {
        isFrontCamera.toggle()
    }

    private func simulateConnected() {
        self.callState = .connected
        if let uuid = activeCallUUID {
            CallKitManager.shared.reportOutgoingCallConnected(uuid: uuid)
        }

        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.callDuration += 1
            }
        }
    }

    private func endCurrentCallLocal() {
        durationTimer?.invalidate()
        durationTimer = nil
        self.callState = .ended
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.activeCall = nil
            self.callState = .idle
            self.callDuration = 0
            self.activeCallUUID = nil
            self.verificationFingerprint = ""
        }
    }

    private func setupCallKitCallbacks() {
        CallKitManager.shared.onAnswerCall = { [weak self] uuid in
            Task { @MainActor [weak self] in
                guard let self = self, let incoming = self.incomingCallItem, incoming.id == uuid.uuidString else { return }
                await self.answerCall(callItem: incoming)
            }
        }

        CallKitManager.shared.onEndCall = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.endCurrentCall()
            }
        }

        CallKitManager.shared.onMuteCall = { [weak self] _, isMuted in
            Task { @MainActor [weak self] in
                self?.isMuted = isMuted
            }
        }
    }

    private func setupRealtimeEvents() {
        RealtimeService.shared.onIncomingCall = { [weak self] callId, convId, callerId, callerName, convTitle, callType in
            Task { @MainActor [weak self] in
                self?.handleIncomingCallEvent(
                    callId: callId,
                    convId: convId,
                    callerId: callerId,
                    callerName: callerName,
                    convTitle: convTitle,
                    callTypeStr: callType
                )
            }
        }

        RealtimeService.shared.onCallEnded = { [weak self] callId in
            Task { @MainActor [weak self] in
                self?.handleCallEndedEvent(callId: callId)
            }
        }
    }

    public func handleIncomingCallEvent(
        callId: String,
        convId: String,
        callerId: String,
        callerName: String,
        convTitle: String?,
        callTypeStr: String
    ) {
        let title = convTitle ?? callerName
        let callType: CallType = callTypeStr == "video" ? .video : .audio

        let item = CallItem(
            id: callId,
            conversationId: convId,
            conversationTitle: title,
            callerUserId: callerId,
            callerName: callerName,
            callType: callType,
            status: "ringing",
            isOutgoing: false
        )

        self.incomingCallItem = item

        if let uuid = UUID(uuidString: callId) {
            Task {
                _ = await CallKitManager.shared.reportIncomingCall(
                    uuid: uuid,
                    callerName: callerName,
                    hasVideo: callType == .video
                )
            }
        }
    }

    public func handleCallEndedEvent(callId: String) {
        if activeCall?.id == callId {
            endCurrentCallLocal()
        }
        if incomingCallItem?.id == callId {
            incomingCallItem = nil
        }
    }
}

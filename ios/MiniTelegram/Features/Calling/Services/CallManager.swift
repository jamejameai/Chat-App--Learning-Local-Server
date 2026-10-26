import Foundation
import SwiftUI
import Combine
import AudioToolbox
import UserNotifications
import LiveKit

/// Voice and video calls over the LiveKit server (WebRTC).
///
/// Caller: POST /calls/initiate → the server rings the other members' phones over the live connection →
/// the caller joins the LiveKit room and waits. Callee: accepts → POST /calls/:id/join → joins the same room.
/// Hanging up or declining calls POST /calls/:id/end, which tells the other phone to stop.
/// LiveKit manages the audio session itself (no CallKit: without Apple VoIP push it only works while the
/// app is open anyway, and mixing it with LiveKit's audio handling is a classic cause of silent calls).
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
    @Published public private(set) var localVideoTrack: VideoTrack?
    @Published public private(set) var remoteVideoTrack: VideoTrack?
    @Published public var errorMessage: String?

    private var room: Room?
    private let roomEvents = RoomEvents()
    private var durationTimer: Timer?
    private var ringTimer: Timer?
    private var unansweredTimeout: Task<Void, Never>?
    private var hasRemoteJoined = false

    /// How long a call rings before giving up.
    private static let ringTimeoutSeconds: UInt64 = 45

    private init() {
        setupRealtimeEvents()
    }

    // MARK: - Server responses

    private struct CallSessionResponse: Decodable {
        let call_id: String
        let conversation_id: String
        let room_name: String
        let call_type: String
        let token: String
        let livekit_url: String?
    }

    // MARK: - Outgoing

    public func startCall(
        conversationId: String,
        title: String,
        callType: CallType
    ) async {
        guard activeCall == nil else { return }
        prepareForCall(video: callType == .video)
        callState = .dialing

        // Shown immediately while the server sets the call up
        activeCall = CallItem(
            id: "",
            conversationId: conversationId,
            conversationTitle: title,
            callerUserId: SessionStore.currentUserId ?? "",
            callerName: "Me",
            callType: callType,
            status: "dialing",
            isOutgoing: true
        )

        struct InitiateBody: Codable {
            let conversation_id: String
            let call_type: String
        }

        do {
            let res: CallSessionResponse = try await APIClient.shared.request(
                endpoint: "/calls/initiate",
                method: "POST",
                body: InitiateBody(conversation_id: conversationId, call_type: callType.rawValue)
            )

            var call = CallItem(
                id: res.call_id, // the server's id: hang-up and "call ended" match by it
                conversationId: conversationId,
                conversationTitle: title,
                callerUserId: SessionStore.currentUserId ?? "",
                callerName: "Me",
                callType: callType,
                status: "dialing",
                isOutgoing: true
            )
            call.livekitRoomName = res.room_name
            call.token = res.token
            activeCall = call

            try await connect(url: res.livekit_url, token: res.token, video: callType == .video)
            if !hasRemoteJoined {
                callState = .ringing
                startUnansweredTimeout()
            }
        } catch {
            errorMessage = Self.friendlyError(error)
            await endCurrentCall()
        }
    }

    // MARK: - Incoming

    public func answerCall(callItem: CallItem) async {
        stopRinging()
        incomingCallItem = nil
        prepareForCall(video: callItem.callType == .video)
        activeCall = callItem
        callState = .connecting

        do {
            let res: CallSessionResponse = try await APIClient.shared.request(
                endpoint: "/calls/\(callItem.id)/join",
                method: "POST"
            )
            var updated = callItem
            updated.livekitRoomName = res.room_name
            updated.token = res.token
            activeCall = updated

            try await connect(url: res.livekit_url, token: res.token, video: callItem.callType == .video)
            if !hasRemoteJoined {
                // The caller hung up while this phone was connecting
                callState = .connecting
                startUnansweredTimeout()
            }
        } catch {
            errorMessage = Self.friendlyError(error)
            await endCurrentCall()
        }
    }

    public func declineIncomingCall(callId: String) async {
        stopRinging()
        incomingCallItem = nil
        // Tell the server so the caller stops ringing
        await postEnd(callId: callId)
    }

    public func endCurrentCall() async {
        if let call = activeCall, !call.id.isEmpty {
            await postEnd(callId: call.id)
        }
        finishCallLocally()
    }

    // MARK: - Controls

    public func toggleMute() {
        isMuted.toggle()
        let enabled = !isMuted
        if let room {
            Task { try? await room.localParticipant.setMicrophone(enabled: enabled) }
        }
    }

    public func toggleVideo() {
        isVideoEnabled.toggle()
        let enabled = isVideoEnabled
        guard let room else { return }
        Task {
            let publication = try? await room.localParticipant.setCamera(enabled: enabled)
            self.localVideoTrack = enabled ? publication?.track as? VideoTrack : nil
            if enabled && !self.isSpeakerOn {
                self.toggleSpeaker() // video calls are usually held away from the ear
            }
        }
    }

    public func toggleSpeaker() {
        isSpeakerOn.toggle()
        AudioManager.shared.audioSession.isSpeakerOutputPreferred = isSpeakerOn
    }

    public func flipCamera() {
        guard let camera = (localVideoTrack as? LocalVideoTrack)?.capturer as? CameraCapturer else { return }
        Task {
            if (try? await camera.switchCameraPosition()) != nil {
                self.isFrontCamera.toggle()
            }
        }
    }

    // MARK: - LiveKit

    private func connect(url: String?, token: String, video: Bool) async throws {
        guard let url, !url.isEmpty else { throw CallError.notConfigured }

        let room = Room(delegate: roomEvents)
        self.room = room
        try await room.connect(url: url, token: token)
        try await room.localParticipant.setMicrophone(enabled: !isMuted)
        if video {
            let publication = try await room.localParticipant.setCamera(enabled: true)
            localVideoTrack = publication?.track as? VideoTrack
        }
        // The other person may already be in the room (e.g. answering an incoming call)
        if !room.remoteParticipants.isEmpty {
            remoteJoined()
        }
        refreshRemoteVideo()
    }

    fileprivate func remoteJoined() {
        guard activeCall != nil, !hasRemoteJoined else { return }
        hasRemoteJoined = true
        unansweredTimeout?.cancel()
        callState = .connected
        startDurationTimer()
    }

    fileprivate func refreshRemoteVideo() {
        remoteVideoTrack = room?.remoteParticipants.values.lazy.compactMap { $0.firstCameraVideoTrack }.first
    }

    fileprivate func remoteLeft() {
        guard let room, room.remoteParticipants.isEmpty, hasRemoteJoined else {
            refreshRemoteVideo()
            return
        }
        // Everyone else hung up
        Task { await endCurrentCall() }
    }

    fileprivate func roomDisconnected() {
        guard activeCall != nil, callState != .ended else { return }
        Task { await endCurrentCall() }
    }

    // MARK: - Realtime events

    private func setupRealtimeEvents() {
        RealtimeService.shared.onIncomingCall = { callId, convId, callerId, callerName, convTitle, callType in
            Task { @MainActor in
                CallManager.shared.handleIncomingCallEvent(
                    callId: callId,
                    convId: convId,
                    callerId: callerId,
                    callerName: callerName,
                    convTitle: convTitle,
                    callTypeStr: callType
                )
            }
        }

        RealtimeService.shared.onCallEnded = { callId in
            Task { @MainActor in
                CallManager.shared.handleCallEndedEvent(callId: callId)
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
        // Already in a call: ignore (the caller's call times out)
        guard activeCall == nil, incomingCallItem == nil else { return }

        let callType: CallType = callTypeStr == "video" ? .video : .audio
        incomingCallItem = CallItem(
            id: callId,
            conversationId: convId,
            conversationTitle: convTitle ?? callerName,
            callerUserId: callerId,
            callerName: callerName,
            callType: callType,
            status: "ringing",
            isOutgoing: false
        )
        startRinging()

        if UIApplication.shared.applicationState != .active && !MessageAlertManager.barkCoversBackgroundAlerts {
            let content = UNMutableNotificationContent()
            content.title = callerName
            content.body = callType == .video ? "Incoming video call" : "Incoming voice call"
            content.sound = .default
            content.userInfo = ["conversation_id": convId]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "call-\(callId)", content: content, trigger: nil))
        }

        LuxuryAlertManager.shared.showIncomingCall(
            callerName: callerName,
            callId: callId,
            convId: convId,
            callType: callTypeStr
        )

        // Stop ringing if nobody answers
        let id = callId
        Task {
            try? await Task.sleep(nanoseconds: Self.ringTimeoutSeconds * 1_000_000_000)
            if self.incomingCallItem?.id == id {
                self.stopRinging()
                self.incomingCallItem = nil
                LuxuryAlertManager.shared.dismissAlert()
            }
        }
    }

    public func handleCallEndedEvent(callId: String) {
        LuxuryAlertManager.shared.dismissAlert()
        if incomingCallItem?.id == callId {
            stopRinging()
            incomingCallItem = nil
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
        }
        if let call = activeCall, call.id == callId {
            finishCallLocally()
        }
    }

    // MARK: - Helpers

    private func prepareForCall(video: Bool) {
        errorMessage = nil
        hasRemoteJoined = false
        callDuration = 0
        isMuted = false
        isVideoEnabled = video
        isFrontCamera = true
        // Earpiece for voice calls, loudspeaker for video calls
        isSpeakerOn = video
        AudioManager.shared.audioSession.isSpeakerOutputPreferred = video
    }

    private func postEnd(callId: String) async {
        struct EndResponse: Codable {
            let success: Bool
        }
        _ = try? await APIClient.shared.request(endpoint: "/calls/\(callId)/end", method: "POST") as EndResponse
    }

    private func finishCallLocally() {
        stopRinging()
        unansweredTimeout?.cancel()
        unansweredTimeout = nil
        durationTimer?.invalidate()
        durationTimer = nil

        let finishedRoom = room
        room = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        hasRemoteJoined = false
        Task { await finishedRoom?.disconnect() }

        guard activeCall != nil else { return }
        callState = .ended
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // show "Call ended" briefly
            if self.callState == .ended {
                self.activeCall = nil
                self.callState = .idle
                self.callDuration = 0
            }
        }
    }

    private func startUnansweredTimeout() {
        unansweredTimeout?.cancel()
        unansweredTimeout = Task {
            try? await Task.sleep(nanoseconds: Self.ringTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled, !self.hasRemoteJoined, self.activeCall != nil else { return }
            self.errorMessage = "No answer"
            await self.endCurrentCall()
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                CallManager.shared.callDuration += 1
            }
        }
    }

    private func startRinging() {
        stopRinging()
        let ring = {
            AudioServicesPlaySystemSound(1005)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        ring()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in ring() }
    }

    private func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
    }

    private enum CallError: LocalizedError {
        case notConfigured
        var errorDescription: String? { "Calling isn't set up on the server yet." }
    }

    private static func friendlyError(_ error: Error) -> String {
        if error is LiveKitError {
            // LiveKit runs on the home server; it can't be reached from outside the home network yet
            return "Couldn't connect the call. Calls work when both phones can reach the server (same Wi-Fi as the server)."
        }
        return "Couldn't connect the call: \(error.localizedDescription)"
    }
}

/// LiveKit reports room events on its own threads; forward them to the CallManager on the main actor.
private final class RoomEvents: NSObject, RoomDelegate, @unchecked Sendable {
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in CallManager.shared.remoteJoined() }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in CallManager.shared.remoteLeft() }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            CallManager.shared.remoteJoined()
            CallManager.shared.refreshRemoteVideo()
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in CallManager.shared.refreshRemoteVideo() }
    }

    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        Task { @MainActor in CallManager.shared.refreshRemoteVideo() }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in CallManager.shared.roomDisconnected() }
    }
}

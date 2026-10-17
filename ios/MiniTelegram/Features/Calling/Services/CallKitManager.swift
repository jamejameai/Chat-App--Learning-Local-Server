import Foundation
import CallKit
import AVFoundation

public final class CallKitManager: NSObject, @unchecked Sendable, CXProviderDelegate {
    public static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController: CXCallController

    public var onAnswerCall: (@Sendable (UUID) -> Void)?
    public var onEndCall: (@Sendable (UUID) -> Void)?
    public var onMuteCall: (@Sendable (UUID, Bool) -> Void)?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true

        self.provider = CXProvider(configuration: config)
        self.callController = CXCallController()
        super.init()
        self.provider.setDelegate(self, queue: .main)
    }

    public func reportIncomingCall(uuid: UUID, callerName: String, hasVideo: Bool) async -> Bool {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsDTMF = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        return await withCheckedContinuation { continuation in
            provider.reportNewIncomingCall(with: uuid, update: update) { error in
                if let error = error {
                    print("[CallKitManager] Failed to report incoming call: \(error)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    public func startOutgoingCall(uuid: UUID, recipientName: String, hasVideo: Bool) {
        let handle = CXHandle(type: .generic, value: recipientName)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = hasVideo

        let transaction = CXTransaction(action: startAction)
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKitManager] Failed to request start call action: \(error)")
            }
        }
    }

    public func endCall(uuid: UUID) {
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKitManager] Failed to request end call action: \(error)")
            }
        }
    }

    public func setMuted(uuid: UUID, isMuted: Bool) {
        let muteAction = CXSetMutedCallAction(call: uuid, muted: isMuted)
        let transaction = CXTransaction(action: muteAction)
        callController.request(transaction) { error in
            if let error = error {
                print("[CallKitManager] Failed to request mute call action: \(error)")
            }
        }
    }

    public func reportOutgoingCallConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    // MARK: - CXProviderDelegate
    public func providerDidReset(_ provider: CXProvider) {
        print("[CallKitManager] Provider did reset")
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        configureAudioSession()
        onAnswerCall?(action.callUUID)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        onEndCall?(action.callUUID)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        onMuteCall?(action.callUUID, action.isMuted)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("[CallKitManager] AudioSession did activate")
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("[CallKitManager] AudioSession did deactivate")
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[CallKitManager] Failed to configure AVAudioSession: \(error)")
        }
    }
}

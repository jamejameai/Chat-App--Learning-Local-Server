import Combine
@preconcurrency import CoreLocation
import Foundation
import Security

@MainActor
public final class LiveLocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    public static let shared = LiveLocationManager()

    @Published public private(set) var authorizationStatus: CLAuthorizationStatus
    @Published public private(set) var lastLocation: CLLocation?
    @Published public private(set) var isUpdating = false
    @Published public private(set) var permissionError: String?

    public var onLocationUpdate: ((CLLocation) -> Void)?
    public var onPermissionLost: (() -> Void)?

    private let manager: CLLocationManager
    private var sharingRequested = false
    private var requestedAlwaysAuthorization = false

    private override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 15
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    private var isViewing = false

    public func startViewingLocation() {
        isViewing = true
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startLocationUpdates()
        }
    }

    public func stopViewingLocation() {
        isViewing = false
        if !sharingRequested {
            isUpdating = false
            manager.stopUpdatingLocation()
        }
    }

    public func requestWhenInUseAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    public func clearPermissionError() {
        permissionError = nil
    }

    public func beginSharing() {
        sharingRequested = true
        isViewing = true
        permissionError = nil
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways:
            startLocationUpdates()
        case .authorizedWhenInUse:
            requestedAlwaysAuthorization = true
            manager.requestAlwaysAuthorization()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            permissionError = "Allow Always location access in Settings to share your live location in the background."
            stopLocationUpdates()
            onPermissionLost?()
        @unknown default:
            permissionError = "Location permission is unavailable."
        }
    }

    public func stopSharing() {
        sharingRequested = false
        requestedAlwaysAuthorization = false
        if !isViewing {
            isUpdating = false
            lastLocation = nil
            manager.stopUpdatingLocation()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isViewing && !isUpdating {
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                startLocationUpdates()
            }
        }
        guard sharingRequested else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways:
            startLocationUpdates()
        case .authorizedWhenInUse where !requestedAlwaysAuthorization:
            requestedAlwaysAuthorization = true
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            permissionError = "Choose Always Allow to keep sharing while the app is in the background."
            stopLocationUpdates()
            onPermissionLost?()
        case .denied, .restricted:
            permissionError = "Location access is off. Change it in Settings to share your live location."
            stopLocationUpdates()
            onPermissionLost?()
        case .notDetermined:
            break
        @unknown default:
            permissionError = "Location permission is unavailable."
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        if sharingRequested {
            onLocationUpdate?(location)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        permissionError = error.localizedDescription
    }

    private func startLocationUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func stopLocationUpdates() {
        sharingRequested = false
        isUpdating = false
        manager.stopUpdatingLocation()
    }
}

@MainActor
public final class LiveLocationViewModel: ObservableObject {
    public static let shared = LiveLocationViewModel()

    @Published public private(set) var friendLocations: [LiveLocationDTO] = []
    @Published public private(set) var availableFriends: [FriendDTO] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSharing = false
    @Published public private(set) var isPublishingFirstLocation = false
    @Published public private(set) var isLoadingAudience = false
    @Published public private(set) var isStopPending = false
    @Published public var errorMessage: String?

    public var viewerCount: Int {
        viewerIDsForPendingShare.count
    }

    public var myLocation: CLLocation? {
        locationManager.lastLocation
    }

    private let locationManager = LiveLocationManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var stopRequestPending = false
    private var pendingStopUserId: String?
    private let pendingStopKeyPrefix = "live_location_pending_stop_"
    private let pendingStopUserKey = "live_location_pending_stop_user"
    private let stopTokenKeyPrefix = "live_location_stop_token_"
    private var loadedAccountUserId: String?
    private var activeShareUserId: String?
    private var activeShareId: String?
    private var didLoadShareState = false
    private var shareActionRevision = 0
    private var friendFetchGeneration = 0
    private var locationEventRevision = 0
    private var locationEventChanges: [String: LocationEventChange] = [:]
    private var viewerIDsForPendingShare: [String] = []
    private var stopTokenForPendingShare: String?
    private var didCreateServerShare = false
    private var isStartingServerShare = false
    private var startingShareUserId: String?
    private var shouldStopAfterStartRequest = false
    private var startRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopRequestsInFlight = Set<String>()
    private var stopRequestWaiters: [String: [CheckedContinuation<Bool, Never>]] = [:]
    private var stoppedShareIdsByUser: [String: Set<String>] = [:]

    private struct LocationEventChange {
        let revision: Int
        let location: LiveLocationDTO?
    }

    private init() {
        pendingStopUserId = SessionStore.currentUserId
        loadedAccountUserId = SessionStore.currentUserId
        if let pendingStopUserId {
            stopRequestPending = UserDefaults.standard.bool(
                forKey: pendingStopKeyPrefix + pendingStopUserId
            )
            isStopPending = stopRequestPending
        }
        locationManager.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                await self?.publish(location)
            }
        }
        locationManager.onPermissionLost = { [weak self] in
            Task { @MainActor in
                await self?.stopSharing()
            }
        }

        RealtimeService.shared.onLocationUpdated = { [weak self] location in
            Task { @MainActor in
                self?.merge(location)
            }
        }
        RealtimeService.shared.onLocationStopped = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let userId = event.user_id
                if userId == SessionStore.currentUserId {
                    guard let shareId = event.share_id,
                          shareId == self.activeShareId else { return }
                    self.shareActionRevision += 1
                    self.isSharing = false
                    self.isPublishingFirstLocation = false
                    self.didCreateServerShare = false
                    self.activeShareUserId = nil
                    self.activeShareId = nil
                    self.locationManager.stopSharing()
                    self.setStopRequestPending(false, for: userId)
                } else {
                    if let shareId = event.share_id {
                        self.stoppedShareIdsByUser[userId, default: []].insert(shareId)
                    }
                    if let shareId = event.share_id,
                       let location = self.friendLocations.first(where: { $0.user_id == userId }),
                       let locationShareId = location.share_id,
                       locationShareId != shareId {
                        return
                    }
                    self.friendLocations.removeAll { $0.user_id == userId }
                    self.recordLocationEvent(userId: userId, location: nil)
                }
            }
        }

        NotificationCenter.default.publisher(for: .realtimeReconnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshAfterReconnect()
                }
            }
            .store(in: &cancellables)
    }

    public func loadFriendLocations() async {
        guard let userId = SessionStore.currentUserId else {
            clearAccountState(for: loadedAccountUserId)
            return
        }
        prepareAccountState(for: userId)
        friendFetchGeneration += 1
        let fetchGeneration = friendFetchGeneration
        isLoading = true
        defer {
            if fetchGeneration == friendFetchGeneration {
                isLoading = false
            }
        }
        await retryPendingRevocation()
        guard fetchGeneration == friendFetchGeneration,
              SessionStore.currentUserId == userId else { return }
        restorePendingStopForCurrentUser()
        do {
            if stopRequestPending {
                _ = await sendStopRequest()
            }
            guard fetchGeneration == friendFetchGeneration,
                  SessionStore.currentUserId == userId else { return }
            let locationRevisionAtRequest = locationEventRevision
            async let friends: [LiveLocationDTO] = APIClient.shared.request(
                endpoint: "/locations/friends",
                expectedSessionUserId: userId
            )
            if !didLoadShareState {
                let shareActionRevisionAtRequest = shareActionRevision
                let shareState: LiveLocationShareState = try await APIClient.shared.request(
                    endpoint: "/locations/me",
                    expectedSessionUserId: userId
                )
                if fetchGeneration == friendFetchGeneration,
                   SessionStore.currentUserId == userId,
                   shareActionRevisionAtRequest == shareActionRevision,
                   !didLoadShareState {
                    didLoadShareState = true
                    viewerIDsForPendingShare = shareState.location?.viewer_ids ?? []
                    if shareState.sharing && viewerIDsForPendingShare.isEmpty {
                        setStopRequestPending(true, for: userId)
                        _ = await sendStopRequest(for: userId)
                    }
                    let shouldResumeSharing = shareState.sharing &&
                        !viewerIDsForPendingShare.isEmpty &&
                        !stopRequestPending
                    activeShareUserId = shouldResumeSharing ? userId : nil
                    activeShareId = shouldResumeSharing ? shareState.location?.share_id : nil
                    isSharing = shouldResumeSharing
                    isPublishingFirstLocation = shouldResumeSharing
                    didCreateServerShare = shouldResumeSharing
                    if shouldResumeSharing {
                        locationManager.beginSharing()
                    } else {
                        locationManager.stopSharing()
                    }
                }
            }
            let fetchedLocations = try await friends
            guard fetchGeneration == friendFetchGeneration,
                  SessionStore.currentUserId == userId else { return }
            var locationsByUser = Dictionary(
                uniqueKeysWithValues: fetchedLocations.map { ($0.user_id, $0) }
            )
            locationsByUser = locationsByUser.filter { userId, location in
                guard let shareId = location.share_id else { return true }
                return stoppedShareIdsByUser[userId]?.contains(shareId) != true
            }
            for (userId, event) in locationEventChanges where event.revision > locationRevisionAtRequest {
                if let location = event.location {
                    locationsByUser[userId] = location
                } else {
                    locationsByUser.removeValue(forKey: userId)
                }
            }
            friendLocations = locationsByUser.values.sorted {
                $0.updated_at > $1.updated_at
            }
            locationEventChanges = locationEventChanges.filter {
                $0.value.revision > locationRevisionAtRequest
            }
        } catch {
            if fetchGeneration == friendFetchGeneration,
               SessionStore.currentUserId == userId {
                errorMessage = "Couldn't load live locations: \(error.localizedDescription)"
            }
        }
    }

    public func loadShareAudience() async -> [FriendDTO] {
        guard let userId = SessionStore.currentUserId else {
            errorMessage = "Sign in again before sharing your live location."
            return []
        }
        isLoadingAudience = true
        defer { isLoadingAudience = false }
        do {
            let friends: [FriendDTO] = try await APIClient.shared.request(
                endpoint: "/friends",
                expectedSessionUserId: userId
            )
            guard SessionStore.currentUserId == userId else { return [] }
            availableFriends = friends
            if friends.isEmpty {
                errorMessage = "Add a friend before sharing your live location."
            }
            return friends
        } catch {
            if SessionStore.currentUserId == userId {
                errorMessage = "Couldn't load friends: \(error.localizedDescription)"
            }
            return []
        }
    }

    public func startSharing(with viewerIDs: Set<String>) {
        let availableIDs = Set(availableFriends.map(\.id))
        guard !isSharing, !isStartingServerShare, !stopRequestPending,
              !viewerIDs.isEmpty, viewerIDs.isSubset(of: availableIDs) else { return }
        guard let userId = SessionStore.currentUserId else {
            errorMessage = "Sign in again before sharing your live location."
            return
        }
        let stopToken: String
        do {
            stopToken = try makeStopToken()
            try KeychainManager.shared.saveString(
                key: stopTokenKeyPrefix + userId,
                value: stopToken
            )
        } catch {
            errorMessage = "Couldn't securely prepare location sharing: \(error.localizedDescription)"
            return
        }
        shareActionRevision += 1
        didLoadShareState = true
        isSharing = true
        activeShareUserId = userId
        activeShareId = nil
        pendingStopUserId = userId
        isPublishingFirstLocation = true
        viewerIDsForPendingShare = viewerIDs.sorted()
        stopTokenForPendingShare = stopToken
        didCreateServerShare = false
        isStartingServerShare = false
        shouldStopAfterStartRequest = false
        errorMessage = nil
        locationManager.beginSharing()
    }

    public func stopSharing() async {
        guard let userId = SessionStore.currentUserId ?? activeShareUserId ?? pendingStopUserId else {
            isSharing = false
            isPublishingFirstLocation = false
            didCreateServerShare = false
            activeShareUserId = nil
            activeShareId = nil
            locationManager.stopSharing()
            return
        }
        shareActionRevision += 1
        isSharing = false
        isPublishingFirstLocation = false
        didCreateServerShare = false
        if activeShareUserId == userId {
            activeShareUserId = nil
            activeShareId = nil
        }
        locationManager.stopSharing()
        pendingStopUserId = userId
        setStopRequestPending(true, for: userId)
        if startingShareUserId == userId {
            shouldStopAfterStartRequest = true
            return
        }
        _ = await sendStopRequest(for: userId)
    }

    public func retryStopSharing() async {
        guard let userId = pendingStopUserId else { return }
        _ = await sendStopRequest(for: userId)
    }

    public func stopForLogout() async -> Bool {
        guard let userId = SessionStore.currentUserId else { return false }
        let hasStopToken = (try? KeychainManager.shared.getString(
            key: stopTokenKeyPrefix + userId
        )) != nil
        let needsRevocation = hasStopToken ||
            activeShareUserId == userId ||
            UserDefaults.standard.bool(forKey: pendingStopKeyPrefix + userId)
        shareActionRevision += 1
        isSharing = false
        isPublishingFirstLocation = false
        didCreateServerShare = false
        activeShareUserId = nil
        activeShareId = nil
        locationManager.stopSharing()
        clearAccountState(for: userId)
        guard needsRevocation else { return true }
        pendingStopUserId = userId
        setStopRequestPending(true, for: userId)
        if startingShareUserId == userId {
            shouldStopAfterStartRequest = true
            await waitForServerStartRequest(for: userId)
        }
        return await sendStopRequest(for: userId)
    }

    public func stopAfterSessionEnded(userId: String?) async {
        guard let userId else {
            if activeShareUserId != nil {
                shareActionRevision += 1
                isSharing = false
                isPublishingFirstLocation = false
                didCreateServerShare = false
                activeShareUserId = nil
                activeShareId = nil
                locationManager.stopSharing()
            }
            return
        }
        let hadLocalShareState = activeShareUserId == userId ||
            (pendingStopUserId == userId && stopRequestPending)
        if activeShareUserId == userId {
            shareActionRevision += 1
            isSharing = false
            isPublishingFirstLocation = false
            didCreateServerShare = false
            activeShareUserId = nil
            activeShareId = nil
            locationManager.stopSharing()
        }
        clearAccountState(for: userId)
        let hasStopToken = (try? KeychainManager.shared.getString(
            key: stopTokenKeyPrefix + userId
        )) != nil
        guard hadLocalShareState || hasStopToken else { return }
        pendingStopUserId = userId
        setStopRequestPending(true, for: userId)
        if startingShareUserId == userId {
            shouldStopAfterStartRequest = true
            await waitForServerStartRequest(for: userId)
        }
        _ = await sendStopRequest(for: userId)
    }

    public func retryPendingRevocation() async {
        var pendingUserIds = Set<String>(
            UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> String? in
                guard key.hasPrefix(pendingStopKeyPrefix), value as? Bool == true else {
                    return nil
                }
                return String(key.dropFirst(pendingStopKeyPrefix.count))
            }
        )
        if let legacyPendingUserId = UserDefaults.standard.string(forKey: pendingStopUserKey) {
            pendingUserIds.insert(legacyPendingUserId)
        }
        for userId in pendingUserIds {
            if startingShareUserId == userId {
                await waitForServerStartRequest(for: userId)
            }
            if SessionStore.currentUserId == userId {
                pendingStopUserId = userId
                stopRequestPending = true
                isStopPending = true
            }
            _ = await sendStopRequest(for: userId)
        }
    }

    private func publish(_ location: CLLocation) async {
        guard isSharing,
              let ownerUserId = activeShareUserId,
              location.horizontalAccuracy >= 0 else { return }
        if !didCreateServerShare {
            guard !isStartingServerShare else { return }
            isStartingServerShare = true
            startingShareUserId = ownerUserId
            let actionRevisionAtStart = shareActionRevision
            let payload = LiveLocationStartPayload(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                heading: location.course >= 0 ? location.course : nil,
                accuracy: location.horizontalAccuracy,
                viewer_ids: viewerIDsForPendingShare,
                stop_token: stopTokenForPendingShare ?? ""
            )
            do {
                let receipt: LiveLocationUpdateReceipt = try await APIClient.shared.request(
                    endpoint: "/locations/me",
                    method: "POST",
                    body: payload,
                    expectedSessionUserId: ownerUserId
                )
                finishServerStartRequest()
                if shouldStopAfterStartRequest || actionRevisionAtStart != shareActionRevision {
                    shouldStopAfterStartRequest = false
                    _ = await sendStopRequest(for: ownerUserId)
                    return
                }
                if activeShareUserId == ownerUserId,
                   SessionStore.currentUserId == ownerUserId {
                    activeShareId = receipt.share_id
                    didCreateServerShare = true
                    isPublishingFirstLocation = false
                }
                return
            } catch {
                finishServerStartRequest()
                if shouldStopAfterStartRequest || actionRevisionAtStart != shareActionRevision {
                    shouldStopAfterStartRequest = false
                    _ = await sendStopRequest(for: ownerUserId)
                    return
                }
                await handlePublishFailure(error, for: ownerUserId)
                return
            }
        }

        let payload = LiveLocationUpdatePayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            heading: location.course >= 0 ? location.course : nil,
            accuracy: location.horizontalAccuracy
        )
        do {
            let _: LiveLocationUpdateReceipt = try await APIClient.shared.request(
                endpoint: "/locations/me",
                method: "PUT",
                body: payload,
                expectedSessionUserId: ownerUserId
            )
            if activeShareUserId == ownerUserId,
               SessionStore.currentUserId == ownerUserId {
                isPublishingFirstLocation = false
            }
        } catch {
            await handlePublishFailure(error, for: ownerUserId)
        }
    }

    private func handlePublishFailure(_ error: Error, for userId: String) async {
        let isCurrentShare = activeShareUserId == userId
        if isCurrentShare {
            shareActionRevision += 1
            isSharing = false
            isPublishingFirstLocation = false
            didCreateServerShare = false
            activeShareUserId = nil
            activeShareId = nil
            locationManager.stopSharing()
        }
        let publishError = "Couldn't share your location: \(error.localizedDescription)"
        setStopRequestPending(true, for: userId)
        let stopped = await sendStopRequest(for: userId)
        if stopped && isCurrentShare && SessionStore.currentUserId == userId {
            errorMessage = publishError
        }
    }

    private func sendStopRequest() async -> Bool {
        guard let userId = pendingStopUserId else { return !stopRequestPending }
        return await sendStopRequest(for: userId)
    }

    private func sendStopRequest(for userId: String) async -> Bool {
        if stopRequestsInFlight.contains(userId) {
            return await withCheckedContinuation { continuation in
                stopRequestWaiters[userId, default: []].append(continuation)
            }
        }
        stopRequestsInFlight.insert(userId)
        let result = await performStopRequest(for: userId)
        stopRequestsInFlight.remove(userId)
        let waiters = stopRequestWaiters.removeValue(forKey: userId) ?? []
        waiters.forEach { $0.resume(returning: result) }
        return result
    }

    private func performStopRequest(for userId: String) async -> Bool {
        return await revokeSharingWithStopToken(for: userId)
    }

    private func revokeSharingWithStopToken(for userId: String) async -> Bool {
        guard let stopToken = try? KeychainManager.shared.getString(
                key: stopTokenKeyPrefix + userId
              ) else {
            // No stop token on this phone: without this the pending stop could never finish,
            // and it blocks every new share while showing "couldn't be reached" offline
            return await stopSharingAsSignedInUser(userId)
        }
        do {
            let payload = LiveLocationStopPayload(stop_token: stopToken)
            let _: LiveLocationStopReceipt = try await APIClient.shared.request(
                endpoint: "/locations/revoke",
                method: "POST",
                body: payload,
                requiresAuth: false
            )
            clearStopRequestPending(for: userId)
            return true
        } catch APIError.serverError(let statusCode, _) where (400..<500).contains(statusCode) {
            // The server answered but refused this token: retrying it would fail forever
            return await stopSharingAsSignedInUser(userId)
        } catch {
            if pendingStopUserId == userId || SessionStore.currentUserId == userId {
                errorMessage = "The server couldn't be reached to clear your last location. Tap to retry."
            }
            return false
        }
    }

    /// Stops the share through the signed-in account instead of the stop token.
    private func stopSharingAsSignedInUser(_ userId: String) async -> Bool {
        guard SessionStore.currentUserId == userId else {
            if pendingStopUserId == userId {
                errorMessage = "The server couldn't be reached to clear your last location. Tap to retry."
            }
            return false
        }
        do {
            let _: LiveLocationStopReceipt = try await APIClient.shared.request(
                endpoint: "/locations/me",
                method: "DELETE",
                expectedSessionUserId: userId
            )
            clearStopRequestPending(for: userId)
            return true
        } catch {
            if pendingStopUserId == userId || SessionStore.currentUserId == userId {
                errorMessage = "The server couldn't be reached to clear your last location. Tap to retry."
            }
            return false
        }
    }

    private func refreshAfterReconnect() async {
        if stopRequestPending {
            _ = await sendStopRequest()
        }
        await loadFriendLocations()
    }

    private func merge(_ location: LiveLocationDTO) {
        if let shareId = location.share_id,
           stoppedShareIdsByUser[location.user_id]?.contains(shareId) == true {
            return
        }
        friendLocations.removeAll { $0.user_id == location.user_id }
        friendLocations.append(location)
        recordLocationEvent(userId: location.user_id, location: location)
    }

    private func recordLocationEvent(userId: String, location: LiveLocationDTO?) {
        locationEventRevision += 1
        locationEventChanges[userId] = LocationEventChange(
            revision: locationEventRevision,
            location: location
        )
    }

    private func finishServerStartRequest() {
        isStartingServerShare = false
        startingShareUserId = nil
        let waiters = startRequestWaiters
        startRequestWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForServerStartRequest(for userId: String) async {
        guard startingShareUserId == userId else { return }
        await withCheckedContinuation { continuation in
            if startingShareUserId == userId {
                startRequestWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    private func setStopRequestPending(_ pending: Bool, for userId: String? = nil) {
        guard let userId = userId ?? pendingStopUserId ?? SessionStore.currentUserId else {
            stopRequestPending = pending
            isStopPending = pending
            return
        }
        if pending {
            UserDefaults.standard.set(true, forKey: pendingStopKeyPrefix + userId)
            if SessionStore.currentUserId == userId {
                pendingStopUserId = userId
                stopRequestPending = true
                isStopPending = true
            }
        } else {
            clearStopRequestPending(for: userId)
        }
    }

    private func clearStopRequestPending(for userId: String) {
        UserDefaults.standard.set(false, forKey: pendingStopKeyPrefix + userId)
        if UserDefaults.standard.string(forKey: pendingStopUserKey) == userId {
            UserDefaults.standard.removeObject(forKey: pendingStopUserKey)
        }
        KeychainManager.shared.delete(key: stopTokenKeyPrefix + userId)
        if pendingStopUserId == userId {
            stopRequestPending = false
            isStopPending = false
            pendingStopUserId = nil
            errorMessage = nil
        }
    }

    private func makeStopToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func restorePendingStopForCurrentUser() {
        let currentUserId = SessionStore.currentUserId
        guard currentUserId != pendingStopUserId else { return }
        pendingStopUserId = currentUserId
        stopRequestPending = currentUserId.map {
            UserDefaults.standard.bool(forKey: pendingStopKeyPrefix + $0)
        } ?? false
        isStopPending = stopRequestPending
    }

    private func prepareAccountState(for userId: String) {
        guard loadedAccountUserId != userId else { return }
        if let previousShareUserId = activeShareUserId,
           previousShareUserId != userId,
           isSharing || isStartingServerShare {
            setStopRequestPending(true, for: previousShareUserId)
            shareActionRevision += 1
            locationManager.stopSharing()
            activeShareUserId = nil
            activeShareId = nil
            isSharing = false
            isPublishingFirstLocation = false
            didCreateServerShare = false
        }
        errorMessage = nil
        loadedAccountUserId = userId
        friendFetchGeneration += 1
        friendLocations.removeAll()
        availableFriends.removeAll()
        locationEventChanges.removeAll()
        stoppedShareIdsByUser.removeAll()
        didLoadShareState = false
        viewerIDsForPendingShare.removeAll()
        stopTokenForPendingShare = nil
        pendingStopUserId = userId
        stopRequestPending = UserDefaults.standard.bool(forKey: pendingStopKeyPrefix + userId)
        isStopPending = stopRequestPending
    }

    private func clearAccountState(for userId: String?) {
        guard let userId, loadedAccountUserId == userId else { return }
        friendFetchGeneration += 1
        friendLocations.removeAll()
        availableFriends.removeAll()
        locationEventChanges.removeAll()
        stoppedShareIdsByUser.removeAll()
        didLoadShareState = false
        viewerIDsForPendingShare.removeAll()
        stopTokenForPendingShare = nil
        if activeShareUserId == userId {
            activeShareUserId = nil
            activeShareId = nil
            isSharing = false
            isPublishingFirstLocation = false
            didCreateServerShare = false
            locationManager.stopSharing()
        }
        errorMessage = nil
        loadedAccountUserId = nil
    }
}

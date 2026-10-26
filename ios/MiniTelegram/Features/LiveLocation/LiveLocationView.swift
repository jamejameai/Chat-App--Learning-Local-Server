import CoreLocation
import MapKit
import SwiftUI
import UIKit

public struct LiveLocationView: View {
    @StateObject private var viewModel = LiveLocationViewModel.shared
    @ObservedObject private var locationManager = LiveLocationManager.shared
    @ObservedObject private var presence = PresenceManager.shared
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCentered = false
    @State private var showingBackgroundDisclosure = false
    @State private var showingAudiencePicker = false
    @State private var pulseAnimation = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition) {
                // Native Apple Maps pulsing blue user location dot
                UserAnnotation()

                // Custom dedicated "You (Live)" marker when actively sharing
                if viewModel.isSharing, let myLoc = locationManager.lastLocation {
                    Annotation(
                        "You",
                        coordinate: myLoc.coordinate,
                        anchor: .bottom
                    ) {
                        myLiveSharingMarker(myLoc)
                    }
                }

                // Friends sharing their live location
                ForEach(viewModel.friendLocations) { location in
                    Annotation(
                        location.display_name ?? location.username ?? "Friend",
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.latitude,
                            longitude: location.longitude
                        ),
                        anchor: .bottom
                    ) {
                        friendMarker(location)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .top)

            // Header gradient overlay
            header

            // Floating control buttons (Recenter on Me, Fit All, Refresh)
            floatingControls
                .padding(.top, 120)
                .padding(.trailing, 18)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sharingPanel
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            locationManager.startViewingLocation()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
            centerInitialLocationIfNeeded()
        }
        .onDisappear {
            locationManager.stopViewingLocation()
        }
        .task {
            await viewModel.loadFriendLocations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveLocationsChanged)) { _ in
            Task { await viewModel.loadFriendLocations() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .friendsChanged)) { _ in
            Task { await viewModel.loadFriendLocations() }
        }
        .onChange(of: viewModel.friendLocations) { _, _ in
            centerInitialLocationIfNeeded()
        }
        .onChange(of: locationManager.lastLocation) { _, _ in
            centerInitialLocationIfNeeded()
        }
        .sheet(isPresented: $showingAudiencePicker) {
            LiveLocationAudiencePicker(friends: viewModel.availableFriends) { viewerIDs in
                viewModel.startSharing(with: viewerIDs)
            }
        }
        .confirmationDialog(
            "Choose who can see your live location",
            isPresented: $showingBackgroundDisclosure,
            titleVisibility: .visible
        ) {
            Button("Choose friends") {
                Task {
                    let friends = await viewModel.loadShareAudience()
                    if !friends.isEmpty {
                        showingAudiencePicker = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only friends you select can see your current position and direction. New friends are not added automatically. You can stop sharing at any time.")
        }
        .alert("Location", isPresented: Binding(
            get: { viewModel.errorMessage != nil || locationManager.permissionError != nil },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    locationManager.clearPermissionError()
                }
            }
        )) {
            if viewModel.errorMessage?.contains("Tap to retry") == true {
                Button("Retry stop") {
                    Task { await viewModel.retryStopSharing() }
                }
            }
            if locationManager.permissionError != nil,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settingsURL)
            }
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? locationManager.permissionError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Live")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(viewModel.friendLocations.isEmpty
                     ? (viewModel.isSharing ? "Sharing live with \(viewModel.viewerCount) friend\(viewModel.viewerCount == 1 ? "" : "s")" : "A quiet way to stay close")
                     : "\(viewModel.friendLocations.count) friend\(viewModel.friendLocations.count == 1 ? "" : "s") sharing")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 64)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [AppColors.background.opacity(0.98), AppColors.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            // Recenter on My Location
            Button {
                centerOnMyLocation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(locationManager.lastLocation != nil ? AppColors.accent : AppColors.textTertiary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .accessibilityLabel("Center on my location")

            // Fit All Participants
            Button {
                fitAllParticipants()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .accessibilityLabel("Fit all participants on map")

            // Refresh Friends Locations
            Button {
                Task { await viewModel.loadFriendLocations() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .accessibilityLabel("Refresh friends' live locations")
        }
    }

    private var sharingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isSharing && locationManager.isUpdating
                          ? AppColors.statusOnline
                          : AppColors.textTertiary)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isSharing && locationManager.isUpdating &&
                         !viewModel.isPublishingFirstLocation
                         ? "Your location is live"
                         : "Your location is private")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(sharingStatus)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Button {
                    if viewModel.isStopPending {
                        Task { await viewModel.retryStopSharing() }
                    } else if viewModel.isSharing {
                        Task { await viewModel.stopSharing() }
                    } else {
                        showingBackgroundDisclosure = true
                    }
                } label: {
                    Text(viewModel.isStopPending
                         ? "Retry stop"
                         : viewModel.isSharing ? "Stop" : "Share live")
                        .font(AppTypography.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.isSharing || viewModel.isStopPending
                                         ? AppColors.accent
                                         : .white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(
                            viewModel.isSharing || viewModel.isStopPending
                                ? AppColors.accentLight
                                : AppColors.textPrimary,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            // Cards Carousel: "You (Live)" card first if sharing/locating, followed by friends
            if viewModel.isSharing || !viewModel.friendLocations.isEmpty || locationManager.lastLocation != nil {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // My location card
                        if let myLoc = locationManager.lastLocation {
                            mySummaryCard(myLoc)
                        }

                        // Friends cards
                        ForEach(viewModel.friendLocations) { location in
                            friendSummary(location)
                        }
                    }
                }
            } else if !viewModel.isLoading {
                Text("When friends share their location with you, they'll appear here.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var sharingStatus: String {
        if viewModel.isLoadingAudience {
            return "Loading friends to choose from…"
        }
        if viewModel.isStopPending {
            return "Stop pending · retry to confirm"
        }
        if viewModel.isSharing && !locationManager.isUpdating {
            return locationManager.permissionError == nil
                ? "Requesting background location access…"
                : "Location permission is needed to go live"
        }
        if viewModel.isPublishingFirstLocation {
            return "Waiting for a precise location…"
        }
        if viewModel.isSharing {
            let count = viewModel.viewerCount
            return "Visible to \(count) friend\(count == 1 ? "" : "s") · tap Stop any time"
        }

        return "Only you can see your location on this map"
    }

    // MARK: - Markers

    private func myLiveSharingMarker(_ location: CLLocation) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Pulsing radar ring
                Circle()
                    .stroke(AppColors.accent.opacity(pulseAnimation ? 0.0 : 0.65), lineWidth: 2.5)
                    .scaleEffect(pulseAnimation ? 1.6 : 1.0)
                    .frame(width: 52, height: 52)

                // White circle container with accent outline
                Circle()
                    .fill(.white)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Circle().strokeBorder(AppColors.accent, lineWidth: 3)
                    }
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    .shadow(color: AppColors.accent.opacity(0.35), radius: 8, y: 3)

                // Live green badge
                Circle()
                    .fill(AppColors.statusOnline)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 16, y: 16)
            }

            // Heading direction arrow
            if location.course >= 0 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .rotationEffect(.degrees(location.course))
                    .accessibilityHidden(true)
            }

            // Name & Viewer Count Pill
            HStack(spacing: 4) {
                Text("You (Live)")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                if viewModel.viewerCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 8))
                        Text("\(viewModel.viewerCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your live location, shared with \(viewModel.viewerCount) friends")
    }

    private func friendMarker(_ location: LiveLocationDTO) -> some View {
        let isFriendOnline = presence.isOnline(location.user_id)

        return VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(.white)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .overlay {
                        Circle().strokeBorder(.white, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                // Online/Live indicator badge
                Circle()
                    .fill(location.isFresh || isFriendOnline ? AppColors.statusOnline : AppColors.statusWarning)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            }

            if let heading = location.heading {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .rotationEffect(.degrees(heading))
                    .accessibilityHidden(true)
            }

            Text(location.display_name ?? location.username ?? "Friend")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(location.display_name ?? location.username ?? "Friend"), \(location.isFresh ? "live location" : "last known location")")
    }

    // MARK: - Carousel Cards

    private func mySummaryCard(_ location: CLLocation) -> some View {
        Button {
            centerOnMyLocation()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(viewModel.isSharing ? AppColors.accentLight : AppColors.surface)
                        .frame(width: 32, height: 32)
                    Image(systemName: viewModel.isSharing ? "antenna.radiowaves.left.and.right" : "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.isSharing ? AppColors.accent : AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("You")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        if viewModel.isSharing {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppColors.statusOnline)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppColors.statusOnline.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(viewModel.isSharing ? "\(viewModel.viewerCount) viewers · ±\(Int(location.horizontalAccuracy))m" : "Private · ±\(Int(location.horizontalAccuracy))m")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(viewModel.isSharing ? AppColors.accentLight.opacity(0.5) : AppColors.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(viewModel.isSharing ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func friendSummary(_ location: LiveLocationDTO) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: location.latitude,
                            longitude: location.longitude
                        ),
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppColors.surface)
                        .frame(width: 32, height: 32)
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(location.display_name ?? location.username ?? "Friend")
                        .font(AppTypography.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(relativeUpdateTime(location.updated_at))
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Camera Controls

    private func centerOnMyLocation() {
        if let myLoc = locationManager.lastLocation {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: myLoc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    )
                )
            }
        } else {
            locationManager.startViewingLocation()
        }
    }

    private func fitAllParticipants() {
        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0
        var count = 0

        if let myLoc = locationManager.lastLocation {
            let lat = myLoc.coordinate.latitude
            let lon = myLoc.coordinate.longitude
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
            count += 1
        }

        for friend in viewModel.friendLocations {
            minLat = min(minLat, friend.latitude)
            maxLat = max(maxLat, friend.latitude)
            minLon = min(minLon, friend.longitude)
            maxLon = max(maxLon, friend.longitude)
            count += 1
        }

        guard count > 0 else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.6, 0.02)
        let lonDelta = max((maxLon - minLon) * 1.6, 0.02)

        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
                )
            )
        }
    }

    private func centerInitialLocationIfNeeded() {
        guard !hasCentered else { return }
        if let firstFriend = viewModel.friendLocations.first {
            hasCentered = true
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: firstFriend.latitude, longitude: firstFriend.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
        } else if let myLoc = locationManager.lastLocation {
            hasCentered = true
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: myLoc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

    private func relativeUpdateTime(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: timestamp)
            ?? ISO8601DateFormatter().date(from: timestamp)
        guard let date else { return "just now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct LiveLocationAudiencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let friends: [FriendDTO]
    let onStartSharing: (Set<String>) -> Void
    @State private var selectedViewerIDs = Set<String>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your location is visible only to the friends selected here. New friends will not be added automatically.")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Friends") {
                    ForEach(friends) { friend in
                        Button {
                            toggle(friend.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(friend.display_name)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("@\(friend.username)")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: selectedViewerIDs.contains(friend.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(selectedViewerIDs.contains(friend.id)
                                                     ? AppColors.accent
                                                     : AppColors.textTertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(friend.display_name)
                        .accessibilityValue(selectedViewerIDs.contains(friend.id)
                                            ? "Selected"
                                            : "Not selected")
                        .accessibilityHint("Toggles whether this friend can see your live location")
                    }
                }
            }
            .navigationTitle("Share with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share live") {
                        onStartSharing(selectedViewerIDs)
                        dismiss()
                    }
                    .disabled(selectedViewerIDs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ friendID: String) {
        if selectedViewerIDs.contains(friendID) {
            selectedViewerIDs.remove(friendID)
        } else {
            selectedViewerIDs.insert(friendID)
        }
    }
}

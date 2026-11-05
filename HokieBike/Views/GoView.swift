import SwiftUI
import MapKit
import CoreLocation

struct GoView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var rideTrackingManager: RideTrackingManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationManager = LocationPermissionManager()

    @State private var whereToText = ""
    @State private var placeResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var showArrivalBanner = false
    @State private var showRideSummary = false
    @State private var hasPresentedCurrentSummary = false
    @State private var showNavigationModePicker = false
    @State private var showInAppNavigation = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.2296, longitude: -80.4244),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    )

    var body: some View {
        ZStack {
            fullScreenMap
            topReadabilityOverlay

            VStack(spacing: 0) {
                HStack {
                    Button {
                        selectedTab = .activity
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }

                    greetingChip
                        .padding(.horizontal, 10)

                    Spacer()

                    Button {
                        selectedTab = .account
                    } label: {
                        accountButtonAvatar
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Where to today?", text: $whereToText)
                        .textFieldStyle(.roundedBorder)

                    routeControls
                }
                .padding(12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
                .padding(.top, 8)

                if shouldShowSearchOverlay {
                    searchResultsOverlay
                        .padding(.horizontal)
                        .padding(.top, 6)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        selectedTab = .go
                    } label: {
                        Label("Go", systemImage: "bicycle")
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTab == .go ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == .go ? Color("VTMaroon") : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = .explore
                    } label: {
                        Label("Explore", systemImage: "map")
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTab == .explore ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedTab == .explore ? Color("VTMaroon") : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.horizontal)
                .padding(.bottom, 18)
            }

            if showArrivalBanner {
                VStack {
                    Label("Arrived at destination", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color("VTMaroon"))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.top, 80)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            locationManager.requestPermissionIfNeeded()
            rideTrackingManager.requestPermissionIfNeeded()
        }
        .onReceive(locationManager.$currentLocation) { coordinate in
            guard let coordinate else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        }
        .onChange(of: whereToText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await searchNearbyPlaces(query: newValue)
            }
        }
        .onChange(of: rideTrackingManager.arrivalEventID) { _, newValue in
            guard newValue != nil else { return }

            if viewModel.activeRental != nil {
                endActiveRentalFromCurrentCoordinate()
            }

            withAnimation {
                showArrivalBanner = true
            }

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation {
                        showArrivalBanner = false
                    }
                }
            }
        }
        .onChange(of: rideTrackingManager.latestSummary?.id) { _, _ in
            guard rideTrackingManager.latestSummary != nil else { return }
            hasPresentedCurrentSummary = false
            showRideSummary = true
            hasPresentedCurrentSummary = true
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            guard rideTrackingManager.latestSummary != nil else { return }
            guard !hasPresentedCurrentSummary else { return }
            showRideSummary = true
            hasPresentedCurrentSummary = true
        }
        .sheet(isPresented: $showRideSummary) {
            if let summary = rideTrackingManager.latestSummary {
                RideSummarySheetView(summary: summary) {
                    shareRideSummaryToCommunity(summary)
                    showRideSummary = false
                    selectedTab = .activity
                }
            }
        }
        .confirmationDialog("Start navigation", isPresented: $showNavigationModePicker, titleVisibility: .visible) {
            Button("Navigate in HokieBike") {
                beginInAppNavigation()
            }
            Button("Open in Apple Maps") {
                openInAppleMaps()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how you want turn-by-turn guidance.")
        }
        .fullScreenCover(isPresented: $showInAppNavigation) {
            InAppNavigationView(
                onOpenAppleMaps: {
                    openInAppleMaps()
                },
                onEndRide: {
                    rideTrackingManager.stopTracking()
                    endActiveRentalFromCurrentCoordinate()
                },
                onClose: {
                    showInAppNavigation = false
                }
            )
            .environmentObject(rideTrackingManager)
        }
    }

    private var topReadabilityOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.black.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var fullScreenMap: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(mapAvailableBikes) { bike in
                    if let coordinate = bike.coordinate {
                        Marker(bike.name, coordinate: coordinate)
                            .tint(Color("VTMaroon"))
                    }
                }

                if mapAvailableBikes.isEmpty {
                    Marker("DemoBike (Simulated)", coordinate: simulatedBikeCoordinate)
                        .tint(Color("VTOrange"))
                }

                if let route = rideTrackingManager.plannedRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color("VTOrange"), lineWidth: 4)
                }

                if trackedPathPolyline.pointCount > 1 {
                    MapPolyline(trackedPathPolyline)
                        .stroke(Color("VTMaroon"), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                UserAnnotation()
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    availabilityChip
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 130)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        locationManager.recenterRequest()
                    } label: {
                        Image(systemName: "location.fill")
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 130)
            }
        }
    }

    private var shouldShowSearchOverlay: Bool {
        !placeResults.isEmpty && whereToText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var searchResultsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(placeResults.prefix(8).enumerated()), id: \.offset) { _, item in
                Button {
                    centerOnPlace(item)
                    placeResults = []
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Color("VTMaroon"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Location")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(item.placemark.title ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .buttonStyle(.plain)

                Divider()
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private var greetingChip: some View {
        HStack(spacing: 6) {
            greetingAvatar
            Text("\(greetingText), \(firstName)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color("VTMaroon"))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var greetingAvatar: some View {
        if let urlString = viewModel.currentUser.profilePhotoURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var accountButtonAvatar: some View {
        if let urlString = viewModel.currentUser.profilePhotoURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .padding(3)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.black.opacity(0.35))
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.headline)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.35))
                .clipShape(Circle())
        }
    }

    private var availabilityChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text(availableBikeStatusText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var availableBikeStatusText: String {
        let count = mapAvailableBikes.count
        if count == 0 { return "No bikes available" }
        if count == 1 {
            return "1 bike available: \(mapAvailableBikes[0].name)"
        }
        return "\(count) bikes available"
    }

    private var firstName: String {
        let trimmed = viewModel.currentUser.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? "Hokie"
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good evening"
        }
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let destinationName = rideTrackingManager.destinationName {
                HStack {
                    Text("Destination: \(destinationName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        rideTrackingManager.clearRoute()
                        whereToText = ""
                        placeResults = []
                    }
                    .font(.caption)
                }
            } else {
                Text("Destination optional. Start Ride to track your route anywhere.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let nextInstruction = rideTrackingManager.nextInstruction {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next", systemImage: "arrow.turn.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(nextInstruction)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        if let remainingDistanceMeters = rideTrackingManager.remainingDistanceMeters {
                            Text(String(format: "%.1f km remaining", remainingDistanceMeters / 1000.0))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let eta = rideTrackingManager.remainingETASeconds {
                            Text("ETA: \(eta.formattedDuration)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
            }

            if let statusMessage = rideTrackingManager.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    startRideTapped()
                } label: {
                    Label("Start Ride", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("VTMaroon"))
                .disabled(rideTrackingManager.isTracking)

                Button {
                    rideTrackingManager.stopTracking()
                } label: {
                    Label("Stop Tracking", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!rideTrackingManager.isTracking)
            }

            Button {
                openInAppleMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(rideTrackingManager.destinationCoordinate == nil)
        }
    }

    private func startRideTapped() {
        if rideTrackingManager.destinationCoordinate != nil {
            showNavigationModePicker = true
        } else {
            beginInAppNavigation()
        }
    }

    private var mapSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                ForEach(filteredNearbyBikes) { bike in
                    if let coordinate = bike.coordinate {
                        Marker(bike.name, coordinate: coordinate)
                            .tint(Color("VTMaroon"))
                    }
                }

                if let route = rideTrackingManager.plannedRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color("VTOrange"), lineWidth: 4)
                }

                if trackedPathPolyline.pointCount > 1 {
                    MapPolyline(trackedPathPolyline)
                        .stroke(Color("VTMaroon"), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                UserAnnotation()
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                locationManager.recenterRequest()
            } label: {
                Image(systemName: "location.fill")
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(12)
        }
    }

    private var trackedPathPolyline: MKPolyline {
        MKPolyline(coordinates: rideTrackingManager.trackedPath, count: rideTrackingManager.trackedPath.count)
    }

    private var mapAvailableBikes: [Bike] {
        viewModel.bikes.filter { $0.isAvailable }
    }

    private var simulatedBikeCoordinate: CLLocationCoordinate2D {
        // Keep fallback anchored to campus so the demo pin does not drift with user location.
        return CLLocationCoordinate2D(latitude: 37.2291, longitude: -80.4235)
    }

    private var filteredNearbyBikes: [Bike] {
        let base: [Bike]
        if let userCoordinate = locationManager.currentLocation {
            base = viewModel.nearbyBikes(around: userCoordinate, maxDistanceMeters: 2500)
        } else {
            base = viewModel.bikes
        }

        guard !whereToText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }

        return base.filter {
            $0.name.localizedCaseInsensitiveContains(whereToText) ||
            $0.location.localizedCaseInsensitiveContains(whereToText)
        }
    }

    private var filteredNearbyJourneys: [Journey] {
        let base: [Journey]
        if let userCoordinate = locationManager.currentLocation {
            let userPoint = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            base = viewModel.journeys.filter { journey in
                let start = CLLocation(latitude: journey.startCoordinate.latitude, longitude: journey.startCoordinate.longitude)
                return userPoint.distance(from: start) <= 5000
            }
        } else {
            base = viewModel.journeys
        }

        guard !whereToText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }

        return base.filter {
            $0.title.localizedCaseInsensitiveContains(whereToText) ||
            $0.destinationName.localizedCaseInsensitiveContains(whereToText) ||
            $0.startName.localizedCaseInsensitiveContains(whereToText)
        }
    }

    private func searchNearbyPlaces(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            await MainActor.run { placeResults = [] }
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed

        if let current = locationManager.currentLocation {
            request.region = MKCoordinateRegion(
                center: current,
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            await MainActor.run {
                placeResults = response.mapItems
            }
        } catch {
            await MainActor.run {
                placeResults = []
            }
        }
    }

    private func centerOnPlace(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }

        Task {
            await rideTrackingManager.setDestination(
                name: item.name ?? "Selected Destination",
                coordinate: coordinate,
                bikeFallback: viewModel.bikes.first?.coordinate
            )
        }
    }

    private func openInAppleMaps() {
        guard let destinationCoordinate = rideTrackingManager.destinationCoordinate else { return }

        ensureActiveRentalForNavigation()

        if !rideTrackingManager.isTracking {
            rideTrackingManager.startTracking()
        }

        let destinationName = rideTrackingManager.destinationName ?? "Destination"
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        destinationItem.name = destinationName

        var launchOptions: [String: Any] = [
            MKLaunchOptionsShowsTrafficKey: false
        ]

        if #available(iOS 14.0, *) {
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeCycling
        } else {
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeWalking
        }

        if let current = locationManager.currentLocation {
            let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: current))
            sourceItem.name = "Current Location"
            MKMapItem.openMaps(with: [sourceItem, destinationItem], launchOptions: launchOptions)
        } else {
            destinationItem.openInMaps(launchOptions: launchOptions)
        }
    }

    private func beginInAppNavigation() {
        ensureActiveRentalForNavigation()
        if !rideTrackingManager.isTracking {
            rideTrackingManager.startTracking()
        }
        showInAppNavigation = true
    }

    private func ensureActiveRentalForNavigation() {
        guard viewModel.activeRental == nil else { return }
        guard let bike = viewModel.bikes.first(where: { $0.isAvailable }) else { return }

        let coordinate = locationManager.currentLocation
        let startLocation = coordinate.map { point in
            String(format: "%.5f, %.5f", point.latitude, point.longitude)
        }

        viewModel.startRental(
            bike: bike,
            startLocation: startLocation,
            startCoordinate: coordinate
        )
    }

    private func endActiveRentalFromCurrentCoordinate() {
        let coordinate = rideTrackingManager.currentCoordinate
        let endLocation = coordinate.map { point in
            String(format: "%.5f, %.5f", point.latitude, point.longitude)
        }
        viewModel.endRental(
            endLocation: endLocation,
            endCoordinate: coordinate,
            destinationName: rideTrackingManager.destinationName,
            trackedPath: rideTrackingManager.trackedPath
        )
    }

    private func shareRideSummaryToCommunity(_ summary: RideSummary) {
        let kilometers = summary.distanceMeters / 1000.0
        let miles = kilometers * 0.621371
        let mph = summary.averageSpeedKph * 0.621371

        let title: String
        if let destination = summary.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            title = "Ride to \(destination)"
        } else {
            title = "Free Ride"
        }

        var lines: [String] = [
            "Just wrapped up a HokieBike ride.",
            String(format: "Distance: %.2f mi (%.2f km)", miles, kilometers),
            "Duration: \(formattedRideDuration(summary.durationSeconds))",
            String(format: "Average speed: %.1f mph (%.1f kph)", mph, summary.averageSpeedKph)
        ]

        if summary.didArrive, let destination = summary.destinationName, !destination.isEmpty {
            lines.append("Arrived at \(destination).")
        }

        viewModel.createPost(journeyTitle: title, bodyText: lines.joined(separator: "\n"), imageData: nil)
    }

    private func formattedRideDuration(_ value: TimeInterval) -> String {
        let total = Int(value)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        GoView(selectedTab: .constant(.go))
            .environmentObject(AppViewModel())
            .environmentObject(RideTrackingManager())
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: self) ?? "N/A"
    }
}

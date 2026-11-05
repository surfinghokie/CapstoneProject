import SwiftUI
import MapKit

struct ExploreView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var locationManager = LocationPermissionManager()

    @State private var mapQuery = ""
    @State private var routeSearchText = ""
    @State private var placeResults: [MKMapItem] = []
    @State private var selectedPlaceForTrip: MKMapItem?
    @State private var showSaveTripSheet = false

    @State private var selectedJourney: Journey?
    @State private var selectedJourneyRoute: MKRoute?
    @State private var routePreviewMessage: String?
    @State private var pendingJourneyDelete: Journey?

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.2296, longitude: -80.4244),
            span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
        )
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                mapSearchHeader
                mapSection
                nearbyBikesSection
                journeysSection
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .navigationTitle("Explore")
        .task {
            locationManager.requestPermissionIfNeeded()
            if selectedJourney == nil, let first = filteredJourneys.first {
                selectJourney(first)
            }
        }
        .onReceive(locationManager.$currentLocation) { newValue in
            guard let coordinate = newValue else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        }
        .sheet(isPresented: $showSaveTripSheet) {
            saveTripSheet
        }
        .alert(
            "Delete Trip?",
            isPresented: Binding(
                get: { pendingJourneyDelete != nil },
                set: { if !$0 { pendingJourneyDelete = nil } }
            ),
            presenting: pendingJourneyDelete
        ) { journey in
            Button("Delete", role: .destructive) {
                if selectedJourney?.id == journey.id {
                    selectedJourney = nil
                    selectedJourneyRoute = nil
                    routePreviewMessage = nil
                }
                viewModel.deleteJourney(journeyID: journey.id)
                pendingJourneyDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingJourneyDelete = nil
            }
        } message: { journey in
            Text("This will permanently remove \"\(journey.title)\".")
        }
    }

    private var mapSearchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search places (Map search)", text: $mapQuery)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await runPlaceSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .padding(8)
                        .background(Color("VTMaroon"))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }

            TextField("Filter bikes and routes", text: $routeSearchText)
                .textFieldStyle(.roundedBorder)

            Text(locationStatusText)
                .font(.caption)
                .foregroundColor(.secondary)

            if let selectedJourney {
                Text("Previewing: \(selectedJourney.title)")
                    .font(.caption)
                    .foregroundColor(Color("VTMaroon"))
            }

            if let routePreviewMessage {
                Text(routePreviewMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !placeResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(placeResults.prefix(6).enumerated()), id: \.offset) { _, item in
                            Button {
                                centerOnSearchResult(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Location")
                                        .font(.caption.bold())
                                    Text(mapItemSubtitle(item))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let selectedPlaceForTrip {
                Button {
                    showSaveTripSheet = true
                } label: {
                    Label("Save \(selectedPlaceForTrip.name ?? "Selected Place") as trip", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color("VTMaroon"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mapSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                ForEach(filteredBikes) { bike in
                    if let coordinate = bike.coordinate {
                        Annotation(bike.name, coordinate: coordinate) {
                            VStack(spacing: 2) {
                                Image(systemName: "bicycle.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(bike.isAvailable ? Color("VTMaroon") : .gray)
                                Text(bike.priceString)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)

                                if let lastSeenAt = bike.lastSeenAt {
                                    Text("Updated \(shortRelativeText(for: lastSeenAt))")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }

                ForEach(filteredJourneys) { journey in
                    Marker(journey.title, coordinate: journey.destinationCoordinate)
                        .tint(Color("VTOrange"))
                }

                if let selectedJourneyRoute {
                    MapPolyline(selectedJourneyRoute.polyline)
                        .stroke(Color("VTMaroon"), lineWidth: 5)
                }

                UserAnnotation()
            }
            .frame(height: 320)
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

    private var saveTripSheet: some View {
        NavigationStack {
            SaveTripView(destinationName: selectedPlaceForTrip?.name ?? "") { title, notes, difficulty, category in
                guard let destination = mapItemCoordinate(selectedPlaceForTrip) else { return }
                let start = locationManager.currentLocation ?? viewModel.bikes.first?.coordinate ?? destination

                viewModel.createJourney(
                    title: title,
                    subtitle: "Community Route",
                    description: notes,
                    startName: "Current Location",
                    destinationName: selectedPlaceForTrip?.name ?? "Saved Destination",
                    startCoordinate: start,
                    destinationCoordinate: destination,
                    difficulty: difficulty,
                    category: category
                )

                showSaveTripSheet = false
            }
        }
    }

    private var nearbyBikesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearby Bikes")
                .font(.headline)

            if filteredBikes.isEmpty {
                Text("No bikes match this filter yet.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(filteredBikes.prefix(4)) { bike in
                    NavigationLink(destination: BikeDetailView(bike: bike).environmentObject(viewModel)) {
                        BikeCardView(bike: bike)
                    }
                }
            }
        }
    }

    private var journeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More Suggested Trips")
                .font(.headline)

            if filteredJourneys.isEmpty {
                Text("Suggested trips will appear here once routes are added.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(filteredJourneys) { journey in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    selectJourney(journey)
                                } label: {
                                    JourneyCardView(journey: journey, isSaved: viewModel.isJourneySaved(journey))
                                        .frame(width: 260)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if viewModel.canDeleteJourney(journey) {
                                        Button(role: .destructive) {
                                            pendingJourneyDelete = journey
                                        } label: {
                                            Label("Delete Trip", systemImage: "trash")
                                        }
                                    }
                                }

                                if viewModel.canDeleteJourney(journey) {
                                    Button(role: .destructive) {
                                        pendingJourneyDelete = journey
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Color.black.opacity(0.55))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(8)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let selectedJourney {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selectedJourney.startName) → \(selectedJourney.destinationName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let route = selectedJourneyRoute {
                        HStack(spacing: 8) {
                            Label(String(format: "%.1f km", route.distance / 1000.0), systemImage: "ruler")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.gray.opacity(0.14))
                                .cornerRadius(8)

                            Label(route.expectedTravelTime.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.gray.opacity(0.14))
                                .cornerRadius(8)
                        }
                    }

                    NavigationLink(destination: JourneyDetailView(journey: selectedJourney).environmentObject(viewModel)) {
                        Label("View Journey", systemImage: "map")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color("VTMaroon"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }
    }

    private var filteredBikes: [Bike] {
        viewModel.bikes.filter { bike in
            routeSearchText.isEmpty || bike.name.localizedCaseInsensitiveContains(routeSearchText) || bike.location.localizedCaseInsensitiveContains(routeSearchText)
        }
    }

    private var filteredJourneys: [Journey] {
        let scoped = viewModel.filteredJourneys.filter { journey in
            routeSearchText.isEmpty || journey.title.localizedCaseInsensitiveContains(routeSearchText) || journey.destinationName.localizedCaseInsensitiveContains(routeSearchText)
        }

        return scoped.sorted { lhs, rhs in
            let lhsIsCustom = viewModel.canDeleteJourney(lhs)
            let rhsIsCustom = viewModel.canDeleteJourney(rhs)

            if lhsIsCustom != rhsIsCustom {
                // Suggested (seeded/public) routes first, then user-created routes.
                return rhsIsCustom
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Location enabled"
        case .denied, .restricted:
            return "Location denied. Search and manual map browsing are still available."
        case .notDetermined:
            return "Allow location to center on nearby bikes."
        @unknown default:
            return "Location status unavailable"
        }
    }

    private func selectJourney(_ journey: Journey) {
        selectedJourney = journey
        routePreviewMessage = "Loading route preview..."

        Task {
            await loadPreviewRoute(for: journey)
        }
    }

    private func loadPreviewRoute(for journey: Journey) async {
        let request = MKDirections.Request()
        if #available(iOS 26.0, *) {
            let start = previewStartCoordinate(for: journey)
            let destination = journey.destinationCoordinate
            request.source = MKMapItem(
                location: CLLocation(latitude: start.latitude, longitude: start.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
                address: nil
            )
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: previewStartCoordinate(for: journey)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: journey.destinationCoordinate))
        }
        request.transportType = .any

        do {
            let response = try await MKDirections(request: request).calculate()
            let candidate = response.routes.first

            await MainActor.run {
                selectedJourneyRoute = candidate
                routePreviewMessage = candidate == nil ? "Route preview not available for this journey." : nil
                if let candidate {
                    cameraPosition = .rect(candidate.polyline.boundingMapRect)
                }
            }
        } catch {
            await MainActor.run {
                selectedJourneyRoute = nil
                routePreviewMessage = "Route preview unavailable right now."
            }
        }
    }

    private func previewStartCoordinate(for journey: Journey) -> CLLocationCoordinate2D {
        locationManager.currentLocation ?? viewModel.bikes.first?.coordinate ?? journey.startCoordinate
    }

    private func runPlaceSearch() async {
        let query = mapQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await MainActor.run { placeResults = [] }
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let current = locationManager.currentLocation {
            request.region = MKCoordinateRegion(
                center: current,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
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
                routePreviewMessage = "Place search unavailable right now."
            }
        }
    }

    private func centerOnSearchResult(_ item: MKMapItem) {
        guard let coordinate = mapItemCoordinate(item) else { return }
        selectedPlaceForTrip = item
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

    private func mapItemCoordinate(_ item: MKMapItem?) -> CLLocationCoordinate2D? {
        guard let item else { return nil }
        return item.location.coordinate
    }

    private func mapItemSubtitle(_ item: MKMapItem) -> String {
        if let coordinate = mapItemCoordinate(item) {
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        return ""
    }

    private func shortRelativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct SaveTripView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var difficulty = "Easy"
    @State private var category: JourneyCategory = .community

    let destinationName: String
    let onSave: (_ title: String, _ notes: String, _ difficulty: String, _ category: JourneyCategory) -> Void

    var body: some View {
        Form {
            Section("Trip Info") {
                TextField("Trip title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...5)

                Picker("Difficulty", selection: $difficulty) {
                    Text("Easy").tag("Easy")
                    Text("Moderate").tag("Moderate")
                    Text("Hard").tag("Hard")
                }

                Picker("Category", selection: $category) {
                    ForEach(JourneyCategory.allCases.filter { $0 != .all }) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            Section("Destination") {
                Text(destinationName.isEmpty ? "Selected destination" : destinationName)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Save Trip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved Ride" : title,
                        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Community shared route." : notes,
                        difficulty,
                        category
                    )
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExploreView()
            .environmentObject(AppViewModel())
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

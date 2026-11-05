import SwiftUI
import MapKit

struct JourneyDetailView: View {
    let journey: Journey
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var rideTrackingManager: RideTrackingManager

    @State private var route: MKRoute?
    @State private var routeError: String?
    @State private var cameraPosition: MapCameraPosition

    init(journey: Journey) {
        self.journey = journey
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (journey.startLatitude + journey.destinationLatitude) / 2,
                longitude: (journey.startLongitude + journey.destinationLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)
        )
        _cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topCard
                routeMap
                metadata
                actionButtons
            }
            .padding()
        }
        .navigationTitle(journey.title)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await loadRoute()
        }
    }

    private var topCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("VTMaroon").opacity(0.14))
                .frame(height: 200)

            if journey.usesAssetImage {
                Image(journey.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            LinearGradient(
                colors: [Color.black.opacity(journey.usesAssetImage ? 0.45 : 0.0), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(journey.subtitle)
                    .font(.caption)
                    .foregroundColor(journey.usesAssetImage ? .white.opacity(0.9) : .secondary)
                Text(journey.title)
                    .font(.title2.bold())
                    .foregroundColor(journey.usesAssetImage ? .white : .primary)
                Text(journey.description)
                    .font(.subheadline)
                    .foregroundColor(journey.usesAssetImage ? .white.opacity(0.9) : .secondary)
                    .lineLimit(3)
            }
            .padding()
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition) {
            Marker("Start", coordinate: resolvedStartCoordinate)
                .tint(.green)
            Marker("Destination", coordinate: journey.destinationCoordinate)
                .tint(Color("VTOrange"))

            if let route {
                MapPolyline(route.polyline)
                    .stroke(Color("VTMaroon"), lineWidth: 5)
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Journey Details")
                .font(.headline)

            Text("Start: \(resolvedStartName)")
            Text("Destination: \(journey.destinationName)")
            Text("Difficulty: \(journey.difficulty)")

            if let route {
                Text(String(format: "Distance: %.1f km", route.distance / 1000.0))
                Text("Estimated time: \(route.expectedTravelTime.formattedDuration)")
                    .foregroundColor(.secondary)
            } else if let routeError {
                Text("Route info unavailable: \(routeError)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Calculating route...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Notable spots: \(journey.subtitle), \(journey.destinationName)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.toggleJourneySaved(journey)
            } label: {
                Label(viewModel.isJourneySaved(journey) ? "Saved" : "Save Journey", systemImage: viewModel.isJourneySaved(journey) ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("VTMaroon"))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            NavigationLink {
                BrowseBikesView()
                    .environmentObject(viewModel)
            } label: {
                Label("Find Nearby Bike", systemImage: "bicycle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("VTOrange"))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button {
                Task {
                    await rideTrackingManager.setDestination(
                        name: journey.destinationName,
                        coordinate: journey.destinationCoordinate,
                        bikeFallback: viewModel.bikes.first?.coordinate
                    )
                    if viewModel.activeRental != nil {
                        rideTrackingManager.startTracking()
                    }
                }
            } label: {
                Label("Start Journey", systemImage: "figure.outdoor.cycle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
        }
    }

    private var resolvedStartName: String {
        if let current = rideTrackingManager.currentCoordinate {
            return String(format: "Current Location (%.4f, %.4f)", current.latitude, current.longitude)
        }
        if let bikeCoordinate = viewModel.bikes.first?.coordinate {
            return String(format: "Bike Location (%.4f, %.4f)", bikeCoordinate.latitude, bikeCoordinate.longitude)
        }
        return journey.startName
    }

    private func loadRoute() async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: resolvedStartCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: journey.destinationCoordinate))
        request.transportType = .any

        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
        } catch {
            routeError = "MapKit could not return a route right now."
        }
    }

    private var resolvedStartCoordinate: CLLocationCoordinate2D {
        rideTrackingManager.currentCoordinate ?? viewModel.bikes.first?.coordinate ?? journey.startCoordinate
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

#Preview {
    NavigationStack {
        JourneyDetailView(
            journey: Journey(
                title: "Duck Pond Cruise",
                subtitle: "Campus",
                description: "A relaxing route.",
                startName: "Drillfield",
                destinationName: "Duck Pond",
                startLatitude: 37.2277,
                startLongitude: -80.4232,
                destinationLatitude: 37.2259,
                destinationLongitude: -80.4267,
                difficulty: "Easy",
                category: .campus
            )
        )
        .environmentObject(AppViewModel())
        .environmentObject(RideTrackingManager())
    }
}

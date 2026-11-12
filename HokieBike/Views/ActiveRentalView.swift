import SwiftUI
import CoreLocation
import MapKit

struct ActiveRentalView: View {
    let rental: Rental
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var rideTrackingManager: RideTrackingManager
    @StateObject private var locationManager = LocationPermissionManager()
    @StateObject private var bluetoothLockManager = BluetoothLockManager()
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var timerActive = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isEndingRide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                bikeImage

                VStack(alignment: .leading) {
                    Text(rental.bike.name)
                        .font(.headline)
                    Text(rental.bike.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(rental.bike.priceString)
                    .bold()
            }

            HStack {
                Text("Started: \(rental.startDate, style: .time)")
                Spacer()
                Text("Elapsed: \(elapsedString)" )
                    .monospacedDigit()
            }

            if let destinationName = rideTrackingManager.destinationName {
                Text("Heading to: \(destinationName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let status = rideTrackingManager.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !bluetoothLockManager.statusMessage.isEmpty {
                Text("Lock: \(bluetoothLockManager.statusMessage)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            rideMap

            HStack(spacing: 10) {
                Button {
                    rideTrackingManager.startTracking()
                } label: {
                    Label("Start Tracking", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("VTMaroon"))
                .disabled(rideTrackingManager.destinationCoordinate == nil || rideTrackingManager.isTracking)

                Button {
                    rideTrackingManager.stopTracking()
                } label: {
                    Label("Stop Tracking", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!rideTrackingManager.isTracking)
            }

            Button(action: {
                Task {
                    await endRideAndSendLock()
                }
            }) {
                Text(isEndingRide ? "Ending Ride..." : "Lock & End Ride")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isEndingRide)
        }
        .onAppear {
            updateElapsed()
            timerActive = true
            startTimer()
            locationManager.requestPermissionIfNeeded()
            rideTrackingManager.requestPermissionIfNeeded()
        }
        .onDisappear {
            timerActive = false
        }
    }

    var elapsedString: String {
        let interval = elapsedSeconds
        let hrs = Int(interval) / 3600
        let mins = (Int(interval) % 3600) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }

    func updateElapsed() {
        elapsedSeconds = rental.duration
    }

    func startTimer() {
        Task {
            while timerActive {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                updateElapsed()
            }
        }
    }

    private func endRideAndSendLock() async {
        guard !isEndingRide else { return }
        isEndingRide = true
        defer { isEndingRide = false }

        let lockSucceeded = await bluetoothLockManager.lockDemoBike()
        if !lockSucceeded {
            // Keep UX moving for demos/pilots while still surfacing lock failure state.
            bluetoothLockManager.statusMessage = "Lock command failed. Ending ride anyway."
        }

        let coordinate: CLLocationCoordinate2D?
        if let current = rideTrackingManager.currentCoordinate {
            coordinate = current
        } else {
            coordinate = await locationManager.requestSingleLocation()
        }

        let endLocation = coordinate.map { point in
            String(format: "%.5f, %.5f", point.latitude, point.longitude)
        }

        rideTrackingManager.stopTracking()
        viewModel.endRental(
            endLocation: endLocation,
            endCoordinate: coordinate,
            destinationName: rideTrackingManager.destinationName,
            trackedPath: rideTrackingManager.trackedPath
        )
    }

    private var rideMap: some View {
        Map(position: $cameraPosition) {
            if let route = rideTrackingManager.plannedRoute {
                MapPolyline(route.polyline)
                    .stroke(Color("VTOrange"), lineWidth: 4)
            }

            if trackedPathPolyline.pointCount > 1 {
                MapPolyline(trackedPathPolyline)
                    .stroke(Color("VTMaroon"), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let destination = rideTrackingManager.destinationCoordinate {
                Marker("Destination", coordinate: destination)
                    .tint(Color("VTOrange"))
            }

            UserAnnotation()
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(rideTrackingManager.$currentCoordinate) { coordinate in
            guard let coordinate else { return }
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                )
            }
        }
    }

    private var trackedPathPolyline: MKPolyline {
        MKPolyline(coordinates: rideTrackingManager.trackedPath, count: rideTrackingManager.trackedPath.count)
    }

    @ViewBuilder
    private var bikeImage: some View {
        if rental.bike.usesAssetImage {
            Image(rental.bike.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: rental.bike.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundColor(Color("VTMaroon"))
        }
    }
}

struct ActiveRentalView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = AppViewModel()
        vm.startRental(bike: vm.bikes[0])
        return ActiveRentalView(rental: vm.activeRental!)
            .environmentObject(vm)
            .environmentObject(RideTrackingManager())
    }
}

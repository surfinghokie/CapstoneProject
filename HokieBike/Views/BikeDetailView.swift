import SwiftUI
import CoreLocation

struct BikeDetailView: View {
    let bike: Bike
    @EnvironmentObject var viewModel: AppViewModel

    @StateObject private var locationManager = LocationPermissionManager()
    @StateObject private var bluetoothLockManager = BluetoothLockManager()
    @State private var isUnlocking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.95))
                        .frame(height: 220)

                    detailImage
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(bike.name)
                        .font(.title2.bold())
                    Text("\(bike.type) • Owned by \(bike.ownerName)")
                        .foregroundColor(.secondary)

                    Text(bike.description)
                        .padding(.top, 6)

                    HStack {
                        Text("Location: \(bike.location)")
                        Spacer()
                        Text(bike.priceString)
                            .bold()
                    }

                    if let lastSeenAt = bike.lastSeenAt {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last seen: \(relativeLastSeenText(for: lastSeenAt))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(lastSeenSourceText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Last seen: no ride-end location yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !bluetoothLockManager.statusMessage.isEmpty {
                    Text(bluetoothLockManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    Task {
                        await unlockAndStartRide()
                    }
                }) {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryButtonEnabled ? Color("VTMaroon") : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!primaryButtonEnabled)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle(bike.name)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            Button {
                viewModel.toggleBikeSaved(bike)
            } label: {
                Image(systemName: viewModel.isBikeSaved(bike) ? "heart.fill" : "heart")
            }
        }
        .task {
            locationManager.requestPermissionIfNeeded()
        }
    }

    @ViewBuilder
    private var detailImage: some View {
        if bike.usesAssetImage {
            Image(bike.imageName)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(6)
        } else {
            Image(systemName: bike.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 120)
                .foregroundColor(Color("VTMaroon"))
        }
    }

    private var primaryButtonEnabled: Bool {
        viewModel.activeRental == nil && bike.isAvailable && !isUnlocking && !bluetoothLockManager.isBusy
    }

    private var buttonTitle: String {
        if !bike.isAvailable || viewModel.activeRental != nil {
            return "Unavailable"
        }
        if isUnlocking || bluetoothLockManager.isBusy {
            return "Unlocking..."
        }
        return "Unlock & Start Ride"
    }

    private var lastSeenSourceText: String {
        switch bike.lastSeenSource {
        case "ride_end":
            return "Source: rider location at end of last ride"
        case let source?:
            return "Source: \(source)"
        default:
            return "Source: unknown"
        }
    }

    private func relativeLastSeenText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func unlockAndStartRide() async {
        guard primaryButtonEnabled else { return }
        isUnlocking = true
        defer { isUnlocking = false }

        let location = await locationManager.requestSingleLocation()
        let unlockSucceeded = await bluetoothLockManager.unlockDemoBike()

        guard unlockSucceeded else { return }

        let startLocation = location.map { coordinate in
            String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        } ?? bike.location

        viewModel.startRental(bike: bike, startLocation: startLocation, startCoordinate: location)
    }
}

struct BikeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        BikeDetailView(bike: Bike(name: "Preview Bike", type: "Road", ownerName: "Owner", description: "Test bike", pricePerHour: 5.0, location: "Drillfield", isAvailable: true))
            .environmentObject(AppViewModel())
    }
}

import SwiftUI

struct MyRentalsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var rideTrackingManager: RideTrackingManager
    @State private var pendingRentalDelete: Rental?

    var body: some View {
        List {
            Section("Current Rental") {
                if let active = viewModel.activeRental {
                    ActiveRentalView(rental: active)
                        .environmentObject(viewModel)
                        .environmentObject(rideTrackingManager)
                } else {
                    Text("No active rental")
                        .foregroundColor(.secondary)
                }
            }

            Section("Past Rentals") {
                if viewModel.rentalsHistory.isEmpty {
                    Text("No past rentals yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.rentalsHistory) { rental in
                        VStack(alignment: .leading) {
                            Text(rental.bike.name)
                                .font(.headline)
                            Text(rental.startDate, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text(String(format: "Duration: %.1f hrs", rental.duration / 3600.0))
                                Spacer()
                                Text(String(format: "$%.2f", rental.cost(usingHourlyRate: nil)))
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 6)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingRentalDelete = rental
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Rentals")
        .alert(
            "Delete trip?",
            isPresented: Binding(
                get: { pendingRentalDelete != nil },
                set: { if !$0 { pendingRentalDelete = nil } }
            ),
            presenting: pendingRentalDelete
        ) { rental in
            Button("Delete", role: .destructive) {
                viewModel.deleteRental(rentalID: rental.id)
                pendingRentalDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRentalDelete = nil
            }
        } message: { _ in
            Text("This trip will be removed from your history and backend records. Any of your shared community posts linked to this trip will also be removed.")
        }
    }
}

struct MyRentalsView_Previews: PreviewProvider {
    static var previews: some View {
        MyRentalsView()
            .environmentObject(AppViewModel())
            .environmentObject(RideTrackingManager())
    }
}

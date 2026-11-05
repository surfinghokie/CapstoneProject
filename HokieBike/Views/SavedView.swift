import SwiftUI

struct SavedView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        List {
            Section("Saved Journeys") {
                if savedJourneys.isEmpty {
                    Text("No saved journeys yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(savedJourneys) { journey in
                        NavigationLink(destination: JourneyDetailView(journey: journey).environmentObject(viewModel)) {
                            VStack(alignment: .leading) {
                                Text(journey.title)
                                    .font(.headline)
                                Text(journey.destinationName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.toggleJourneySaved(journey)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Saved Bikes") {
                if savedBikes.isEmpty {
                    Text("No saved bikes yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(savedBikes) { bike in
                        NavigationLink(destination: BikeDetailView(bike: bike).environmentObject(viewModel)) {
                            BikeCardView(bike: bike)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.toggleBikeSaved(bike)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }

    private var savedJourneys: [Journey] {
        viewModel.journeys.filter { viewModel.savedJourneyIDs.contains($0.id) }
    }

    private var savedBikes: [Bike] {
        viewModel.bikes.filter { viewModel.savedBikeIDs.contains($0.id) }
    }
}

#Preview {
    NavigationStack {
        SavedView()
            .environmentObject(AppViewModel())
    }
}

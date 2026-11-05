import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingListSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("HokieBike")
                            .font(.largeTitle.bold())
                            .foregroundColor(Color("VTMaroon"))
                        Text("Bike sharing for Hokies")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "bicycle.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .foregroundColor(Color("VTMaroon"))
                }

                // Featured bikes
                Text("Featured")
                    .font(.headline)

                ForEach(viewModel.bikes.prefix(3)) { bike in
                    NavigationLink(destination: BikeDetailView(bike: bike).environmentObject(viewModel)) {
                        BikeCardView(bike: bike)
                            .padding(.horizontal)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
                    }
                }

                HStack {
                    NavigationLink(destination: BrowseBikesView().environmentObject(viewModel)) {
                        Label("Browse All Bikes", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color("VTMaroon"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: { showingListSheet = true }) {
                        Label("List a Bike", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .sheet(isPresented: $showingListSheet) {
                        NavigationStack {
                            ListBikeView()
                                .environmentObject(viewModel)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView().environmentObject(AppViewModel())
    }
}

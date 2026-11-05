import SwiftUI

struct BrowseBikesView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        List {
            ForEach(viewModel.bikes) { bike in
                NavigationLink(destination: BikeDetailView(bike: bike).environmentObject(viewModel)) {
                    BikeCardView(bike: bike)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Browse Bikes")
    }
}

struct BrowseBikesView_Previews: PreviewProvider {
    static var previews: some View {
        BrowseBikesView().environmentObject(AppViewModel())
    }
}

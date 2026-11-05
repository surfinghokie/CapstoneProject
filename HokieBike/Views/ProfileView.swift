import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .foregroundColor(Color("VTMaroon"))

                Text(viewModel.currentUser.name)
                    .font(.title2.bold())

                Text(viewModel.currentUser.isVTStudent ? "Virginia Tech Student" : "Guest")
                    .foregroundColor(.secondary)

                HStack(spacing: 20) {
                    VStack {
                        Text("Rentals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.currentUser.rentalsCount)")
                            .bold()
                    }

                    VStack {
                        Text("Bikes Listed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.currentUser.bikesListed)")
                            .bold()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Account")
                        .font(.headline)
                    Text("Account settings placeholder")
                    Text("Notifications, payment methods, and preferences can go here in the future.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Profile")
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView().environmentObject(AppViewModel())
    }
}

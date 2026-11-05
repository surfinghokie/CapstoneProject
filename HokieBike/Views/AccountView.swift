import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct AccountView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var authManager: AuthSessionManager
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var isShowingProfileEditor = false

    var body: some View {
        List {
            Section("Profile") {
                HStack(spacing: 12) {
                    profileImageView
                    VStack(alignment: .leading) {
                        Text(viewModel.currentUser.name)
                            .font(.headline)
                        Text(viewModel.currentUser.isVTStudent ? "Virginia Tech Student" : "User")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let pilotID = viewModel.currentUser.pilotID, !pilotID.isEmpty {
                            Text("Pilot ID: \(pilotID)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Create / Edit Account") {
                    isShowingProfileEditor = true
                }
            }

            Section("Rider Metrics") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        metricCard(
                            title: "Total Distance",
                            value: String(format: "%.1f mi / %.1f km", viewModel.totalDistanceMiles, viewModel.totalDistanceKm),
                            symbol: "map"
                        )
                        metricCard(
                            title: "Avg Speed",
                            value: String(format: "%.1f mph / %.1f km/h", viewModel.averageSpeedMph, viewModel.averageSpeedKph),
                            symbol: "speedometer"
                        )
                        metricCard(
                            title: "CO2 Saved",
                            value: String(format: "%.2f kg", viewModel.estimatedCO2SavedKg),
                            symbol: "leaf"
                        )
                        metricCard(
                            title: "Completed Rides",
                            value: "\(viewModel.currentUser.rentalsCount)",
                            symbol: "bicycle"
                        )
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Activity Summary") {
                Label("Journeys Saved: \(viewModel.savedJourneyIDs.count)", systemImage: "bookmark")
                Label("Bikes Listed: \(viewModel.currentUser.bikesListed)", systemImage: "plus.square")
                Label("Community Posts: \(viewModel.communityPosts.count)", systemImage: "person.3")
            }

            Section("Sync Diagnostics") {
                Label(viewModel.lastSyncStatus, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.secondary)

                if let syncAt = viewModel.lastSyncAt {
                    Label("Last Sync: \(syncAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = viewModel.lastSyncError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Label("Session UID: \(viewModel.backendUIDForDiagnostics)", systemImage: "person.crop.rectangle")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Label("Pilot Tag: \(viewModel.currentUser.pilotID ?? "Not set")", systemImage: "tag")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Label("Latest Ride Snapshot: \(viewModel.latestRideSnapshotID ?? "None yet")", systemImage: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button("Run Backend Sync Check") {
                    viewModel.runSyncDiagnostics()
                }
            }

            Section("Settings") {
                Text("Edit Profile")
                Text("Notification Preferences")
                Text("Location Permissions Info")

                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
            }

            Section("Privacy & Security") {
                Text("Profile Visibility")
                Text("Journey Sharing Preferences")
                Text("Friend Request Preferences")
            }

            Section("Policies & Information") {
                Text("Privacy Policy (Draft)")
                Text("Terms of Service (Draft)")
                Text("Bicycle Rental Policies (Draft)")
                Text("Community Guidelines (Draft)")
            }

            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Text("Log Out")
                }
            }
        }
        .navigationTitle("Account")
        .sheet(isPresented: $isShowingProfileEditor) {
            NavigationStack {
                ProfileEditorView(
                    initialName: viewModel.currentUser.name,
                    initialIsVTStudent: viewModel.currentUser.isVTStudent,
                    initialPhotoURL: viewModel.currentUser.profilePhotoURL,
                    initialPilotID: viewModel.currentUser.pilotID
                ) { updatedName, isVTStudent, profileImageData, pilotID in
                    viewModel.updateCurrentUserProfile(name: updatedName, isVTStudent: isVTStudent, profileImageData: profileImageData, pilotID: pilotID)
                }
            }
        }
    }

    @ViewBuilder
    private var profileImageView: some View {
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
                        .foregroundColor(Color("VTMaroon"))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color("VTMaroon"))
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private func metricCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isVTStudent: Bool
#if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
#endif
    @State private var selectedPhotoData: Data?
    let initialPhotoURL: String?
    @State private var pilotID: String

    let onSave: (_ name: String, _ isVTStudent: Bool, _ profileImageData: Data?, _ pilotID: String) -> Void

    init(
        initialName: String,
        initialIsVTStudent: Bool,
        initialPhotoURL: String?,
        initialPilotID: String?,
        onSave: @escaping (_ name: String, _ isVTStudent: Bool, _ profileImageData: Data?, _ pilotID: String) -> Void
    ) {
        _name = State(initialValue: initialName)
        _isVTStudent = State(initialValue: initialIsVTStudent)
        _pilotID = State(initialValue: initialPilotID ?? "")
        self.initialPhotoURL = initialPhotoURL
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Account Details") {
                TextField("Full name", text: $name)
                Toggle("Virginia Tech Student", isOn: $isVTStudent)
                TextField("Pilot ID (for study)", text: $pilotID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section("Profile Photo") {
#if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        selectedPhotoData = try? await newItem?.loadTransferable(type: Data.self)
                    }
                }
#else
                Text("Photo picker unavailable on this platform.")
                    .font(.caption)
                    .foregroundColor(.secondary)
#endif

                profilePreview
            }
        }
        .navigationTitle("Your Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(name, isVTStudent, selectedPhotoData, pilotID)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var profilePreview: some View {
#if canImport(UIKit)
        if let selectedPhotoData, let image = UIImage(data: selectedPhotoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
        } else if let initialPhotoURL, let url = URL(string: initialPhotoURL), !initialPhotoURL.isEmpty {
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
                        .foregroundColor(Color("VTMaroon"))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
        }
#endif
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environmentObject(AppViewModel())
            .environmentObject(AuthSessionManager())
    }
}

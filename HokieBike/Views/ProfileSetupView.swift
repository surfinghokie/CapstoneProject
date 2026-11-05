import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct ProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isVTStudent: Bool
    @State private var selectedPhotoData: Data?
#if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
#endif

    let onComplete: (_ name: String, _ isVTStudent: Bool, _ profileImageData: Data?) -> Void

    init(initialName: String, initialIsVTStudent: Bool, onComplete: @escaping (_ name: String, _ isVTStudent: Bool, _ profileImageData: Data?) -> Void) {
        _name = State(initialValue: initialName)
        _isVTStudent = State(initialValue: initialIsVTStudent)
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set up your profile") {
                    TextField("Your name", text: $name)
                    Toggle("Virginia Tech Student", isOn: $isVTStudent)
#if canImport(PhotosUI)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Profile Photo", systemImage: "person.crop.circle.badge.plus")
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            selectedPhotoData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
#endif
                    Text("This profile is used for your trips, metrics, and community posts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Welcome to HokieBike")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onComplete(name, isVTStudent, selectedPhotoData)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ProfileSetupView(initialName: "", initialIsVTStudent: true) { _, _, _ in }
}

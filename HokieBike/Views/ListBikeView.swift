import SwiftUI

struct ListBikeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var type = ""
    @State private var description = ""
    @State private var priceText = "5.00"
    @State private var location = ""
    @State private var isAvailable = true

    var body: some View {
        Form {
            Section(header: Text("Bike Details")) {
                TextField("Name", text: $name)
                TextField("Type (e.g. Road, Mountain)", text: $type)
                TextField("Location (Campus spot)", text: $location)
                TextField("Price per hour", text: $priceText)
#if canImport(UIKit)
                .keyboardType(.decimalPad)
#endif
                Toggle("Available", isOn: $isAvailable)
                TextEditor(text: $description)
                    .frame(height: 100)
            }

            Button(action: save) {
                Text("List Bike")
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("List a Bike")
#if os(macOS)
        .toolbar {
            ToolbarItem {
                Button("Done") { dismiss() }
            }
        }
#else
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
#endif
    }

    func save() {
        let price = Double(priceText) ?? 5.0
        viewModel.addBike(name: name.isEmpty ? "Untitled Bike" : name,
                          type: type.isEmpty ? "Hybrid" : type,
                          description: description,
                          pricePerHour: price,
                          location: location.isEmpty ? "Campus" : location,
                          isAvailable: isAvailable)

        dismiss()
    }
}

struct ListBikeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ListBikeView().environmentObject(AppViewModel()) }
    }
}

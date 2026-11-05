import SwiftUI

struct BikeCardView: View {
    let bike: Bike

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.95))
                    .frame(width: 68, height: 68)

                bikeThumbnail
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(bike.name)
                    .font(.headline)
                Text("\(bike.type) • \(bike.ownerName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text(bike.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(bike.priceString)
                        .font(.caption)
                        .bold()
                }

                if let lastSeenAt = bike.lastSeenAt {
                    Text("Last seen \(relativeLastSeenText(for: lastSeenAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !bike.isAvailable {
                Text("Unavailable")
                    .font(.caption2)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
    }

    private func relativeLastSeenText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var bikeThumbnail: some View {
        if bike.usesAssetImage {
            Image(bike.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: bike.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundColor(.accentColor)
        }
    }
}

struct BikeCardView_Previews: PreviewProvider {
    static var previews: some View {
        BikeCardView(bike: Bike(name: "Trek Marlin 5", type: "Mountain", ownerName: "A. Lee", description: "", pricePerHour: 4.5, location: "Torgersen Bridge", isAvailable: true))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

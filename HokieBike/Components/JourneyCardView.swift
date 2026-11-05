import SwiftUI

struct JourneyCardView: View {
    let journey: Journey
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("VTMaroon").opacity(0.12))
                    .frame(height: 110)

                coverImage
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(Color("VTOrange"))
                        .padding(10)
                }
            }

            Text(journey.title)
                .font(.headline)
                .lineLimit(1)

            Text(journey.subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack {
                Text(journey.difficulty)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
                Spacer()
                Text(journey.category.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private var coverImage: some View {
        if journey.usesAssetImage {
            Image(journey.imageName)
                .resizable()
                .scaledToFill()
        } else {
            ZStack(alignment: .topTrailing) {
                Color.clear
                Image(systemName: journey.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .foregroundColor(Color("VTMaroon"))
                    .padding(10)
            }
        }
    }
}

#Preview {
    JourneyCardView(
        journey: Journey(
            title: "Duck Pond Cruise",
            subtitle: "Virginia Tech Campus",
            description: "Relaxing campus ride",
            startName: "Drillfield",
            destinationName: "Duck Pond",
            startLatitude: 37.2277,
            startLongitude: -80.4232,
            destinationLatitude: 37.2259,
            destinationLongitude: -80.4267,
            difficulty: "Easy",
            category: .campus
        ),
        isSaved: true
    )
    .padding()
}

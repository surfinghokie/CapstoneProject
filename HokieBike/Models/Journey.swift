import Foundation
import CoreLocation

struct Journey: Identifiable, Equatable {
    let id: UUID
    var title: String
    var subtitle: String
    var description: String
    var startName: String
    var destinationName: String
    var startLatitude: Double
    var startLongitude: Double
    var destinationLatitude: Double
    var destinationLongitude: Double
    var difficulty: String
    var category: JourneyCategory
    var imageName: String
    var usesAssetImage: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        description: String,
        startName: String,
        destinationName: String,
        startLatitude: Double,
        startLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double,
        difficulty: String,
        category: JourneyCategory,
        imageName: String = "figure.outdoor.cycle",
        usesAssetImage: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.startName = startName
        self.destinationName = destinationName
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.difficulty = difficulty
        self.category = category
        self.imageName = imageName
        self.usesAssetImage = usesAssetImage
    }

    var startCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }
}

enum JourneyCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case campus = "Campus"
    case scenic = "Scenic"
    case beginner = "Beginner Friendly"
    case exercise = "Exercise"
    case longerRides = "Longer Rides"
    case community = "Community Favorites"

    var id: String { rawValue }
}

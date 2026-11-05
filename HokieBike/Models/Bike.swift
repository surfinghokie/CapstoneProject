import Foundation
import SwiftUI
import CoreLocation

/// Simple Bike model for the prototype
struct Bike: Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: String
    var ownerName: String
    var description: String
    var pricePerHour: Double
    var location: String
    var isAvailable: Bool
    /// Local image name from asset catalog or SF Symbol.
    var imageName: String
    /// True when imageName refers to an asset image instead of an SF Symbol.
    var usesAssetImage: Bool
    var latitude: Double?
    var longitude: Double?
    var lastSeenAt: Date?
    /// Ex: "ride_end" when updated from a completed trip.
    var lastSeenSource: String?

    init(
        id: UUID = UUID(),
        name: String,
        type: String,
        ownerName: String,
        description: String = "",
        pricePerHour: Double,
        location: String,
        isAvailable: Bool = true,
        imageName: String = "bicycle",
        usesAssetImage: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        lastSeenAt: Date? = nil,
        lastSeenSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.ownerName = ownerName
        self.description = description
        self.pricePerHour = pricePerHour
        self.location = location
        self.isAvailable = isAvailable
        self.imageName = imageName
        self.usesAssetImage = usesAssetImage
        self.latitude = latitude
        self.longitude = longitude
        self.lastSeenAt = lastSeenAt
        self.lastSeenSource = lastSeenSource
    }

    var priceString: String {
        String(format: "$%.2f/hr", pricePerHour)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

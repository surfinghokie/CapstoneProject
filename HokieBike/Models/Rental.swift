import Foundation
import CoreLocation

struct Rental: Identifiable {
    let id: UUID
    let bike: Bike
    let renterName: String
    let startDate: Date
    var endDate: Date?
    var startLocation: String?
    var endLocation: String?
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    init(
        id: UUID = UUID(),
        bike: Bike,
        renterName: String,
        startDate: Date = Date(),
        startLocation: String? = nil,
        startCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.id = id
        self.bike = bike
        self.renterName = renterName
        self.startDate = startDate
        self.startLocation = startLocation
        self.startLatitude = startCoordinate?.latitude
        self.startLongitude = startCoordinate?.longitude
    }

    var isActive: Bool {
        endDate == nil
    }

    var duration: TimeInterval {
        let end = endDate ?? Date()
        return end.timeIntervalSince(startDate)
    }

    var distanceMeters: CLLocationDistance? {
        guard let startLatitude, let startLongitude, let endLatitude, let endLongitude else { return nil }
        let start = CLLocation(latitude: startLatitude, longitude: startLongitude)
        let end = CLLocation(latitude: endLatitude, longitude: endLongitude)
        return end.distance(from: start)
    }

    func cost(usingHourlyRate rate: Double? = nil) -> Double {
        let hours = max(duration / 3600.0, 0.0)
        let pph = rate ?? bike.pricePerHour
        return hours * pph
    }
}

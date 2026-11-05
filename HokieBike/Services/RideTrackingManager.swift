import Foundation
import Combine
import CoreLocation
import MapKit

struct RideSummary: Identifiable {
    let id = UUID()
    let endedAt: Date
    let destinationName: String?
    let durationSeconds: TimeInterval
    let distanceMeters: CLLocationDistance
    let averageSpeedKph: Double
    let didArrive: Bool
}

struct UpcomingDirection: Identifiable {
    let id = UUID()
    let instruction: String
    let distanceMeters: CLLocationDistance
}

@MainActor
final class RideTrackingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isTracking = false
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var trackedPath: [CLLocationCoordinate2D] = []
    @Published var destinationName: String?
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var plannedRoute: MKRoute?
    @Published var statusMessage: String?
    @Published var nextInstruction: String?
    @Published var upcomingDirections: [String] = []
    @Published var upcomingDirectionItems: [UpcomingDirection] = []
    @Published var remainingDistanceMeters: CLLocationDistance?
    @Published var remainingETASeconds: TimeInterval?
    @Published var arrivalEventID: UUID?
    @Published var latestSummary: RideSummary?

    private let manager = CLLocationManager()
    private let arrivalThresholdMeters: CLLocationDistance = 30
    private var didAnnounceArrival = false
    private var trackingStartDate: Date?
    private var trackingDistanceMeters: CLLocationDistance = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func setDestination(name: String, coordinate: CLLocationCoordinate2D, bikeFallback: CLLocationCoordinate2D?) async {
        destinationName = name
        destinationCoordinate = coordinate
        didAnnounceArrival = false
        await recalculateRoute(from: preferredStartCoordinate(bikeFallback: bikeFallback))
        if let currentCoordinate {
            updateGuidance(for: currentCoordinate)
        }
    }

    func startTracking() {
        if !isTracking {
            trackingStartDate = Date()
            trackingDistanceMeters = 0
            trackedPath = []
            didAnnounceArrival = false
        }

        isTracking = true
        if let currentCoordinate, trackedPath.isEmpty {
            trackedPath.append(currentCoordinate)
        }
        if let currentCoordinate {
            updateGuidance(for: currentCoordinate)
        }
        manager.startUpdatingLocation()
        statusMessage = destinationCoordinate == nil ? "Free ride tracking started." : "Ride tracking started."
    }

    func stopTracking(setStatusMessage: Bool = true) {
        guard isTracking else {
            if setStatusMessage {
                statusMessage = "Ride tracking stopped."
            }
            return
        }

        let didArrive = didAnnounceArrival
        isTracking = false
        manager.stopUpdatingLocation()
        publishSummary(didArrive: didArrive)
        if setStatusMessage {
            statusMessage = "Ride tracking stopped."
        }
    }

    func clearRoute() {
        destinationName = nil
        destinationCoordinate = nil
        plannedRoute = nil
        trackedPath = []
        statusMessage = nil
        nextInstruction = nil
        upcomingDirections = []
        upcomingDirectionItems = []
        remainingDistanceMeters = nil
        remainingETASeconds = nil
        didAnnounceArrival = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentCoordinate = latest.coordinate

        if isTracking {
            if let last = trackedPath.last {
                let lastPoint = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let distance = latest.distance(from: lastPoint)
                if distance > 5 {
                    trackingDistanceMeters += distance
                    trackedPath.append(latest.coordinate)
                }
            } else {
                trackedPath.append(latest.coordinate)
            }
        }

        updateGuidance(for: latest.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "Location update failed."
    }

    private func preferredStartCoordinate(bikeFallback: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        currentCoordinate ?? bikeFallback
    }

    private func recalculateRoute(from sourceCoordinate: CLLocationCoordinate2D?) async {
        guard let destinationCoordinate else { return }

        let source = sourceCoordinate ?? destinationCoordinate

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .any

        do {
            let response = try await MKDirections(request: request).calculate()
            plannedRoute = response.routes.first
            if plannedRoute == nil {
                statusMessage = "Could not calculate route right now."
                nextInstruction = nil
                remainingDistanceMeters = nil
                remainingETASeconds = nil
            } else if let currentCoordinate {
                updateGuidance(for: currentCoordinate)
            }
        } catch {
            plannedRoute = nil
            statusMessage = "Could not calculate route right now."
            nextInstruction = nil
            remainingDistanceMeters = nil
            remainingETASeconds = nil
        }
    }

    private func updateGuidance(for coordinate: CLLocationCoordinate2D) {
        guard let route = plannedRoute else {
            nextInstruction = nil
            upcomingDirections = []
            upcomingDirectionItems = []
            remainingDistanceMeters = nil
            remainingETASeconds = nil
            return
        }

        if let destinationCoordinate {
            let rider = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let destination = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
            let distanceToDestination = rider.distance(from: destination)
            if distanceToDestination <= arrivalThresholdMeters && !didAnnounceArrival {
                didAnnounceArrival = true
                statusMessage = "Arrived at destination."
                arrivalEventID = UUID()
                stopTracking(setStatusMessage: false)
                remainingDistanceMeters = 0
                remainingETASeconds = 0
                nextInstruction = "You have arrived"
                upcomingDirections = []
                upcomingDirectionItems = []
                return
            }
        }

        let steps = route.steps.enumerated().filter { !$0.element.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !steps.isEmpty else {
            nextInstruction = "Continue to destination"
            upcomingDirections = ["Continue to destination"]
            upcomingDirectionItems = [UpcomingDirection(instruction: "Continue to destination", distanceMeters: route.distance)]
            remainingDistanceMeters = route.distance
            remainingETASeconds = route.expectedTravelTime
            return
        }

        let riderPoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let nearest = steps.min { lhs, rhs in
            minDistance(from: riderPoint, to: lhs.element.polyline) < minDistance(from: riderPoint, to: rhs.element.polyline)
        }

        guard let nearest else { return }

        let nearestIdx = nearest.offset
        let nearestStep = nearest.element
        nextInstruction = nearestStep.instructions

        let remainingSteps = route.steps.dropFirst(nearestIdx)
        let remainingStepItems = remainingSteps
            .compactMap { step -> UpcomingDirection? in
                let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { return nil }
                return UpcomingDirection(instruction: instruction, distanceMeters: step.distance)
            }
        upcomingDirectionItems = Array(remainingStepItems.prefix(5))
        upcomingDirections = upcomingDirectionItems.map(\.instruction)

        let remainingMeters = remainingSteps.reduce(0.0) { $0 + $1.distance }
        let ratio = route.distance > 0 ? min(max(remainingMeters / route.distance, 0), 1) : 0
        remainingDistanceMeters = remainingMeters
        remainingETASeconds = route.expectedTravelTime * ratio
    }

    private func minDistance(from point: CLLocation, to polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let mapPoints = polyline.points()
        var minimum = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<polyline.pointCount {
            let mapPoint = mapPoints[index]
            let coordinate = mapPoint.coordinate
            let polylinePoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            minimum = min(minimum, point.distance(from: polylinePoint))
        }
        return minimum
    }

    private func publishSummary(didArrive: Bool) {
        guard let start = trackingStartDate else { return }

        let duration = max(Date().timeIntervalSince(start), 1)
        let averageSpeedKph = (trackingDistanceMeters / 1000.0) / (duration / 3600.0)

        latestSummary = RideSummary(
            endedAt: Date(),
            destinationName: destinationName,
            durationSeconds: duration,
            distanceMeters: trackingDistanceMeters,
            averageSpeedKph: averageSpeedKph,
            didArrive: didArrive
        )
    }
}

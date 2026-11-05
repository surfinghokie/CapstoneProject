import Foundation
import CoreLocation
import Combine

final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocationCoordinate2D?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func recenterRequest() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        } else {
            requestPermissionIfNeeded()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(returning: currentLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(returning: currentLocation)
        }
    }

    func requestSingleLocation(timeoutSeconds: Double = 6) async -> CLLocationCoordinate2D? {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return nil
        }

        manager.requestLocation()

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            Task { [weak self] in
                let timeoutNs = UInt64(max(timeoutSeconds, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNs)
                guard let self else { return }
                if let pending = self.locationContinuation {
                    self.locationContinuation = nil
                    pending.resume(returning: self.currentLocation)
                }
            }
        }
    }
}

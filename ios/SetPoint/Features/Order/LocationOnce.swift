import CoreLocation

/// One location fix for Order nearby, asked for only when that screen opens.
@MainActor
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    enum Failure: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var denied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func coordinate() async throws -> CLLocationCoordinate2D {
        if denied { throw Failure.denied }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation?.resume(throwing: Failure.unavailable)
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if continuation != nil { manager.requestLocation() }
            case .denied, .restricted:
                finish(.failure(Failure.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(Failure.unavailable)) }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

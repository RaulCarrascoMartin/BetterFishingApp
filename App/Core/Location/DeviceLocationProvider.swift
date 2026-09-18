import CoreLocation
import Foundation
import os

@MainActor
protocol DeviceLocationProviding: Sendable {
    func requestPermissionIfNeeded() async -> Bool
    func currentLocation() async -> LocationCoordinate2D?
}

protocol LocationAuthorizationing: Sendable {
    var authorizationStatus: CLAuthorizationStatus { get async }
    func requestWhenInUseAuthorization() async
}

protocol LocationFetching: Sendable {
    func currentCoordinate(timeout: Duration) async -> CLLocationCoordinate2D?
}

@MainActor
struct DeviceLocationProvider: DeviceLocationProviding {
    private let authorization: any LocationAuthorizationing
    private let fetcher: any LocationFetching
    private let timeout: Duration

    init(
        authorization: any LocationAuthorizationing,
        fetcher: any LocationFetching,
        timeout: Duration = .seconds(3)
    ) {
        self.authorization = authorization
        self.fetcher = fetcher
        self.timeout = timeout
    }

    func requestPermissionIfNeeded() async -> Bool {
        switch await authorization.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            await authorization.requestWhenInUseAuthorization()
            switch await authorization.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                return true
            default:
                return false
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func currentLocation() async -> LocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        guard await requestPermissionIfNeeded() else { return nil }
        guard let coordinate = await fetcher.currentCoordinate(timeout: timeout) else {
            return nil
        }
        return LocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

@MainActor
final class CLLocationAuthorization: LocationAuthorizationing {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus {
        get async { manager.authorizationStatus }
    }

    func requestWhenInUseAuthorization() async {
        manager.requestWhenInUseAuthorization()
    }
}

extension CLLocationFetcher: @unchecked Sendable {}

final class CLLocationFetcher: NSObject, CLLocationManagerDelegate, LocationFetching {
    private struct State {
        var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    private let manager: CLLocationManager
    private let state = OSAllocatedUnfairLock(initialState: State())

    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    func currentCoordinate(timeout: Duration) async -> CLLocationCoordinate2D? {
        guard state.withLock({ $0.continuation == nil }) else { return nil }
        return await withCheckedContinuation { continuation in
            state.withLock {
                $0.continuation = continuation
            }
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(with: nil)
            }
            state.withLock {
                $0.timeoutTask = timeoutTask
            }
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        let pending: CheckedContinuation<CLLocationCoordinate2D?, Never>? = state.withLock { state in
            guard let continuation = state.continuation else { return nil }
            state.continuation = nil
            state.timeoutTask?.cancel()
            state.timeoutTask = nil
            return continuation
        }
        pending?.resume(returning: coordinate)
    }
}
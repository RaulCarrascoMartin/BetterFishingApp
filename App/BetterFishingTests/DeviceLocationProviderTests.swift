import CoreLocation
import XCTest

@testable import BetterFishing

@MainActor
final class LocationAuthorizationFake: LocationAuthorizationing {
    var status: CLAuthorizationStatus
    var statusAfterRequest: CLAuthorizationStatus
    private(set) var requestCallCount = 0

    init(status: CLAuthorizationStatus, statusAfterRequest: CLAuthorizationStatus? = nil) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest ?? status
    }

    var authorizationStatus: CLAuthorizationStatus {
        get async { status }
    }

    func requestWhenInUseAuthorization() async {
        requestCallCount += 1
        status = statusAfterRequest
    }
}

@MainActor
final class LocationFetcherFake: LocationFetching {
    var coordinate: CLLocationCoordinate2D?

    private(set) var callCount = 0

    init(coordinate: CLLocationCoordinate2D? = nil) {
        self.coordinate = coordinate
    }

    func currentCoordinate(timeout: Duration) async -> CLLocationCoordinate2D? {
        callCount += 1
        return coordinate
    }
}

@MainActor
final class DeviceLocationProviderTests: XCTestCase {
    private let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)

    private func makeProvider(
        authorization: LocationAuthorizationFake,
        fetcher: LocationFetcherFake
    ) -> DeviceLocationProvider {
        DeviceLocationProvider(authorization: authorization, fetcher: fetcher)
    }

    func testCurrentLocationReturnsCoordinatesWhenPermissionGranted() async {
        let authorization = LocationAuthorizationFake(status: .authorizedWhenInUse)
        let fetcher = LocationFetcherFake(coordinate: miami)
        let provider = makeProvider(authorization: authorization, fetcher: fetcher)

        let location = await provider.currentLocation()

        XCTAssertEqual(location, LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918))
        XCTAssertEqual(authorization.requestCallCount, 0)
        XCTAssertEqual(fetcher.callCount, 1)
    }

    func testCurrentLocationReturnsNilWhenPermissionDenied() async {
        let authorization = LocationAuthorizationFake(status: .denied)
        let fetcher = LocationFetcherFake(coordinate: miami)
        let provider = makeProvider(authorization: authorization, fetcher: fetcher)

        let location = await provider.currentLocation()

        XCTAssertNil(location)
        XCTAssertEqual(authorization.requestCallCount, 0)
        XCTAssertEqual(fetcher.callCount, 0)
    }

    func testRequestPermissionIfNeededOnceAuthorizedDoesNotRequestAgain() async {
        let authorization = LocationAuthorizationFake(status: .authorizedAlways)
        let provider = makeProvider(authorization: authorization, fetcher: LocationFetcherFake())

        let first = await provider.requestPermissionIfNeeded()
        let second = await provider.requestPermissionIfNeeded()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testRequestPermissionIfNeededOnceDeniedDoesNotRequestAgain() async {
        let authorization = LocationAuthorizationFake(status: .restricted)
        let provider = makeProvider(authorization: authorization, fetcher: LocationFetcherFake())

        let first = await provider.requestPermissionIfNeeded()
        let second = await provider.requestPermissionIfNeeded()

        XCTAssertFalse(first)
        XCTAssertFalse(second)
        XCTAssertEqual(authorization.requestCallCount, 0)
    }

    func testRequestPermissionWhenNotDeterminedRequestsExactlyOnceAndReturnsTrueWhenGranted() async {
        let authorization = LocationAuthorizationFake(
            status: .notDetermined,
            statusAfterRequest: .authorizedWhenInUse
        )
        let provider = makeProvider(authorization: authorization, fetcher: LocationFetcherFake())

        let first = await provider.requestPermissionIfNeeded()
        let second = await provider.requestPermissionIfNeeded()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertEqual(authorization.requestCallCount, 1)
    }

    func testRequestPermissionWhenNotDeterminedReturnsFalseWhenDeniedAfterRequest() async {
        let authorization = LocationAuthorizationFake(
            status: .notDetermined,
            statusAfterRequest: .denied
        )
        let provider = makeProvider(authorization: authorization, fetcher: LocationFetcherFake())

        let granted = await provider.requestPermissionIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(authorization.requestCallCount, 1)
    }

    func testCurrentLocationReturnsNilWhenFetcherReturnsNothing() async {
        let authorization = LocationAuthorizationFake(status: .authorizedWhenInUse)
        let fetcher = LocationFetcherFake(coordinate: nil)
        let provider = makeProvider(authorization: authorization, fetcher: fetcher)

        let location = await provider.currentLocation()

        XCTAssertNil(location)
        XCTAssertEqual(fetcher.callCount, 1)
    }

    func testCurrentLocationRequestsPermissionWhenNotDeterminedBeforeFetching() async {
        let authorization = LocationAuthorizationFake(
            status: .notDetermined,
            statusAfterRequest: .authorizedWhenInUse
        )
        let fetcher = LocationFetcherFake(coordinate: miami)
        let provider = makeProvider(authorization: authorization, fetcher: fetcher)

        let location = await provider.currentLocation()

        XCTAssertEqual(location, LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918))
        XCTAssertEqual(authorization.requestCallCount, 1)
        XCTAssertEqual(fetcher.callCount, 1)
    }
}
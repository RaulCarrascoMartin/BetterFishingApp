import Foundation

struct SpotRegion: Equatable, Sendable {
    let center: LocationCoordinate2D
    let latitudinalMeters: Double
    let longitudinalMeters: Double

    init(center: LocationCoordinate2D, latitudinalMeters: Double, longitudinalMeters: Double) {
        self.center = center
        self.latitudinalMeters = latitudinalMeters
        self.longitudinalMeters = longitudinalMeters
    }

    var northLatitude: Double {
        center.latitude + (latitudinalMeters / 2) / 111_320
    }

    var minLatitude: Double {
        center.latitude - (latitudinalMeters / 2) / 111_320
    }

    var maxLatitude: Double {
        center.latitude + (latitudinalMeters / 2) / 111_320
    }

    var minLongitude: Double {
        center.longitude - (longitudinalMeters / 2) / (111_320 * cos(center.latitude * .pi / 180))
    }

    var maxLongitude: Double {
        center.longitude + (longitudinalMeters / 2) / (111_320 * cos(center.latitude * .pi / 180))
    }
}
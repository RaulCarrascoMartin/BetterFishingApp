import XCTest
import SwiftUI
import UIKit

@testable import BetterFishing

@MainActor
final class SpotMapTabTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    func testRootViewWithoutSpotServicesKeepsMapTabInUnavailableState() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotMapTabTests-\(UUID().uuidString)", isDirectory: true)
        let services = AppComposition.makeRootServices(arguments: [], draftsDirectory: tempDirectory)

        XCTAssertNil(services.spotMapViewModel, "Sin capa de datos no debe haber ViewModel de mapa (Req 2.1)")

        host(RootView(services: services))

        XCTAssertTrue(windowContainsText("Identificar"), "La pestaña Identificar no debe cambiar (sin regresión)")
        XCTAssertTrue(windowContainsText("Capturas"), "La pestaña Capturas no debe cambiar (sin regresión)")
        XCTAssertTrue(windowContainsText("Mapa"), "La pestaña Mapa debe existir aunque no haya capa de datos (Req 2.1)")
    }

    func testSpotMapViewHostsUnavailableStateWithoutCrashWhenRepositoryNil() {
        let viewModel = SpotMapViewModel(repository: nil, locationProvider: NoLocationStub())
        let mapView = SpotMapView(viewModel: viewModel) { spot in
            SpotDetailView(
                viewModel: SpotDetailViewModel(
                    repository: SpotRepositoryFake(),
                    auth: SupabaseBaseFake(),
                    spot: spot
                )
            )
        }

        host(mapView)

        XCTAssertEqual(viewModel.state, .unavailable, "Sin repositorio el mapa queda en no disponible (Req 2.1)")
        XCTAssertTrue(windowContainsText("Mapa"), "El mapa renderiza su shell de pantalla sin romperse")
        XCTAssertFalse(windowContainsText("Cerca de mí"), "Sin repositorio no debe construirse la UI del mapa real")
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        let hostedWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        hostedWindow.rootViewController = controller
        hostedWindow.makeKeyAndVisible()
        window = hostedWindow
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func windowContainsText(_ text: String) -> Bool {
        allSubviews(of: window?.rootViewController?.view).contains { view in
            viewText(view)?.localizedCaseInsensitiveContains(text) == true
        }
    }

    private func viewText(_ view: UIView) -> String? {
        if let label = view as? UILabel {
            return label.text
        }
        return view.accessibilityLabel
    }

    private func allSubviews(of view: UIView?) -> [UIView] {
        guard let view else { return [] }
        return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }
}

@MainActor
private final class NoLocationStub: DeviceLocationProviding {
    func requestPermissionIfNeeded() async -> Bool { false }
    func currentLocation() async -> LocationCoordinate2D? { nil }
}
import XCTest
import Supabase

@testable import BetterFishing

@MainActor
final class SupabaseCompositionTests: XCTestCase {
    func testMakeRootServicesWithEmptyConfigurationBuildsAllServicesAndNilStack() {
        let services = AppComposition.makeRootServices(arguments: [])

        XCTAssertNil(services.supabase, "Sin configuración accesible el stack de Supabase debe ser nil")
        XCTAssertNotNil(services.scannerViewModel)
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.catchLogViewModel)
        XCTAssertNotNil(services.migrator)
    }

    func testMakeRootServicesWithValidInjectedConfigurationBuildsStackWithThreeSeams() throws {
        let url = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let configuration = SupabaseClientConfiguration(projectURL: url, anonKey: "test-anon-key")

        let services = AppComposition.makeRootServices(
            arguments: [],
            supabaseConfiguration: configuration,
            supabaseOptions: makeClientOptions()
        )

        let stack = try XCTUnwrap(services.supabase, "Config válida inyectada debe producir un stack")
        XCTAssertNotNil(stack.auth)
        XCTAssertNotNil(stack.storage)
        XCTAssertNotNil(stack.database)
        XCTAssertNotNil(services.scannerViewModel)
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.catchLogViewModel)
        XCTAssertNotNil(services.migrator)
    }

    func testMakeRootServicesWithInvalidInjectedConfigurationDegradesGracefully() throws {
        let invalidURL = try XCTUnwrap(URL(string: "http://"))
        let configuration = SupabaseClientConfiguration(projectURL: invalidURL, anonKey: "test-anon-key")

        let services = AppComposition.makeRootServices(arguments: [], supabaseConfiguration: configuration)

        XCTAssertNil(services.supabase, "URL inválida debe degradar a stack nil sin romper el arranque")
        XCTAssertNotNil(services.scannerViewModel)
        XCTAssertNotNil(services.catchSaver)
        XCTAssertNotNil(services.catchLogViewModel)
        XCTAssertNotNil(services.migrator)
    }

    private func makeClientOptions() -> SupabaseClientOptions {
        SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthLocalStorage(), autoRefreshToken: false),
            global: .init(session: .mockSession())
        )
    }
}
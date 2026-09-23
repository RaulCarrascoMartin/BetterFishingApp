import Foundation
import XCTest

@testable import BetterFishing

final class SupabaseConfigurationTests: XCTestCase {
    func testValidURLAndAnonKeyProduceNonNilParsedConfiguration() throws {
        let bundle = try makeBundle([
            "SupabaseProjectURL": "https://abcd1234.supabase.co",
            "SupabaseAnonKey": "eyJhbGciOiJIUzI1NiJ9.anon-test-key",
        ])

        let configuration = SupabaseClientConfiguration(bundle: bundle)

        XCTAssertNotNil(configuration, "URL y anon key presentes deben producir una configuración")
        XCTAssertEqual(configuration?.projectURL, URL(string: "https://abcd1234.supabase.co"))
        XCTAssertEqual(configuration?.anonKey, "eyJhbGciOiJIUzI1NiJ9.anon-test-key")
    }

    func testMissingKeysReturnNil() throws {
        let bundle = try makeBundle([:])

        XCTAssertNil(SupabaseClientConfiguration(bundle: bundle), "Sin claves la configuración debe ser nil")
    }

    func testEmptyAnonKeyReturnsNil() throws {
        let bundle = try makeBundle([
            "SupabaseProjectURL": "https://abcd1234.supabase.co",
            "SupabaseAnonKey": "",
        ])

        XCTAssertNil(SupabaseClientConfiguration(bundle: bundle), "Anon key vacía debe traducirse a nil")
    }

    func testMalformedURLReturnsNil() throws {
        let bundle = try makeBundle([
            "SupabaseProjectURL": "not a url",
            "SupabaseAnonKey": "eyJhbGciOiJIUzI1NiJ9.anon-test-key",
        ])

        XCTAssertNil(SupabaseClientConfiguration(bundle: bundle), "URL no parseable debe traducirse a nil")
    }

    func testDirectInitializerRoundTripsValues() throws {
        let url = try XCTUnwrap(URL(string: "https://abcd1234.supabase.co"))

        let configuration = SupabaseClientConfiguration(projectURL: url, anonKey: "anon-key")

        XCTAssertEqual(configuration.projectURL, url)
        XCTAssertEqual(configuration.anonKey, "anon-key")
    }

    // MARK: - Helpers

    private func makeBundle(_ values: [String: String]) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupabaseConfigurationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.betterfishing.tests.supabase-configuration",
            "CFBundleName": "SupabaseConfigurationTests",
            "CFBundlePackageType": "BNDL",
        ]
        for (key, value) in values {
            plist[key] = value
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))

        let bundle = Bundle(url: directory)
        return try XCTUnwrap(bundle, "Debería construirse un Bundle desde el directorio temporal con Info.plist")
    }
}
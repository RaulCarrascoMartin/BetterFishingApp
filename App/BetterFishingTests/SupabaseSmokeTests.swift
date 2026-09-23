import XCTest
import Supabase

final class SupabaseSmokeTests: XCTestCase {
    func testSupabaseProductResolvesInTestTarget() {
        let clientType: Any.Type = SupabaseClient.self
        let optionsType: Any.Type = SupabaseClientOptions.self
        XCTAssertEqual("\(clientType)-\(optionsType)", "SupabaseClient-SupabaseClientOptions")
    }
}
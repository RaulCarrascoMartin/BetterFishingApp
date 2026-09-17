import Foundation

struct FishialTokenResponse: Decodable {
    let tokenType: String?
    let accessToken: String
}
import Foundation

struct Species: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let commonName: String
    let scientificName: String
    var localizedName: String?
    var referenceImageURL: URL?

    init(
        id: String,
        commonName: String,
        scientificName: String,
        localizedName: String? = nil,
        referenceImageURL: URL? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.scientificName = scientificName
        self.localizedName = localizedName
        self.referenceImageURL = referenceImageURL
    }
}
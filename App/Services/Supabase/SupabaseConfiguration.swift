import Foundation

struct SupabaseClientConfiguration: Equatable, Sendable {
    let projectURL: URL
    let anonKey: String

    init(projectURL: URL, anonKey: String) {
        self.projectURL = projectURL
        self.anonKey = anonKey
    }

    init?(bundle: Bundle = .main) {
        let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseProjectURL") as? String
        let rawKey = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String

        guard let rawURL, let rawKey else { return nil }
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else { return nil }
        guard let parsedURL = URL(string: trimmedURL),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsedURL.host?.isEmpty == false else { return nil }

        self.projectURL = parsedURL
        self.anonKey = trimmedKey
    }
}
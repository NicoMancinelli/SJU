import Foundation

/// Compares the running version against the newest GitHub Release tag.
/// This is the app's only request that doesn't go to the user's server;
/// it fetches public release metadata from the GitHub API on demand.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    @Published var status: Status = .idle

    static let releasesPage = URL(string: "https://github.com/NicoMancinelli/SJU/releases")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/NicoMancinelli/SJU/releases/latest")!

    func check(currentVersion: String) async {
        status = .checking
        do {
            var request = URLRequest(url: Self.latestAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            struct Latest: Decodable {
                let tagName: String?
                let htmlUrl: String?
                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                    case htmlUrl = "html_url"
                }
            }
            let latest = try JSONDecoder().decode(Latest.self, from: data)
            guard let tag = latest.tagName else {
                throw URLError(.cannotParseResponse)
            }
            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isVersion(latestVersion, newerThan: currentVersion) {
                let url = latest.htmlUrl.flatMap(URL.init(string:)) ?? Self.releasesPage
                status = .updateAvailable(version: latestVersion, url: url)
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed("Couldn't check for updates.")
        }
    }

    /// Numeric dotted-component comparison; non-numeric components compare as 0.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

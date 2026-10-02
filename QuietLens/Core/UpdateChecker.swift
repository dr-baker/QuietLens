import Foundation

/// Checks the GitHub releases feed for a newer version. User-initiated only —
/// no background phoning home.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noRelease
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    private static let releasesAPI = URL(string: "https://api.github.com/repos/dr-baker/QuietLens/releases/latest")
    static let releasesPage = URL(string: "https://github.com/dr-baker/QuietLens/releases")

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    func check() {
        guard state != .checking, let releasesAPI = Self.releasesAPI else { return }
        state = .checking
        Task {
            do {
                var req = URLRequest(url: releasesAPI)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, resp) = try await URLSession.shared.data(for: req)
                if (resp as? HTTPURLResponse)?.statusCode == 404 {
                    state = .noRelease
                    return
                }
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                struct Release: Decodable {
                    let tag_name: String
                    let html_url: String
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.hasPrefix("v")
                    ? String(release.tag_name.dropFirst())
                    : release.tag_name
                if Self.isVersion(latest, newerThan: currentVersion) {
                    guard let url = URL(string: release.html_url) ?? Self.releasesPage else {
                        throw URLError(.badURL)
                    }
                    state = .available(version: latest, url: url)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed
            }
        }
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

import Foundation

struct UpdateInfo: Sendable {
    let currentVersion: String
    let latestVersion: String
    let downloadURL: URL
    let releaseURL: URL
}

final class UpdateChecker: @unchecked Sendable {
    static let shared = UpdateChecker()

    private let session: URLSession
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/JeffKim-416/R2Trans/releases/latest")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdate() async -> UpdateInfo? {
        guard
            let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let currentVersion = AppVersion(currentVersionString)
        else {
            return nil
        }

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("R2Trans", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return nil
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard
                !release.draft,
                !release.prerelease,
                let latestVersion = AppVersion(release.tagName),
                latestVersion > currentVersion
            else {
                return nil
            }

            return UpdateInfo(
                currentVersion: currentVersion.description,
                latestVersion: latestVersion.description,
                downloadURL: release.downloadURL,
                releaseURL: release.htmlURL
            )
        } catch {
            return nil
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    var downloadURL: URL {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct AppVersion: Comparable, CustomStringConvertible {
    private let components: [Int]

    init?(_ rawValue: String) {
        let version = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).dropPrefix("v")
        let parts = version.split(separator: ".")

        guard parts.count == 3 else {
            return nil
        }

        let parsedParts = parts.compactMap { Int($0) }
        guard parsedParts.count == parts.count else {
            return nil
        }

        components = parsedParts
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) {
            if left != right {
                return left < right
            }
        }

        return false
    }
}

private extension String {
    func dropPrefix(_ prefix: Character) -> String {
        guard first == prefix else {
            return self
        }

        return String(dropFirst())
    }
}

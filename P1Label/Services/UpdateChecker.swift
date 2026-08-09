import Foundation

struct AppUpdate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
}

enum UpdateChecker {
    private static let latestReleaseURL = URL(
        string: "https://github.com/louis16s/P1_label/releases/latest"
    )

    static func availableUpdate(currentVersion: String) async throws -> AppUpdate? {
        guard let latestReleaseURL else { throw UpdateCheckError.invalidResponse }
        var request = URLRequest(
            url: latestReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let releaseURL = httpResponse.url,
              let latestVersion = latestVersion(fromReleaseURL: releaseURL) else {
            throw UpdateCheckError.invalidResponse
        }

        guard isVersion(latestVersion, newerThan: currentVersion) else {
            return nil
        }
        return AppUpdate(version: latestVersion, releaseURL: releaseURL)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    static func latestVersion(fromReleaseURL url: URL) -> String? {
        guard url.pathComponents.count >= 3,
              url.pathComponents.suffix(2).first == "tag" else {
            return nil
        }
        let version = normalizedVersion(url.lastPathComponent)
        return version.isEmpty ? nil : version
    }

    private static func normalizedVersion(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { component in
                let digits = component.prefix(while: \.isNumber)
                return Int(digits) ?? 0
            }
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
}

import Foundation
import Testing
@testable import P1Label

@Suite("更新版本比较")
struct UpdateCheckerTests {
    @Test("支持 v 前缀和补零比较")
    func comparesReleaseVersions() {
        #expect(UpdateChecker.isVersion("v1.0.3", newerThan: "1.0.2"))
        #expect(UpdateChecker.isVersion("1.0.10", newerThan: "1.0.2"))
        #expect(!UpdateChecker.isVersion("1.0.2", newerThan: "1.0.2"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0.0"))
    }

    @Test("从 GitHub 最新发行版跳转地址读取版本")
    func extractsRedirectedReleaseVersion() throws {
        let releaseURL = try #require(
            URL(string: "https://github.com/louis16s/P1_label/releases/tag/v1.0.2")
        )
        #expect(UpdateChecker.latestVersion(fromReleaseURL: releaseURL) == "1.0.2")
    }
}

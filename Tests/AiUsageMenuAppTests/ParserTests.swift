import Foundation
import Testing
@testable import AiUsageMenuApp

struct ParserTests {
    @Test
    func extractsAndComparesVersions() {
        #expect(VersionStore.extractVersion(from: "claude-code 2.1.90") == "2.1.90")
        #expect(VersionStore.extractVersion(from: "codex-cli 0.128.0") == "0.128.0")
        #expect(VersionComparison.isVersion("0.127.0", olderThan: "0.128.0"))
        #expect(!VersionComparison.isVersion("2.1.90", olderThan: "2.1.90"))
    }

    @Test
    func parsesGitHubReleaseUpdate() throws {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/happenings-dk/ai-usage/releases/tag/v0.2.0",
          "assets": [
            {
              "name": "AIUsageMenu-0.2.0.zip",
              "browser_download_url": "https://github.com/happenings-dk/ai-usage/releases/download/v0.2.0/AIUsageMenu-0.2.0.zip"
            }
          ]
        }
        """

        let status = try VersionStore.parseGitHubRelease(
            data: json.data(using: .utf8)!,
            currentVersion: "0.1.0",
            repository: "happenings-dk/ai-usage",
            checkedAt: DateParsing.parse("2026-05-24T16:00:00Z")!
        )

        #expect(status.latestVersion == "0.2.0")
        #expect(status.isUpdateAvailable)
        #expect(status.githubRepository == "happenings-dk/ai-usage")
        #expect(status.assetName == "AIUsageMenu-0.2.0.zip")
        #expect(status.downloadURL?.absoluteString.hasSuffix("AIUsageMenu-0.2.0.zip") == true)
    }

    @Test
    func parsesClaudeRateLimitCache() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("ai-usage-rate-limits.json")
        let json = """
        {
          "updated_at": "2026-05-24T16:00:00Z",
          "source": "claude-statusline",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 23.5,
              "resets_at": 1780000000
            },
            "seven_day": {
              "used_percentage": 41.2,
              "resets_at": 1780500000
            }
          }
        }
        """
        try json.data(using: .utf8)!.write(to: file)

        let parsed = try ClaudeRateLimitCacheParser.parse(file: file)
        let snapshot = try #require(parsed)

        #expect(snapshot.updatedAt == DateParsing.parse("2026-05-24T16:00:00Z"))
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].name == "5h")
        #expect(snapshot.windows[0].usedPercent == 23.5)
        #expect(snapshot.windows[0].windowMinutes == 300)
        #expect(snapshot.windows[1].name == "Weekly")
        #expect(snapshot.windows[1].usedPercent == 41.2)
        #expect(snapshot.windows[1].windowMinutes == 10_080)
    }

    @Test
    func parsesGeminiSessionTokens() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("chats")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("session-2026-05-24T18-00-test.json")
        let json = """
        {
          "sessionId": "session-id",
          "messages": [
            {
              "id": "message-id",
              "timestamp": "2026-05-24T16:00:00.000Z",
              "type": "gemini",
              "tokens": {
                "input": 100,
                "output": 20,
                "cached": 7,
                "thoughts": 3,
                "tool": 5,
                "total": 135
              },
              "model": "gemini-3-flash-preview"
            }
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: file)

        let events = try GeminiUsageParser.parse(file: file)

        #expect(events.count == 1)
        #expect(events[0].source == .gemini)
        #expect(events[0].usage.input == 100)
        #expect(events[0].usage.cachedInput == 7)
        #expect(events[0].usage.output == 25)
        #expect(events[0].usage.reasoningOutput == 3)
        #expect(events[0].usage.billableApproximation == 128)
    }
}

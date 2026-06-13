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
    func parsesGrokUpdateCheck() {
        let json = """
        {
          "currentVersion": "0.2.51",
          "latestVersion": "0.2.52",
          "updateAvailable": true,
          "installer": "internal",
          "channel": "stable",
          "error": null
        }
        """

        #expect(VersionStore.parseGrokLatestVersion(from: json) == "0.2.52")
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

    @Test
    func parsesGrokSignals() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("session-id")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let summary = """
        {
          "info": {
            "id": "session-id",
            "cwd": "/Users/example/project"
          },
          "updated_at": "2026-06-12T18:11:12.565418Z",
          "last_active_at": "2026-06-12T18:11:12.533300Z",
          "current_model_id": "grok-build"
        }
        """
        try summary.data(using: .utf8)!.write(to: directory.appendingPathComponent("summary.json"))

        let signals = """
        {
          "turnCount": 3,
          "contextTokensUsed": 153431,
          "contextWindowUsage": 29,
          "contextWindowTokens": 512000,
          "toolCallCount": 89,
          "toolFailureCount": 3,
          "errorCount": 2,
          "avgResponseTimeMs": 22865,
          "avgTimeToFirstTokenMs": 2839,
          "primaryModelId": "grok-build"
        }
        """
        let signalsFile = directory.appendingPathComponent("signals.json")
        try signals.data(using: .utf8)!.write(to: signalsFile)

        let parsed = try #require(try GrokUsageParser.parse(signalsFile: signalsFile))
        let event = parsed.event

        #expect(event.id == "grok-session-id")
        #expect(event.source == .grok)
        #expect(event.usage.input == 153431)
        #expect(event.usage.billableApproximation == 153431)
        #expect(event.model == "grok-build")
        #expect(event.project == "/Users/example/project")
        #expect(event.timestamp == DateParsing.parse("2026-06-12T18:11:12.533300Z"))
        #expect(parsed.contextWindowUsage == 29)
        #expect(parsed.contextWindowTokens == 512000)
        #expect(parsed.turnCount == 3)
        #expect(parsed.toolCallCount == 89)
        #expect(parsed.toolFailureCount == 3)
        #expect(parsed.errorCount == 2)
        #expect(parsed.avgResponseTimeMs == 22865)
        #expect(parsed.avgTimeToFirstTokenMs == 2839)
    }
}

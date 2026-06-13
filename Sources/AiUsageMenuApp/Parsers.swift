import Foundation

enum ClaudeUsageParser {
    static func parse(line: String, fallbackProject: String?) -> UsageEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let timestamp = DateParsing.parse(object["timestamp"] as? String),
              let message = object["message"] as? [String: Any],
              let usageObject = message["usage"] as? [String: Any] else {
            return nil
        }

        let messageID = message["id"] as? String
        let uuid = object["uuid"] as? String
        let requestID = object["requestId"] as? String
        let id = messageID ?? uuid ?? requestID ?? UUID().uuidString

        let usage = TokenUsage(
            input: usageObject.int("input_tokens"),
            cachedInput: usageObject.int("cache_read_input_tokens"),
            cacheCreationInput: usageObject.int("cache_creation_input_tokens"),
            output: usageObject.int("output_tokens"),
            reasoningOutput: 0
        )

        guard usage.total > 0 else {
            return nil
        }

        return UsageEvent(
            id: "claude-\(id)",
            source: .claude,
            timestamp: timestamp,
            usage: usage,
            model: message["model"] as? String,
            project: object["cwd"] as? String ?? fallbackProject
        )
    }
}

enum ClaudeRateLimitCacheParser {
    static func parse(file: URL) throws -> RateLimitSnapshot? {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = object["rate_limits"] as? [String: Any] else {
            return nil
        }

        let fileModifiedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        let updatedAt = DateParsing.parse(object["updated_at"] as? String) ?? fileModifiedAt

        let windows = [
            parseWindow(name: "5h", windowMinutes: 5 * 60, object: rateLimits["five_hour"] as? [String: Any]),
            parseWindow(name: "Weekly", windowMinutes: 7 * 24 * 60, object: rateLimits["seven_day"] as? [String: Any])
        ].compactMap { $0 }

        return RateLimitSnapshot(updatedAt: updatedAt, windows: windows)
    }

    private static func parseWindow(name: String, windowMinutes: Int, object: [String: Any]?) -> RateLimitWindow? {
        guard let object,
              let resetsAt = parseResetDate(object["resets_at"]) else {
            return nil
        }

        return RateLimitWindow(
            name: name,
            usedPercent: object.double("used_percentage", fallbackKey: "used_percent"),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func parseResetDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: normalizedEpochSeconds(seconds))
        }
        if let seconds = value as? Int {
            return Date(timeIntervalSince1970: normalizedEpochSeconds(Double(seconds)))
        }
        if let string = value as? String {
            if let seconds = Double(string) {
                return Date(timeIntervalSince1970: normalizedEpochSeconds(seconds))
            }
            return DateParsing.parse(string)
        }
        return nil
    }

    private static func normalizedEpochSeconds(_ value: Double) -> Double {
        if value > 10_000_000_000 {
            return value / 1000
        }
        return value
    }
}

struct CodexParsedLine {
    let timestamp: Date
    let event: UsageEvent?
    let rateLimits: [RateLimitWindow]
}

enum CodexUsageParser {
    static func parse(line: String, fallbackSessionID: String) -> CodexParsedLine? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = DateParsing.parse(object["timestamp"] as? String),
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count" else {
            return nil
        }

        var event: UsageEvent?
        if let info = payload["info"] as? [String: Any],
           let totalUsage = info["total_token_usage"] as? [String: Any] {
            let usage = TokenUsage(
                input: totalUsage.int("input_tokens"),
                cachedInput: totalUsage.int("cached_input_tokens"),
                cacheCreationInput: 0,
                output: totalUsage.int("output_tokens"),
                reasoningOutput: totalUsage.int("reasoning_output_tokens")
            )

            if usage.total > 0 {
                event = UsageEvent(
                    id: "codex-\(fallbackSessionID)",
                    source: .codex,
                    timestamp: timestamp,
                    usage: usage,
                    model: nil,
                    project: nil
                )
            }
        }

        return CodexParsedLine(
            timestamp: timestamp,
            event: event,
            rateLimits: parseRateLimits(payload["rate_limits"] as? [String: Any])
        )
    }

    private static func parseRateLimits(_ object: [String: Any]?) -> [RateLimitWindow] {
        guard let object else {
            return []
        }

        return [
            parseWindow(name: "5h", object: object["primary"] as? [String: Any]),
            parseWindow(name: "Weekly", object: object["secondary"] as? [String: Any])
        ].compactMap { $0 }
    }

    private static func parseWindow(name: String, object: [String: Any]?) -> RateLimitWindow? {
        guard let object,
              let resetSeconds = object.number("resets_at"),
              resetSeconds > 0 else {
            return nil
        }

        return RateLimitWindow(
            name: name,
            usedPercent: object.double("used_percent"),
            windowMinutes: object.int("window_minutes"),
            resetsAt: Date(timeIntervalSince1970: resetSeconds)
        )
    }
}

enum GeminiUsageParser {
    static func parse(file: URL) throws -> [UsageEvent] {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]] else {
            return []
        }

        let sessionID = object["sessionId"] as? String ?? file.deletingPathExtension().lastPathComponent
        let project = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent

        return messages.compactMap { message in
            parseMessage(message, sessionID: sessionID, project: project)
        }
    }

    private static func parseMessage(_ message: [String: Any], sessionID: String, project: String?) -> UsageEvent? {
        guard message["type"] as? String == "gemini",
              let timestamp = DateParsing.parse(message["timestamp"] as? String),
              let tokens = message["tokens"] as? [String: Any] else {
            return nil
        }

        let usage = TokenUsage(
            input: tokens.int("input"),
            cachedInput: tokens.int("cached"),
            cacheCreationInput: 0,
            output: tokens.int("output") + tokens.int("tool"),
            reasoningOutput: tokens.int("thoughts")
        )

        guard usage.total > 0 else {
            return nil
        }

        let id = message["id"] as? String ?? "\(sessionID)-\(timestamp.timeIntervalSince1970)"
        return UsageEvent(
            id: "gemini-\(sessionID)-\(id)",
            source: .gemini,
            timestamp: timestamp,
            usage: usage,
            model: message["model"] as? String,
            project: project
        )
    }
}

struct GrokParsedSignals: Equatable {
    let event: UsageEvent
    let contextWindowUsage: Double?
    let contextWindowTokens: Int?
    let turnCount: Int?
    let toolCallCount: Int?
    let toolFailureCount: Int?
    let errorCount: Int?
    let avgResponseTimeMs: Int?
    let avgTimeToFirstTokenMs: Int?
}

enum GrokUsageParser {
    static func parse(signalsFile: URL) throws -> GrokParsedSignals? {
        let data = try Data(contentsOf: signalsFile, options: [.mappedIfSafe])
        guard let signals = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let sessionDirectory = signalsFile.deletingLastPathComponent()
        let summary = (try? parseSummary(file: sessionDirectory.appendingPathComponent("summary.json"))) ?? [:]

        let usage = TokenUsage(
            input: signals.int("contextTokensUsed"),
            cachedInput: 0,
            cacheCreationInput: 0,
            output: 0,
            reasoningOutput: 0
        )

        guard usage.total > 0 else {
            return nil
        }

        let fileModifiedAt = (try? signalsFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let timestamp = DateParsing.parse(summary["last_active_at"] as? String) ??
            DateParsing.parse(summary["updated_at"] as? String) ??
            fileModifiedAt ??
            Date.distantPast

        let id = summary.string("id", nestedUnder: "info") ?? sessionDirectory.lastPathComponent
        let model = signals["primaryModelId"] as? String ?? summary["current_model_id"] as? String
        let project = summary.string("cwd", nestedUnder: "info") ?? summary["git_root_dir"] as? String

        let event = UsageEvent(
            id: "grok-\(id)",
            source: .grok,
            timestamp: timestamp,
            usage: usage,
            model: model,
            project: project
        )

        return GrokParsedSignals(
            event: event,
            contextWindowUsage: signals.optionalDouble("contextWindowUsage"),
            contextWindowTokens: signals.optionalInt("contextWindowTokens"),
            turnCount: signals.optionalInt("turnCount"),
            toolCallCount: signals.optionalInt("toolCallCount"),
            toolFailureCount: signals.optionalInt("toolFailureCount"),
            errorCount: signals.optionalInt("errorCount"),
            avgResponseTimeMs: signals.optionalInt("avgResponseTimeMs"),
            avgTimeToFirstTokenMs: signals.optionalInt("avgTimeToFirstTokenMs")
        )
    }

    private static func parseSummary(file: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

enum DateParsing {
    static func parse(_ string: String?) -> Date? {
        guard let string else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func optionalInt(_ key: String) -> Int? {
        if let int = self[key] as? Int {
            return int
        }
        if let double = self[key] as? Double {
            return Int(double)
        }
        if let string = self[key] as? String {
            return Int(string)
        }
        return nil
    }

    func int(_ key: String) -> Int {
        if let int = self[key] as? Int {
            return int
        }
        if let double = self[key] as? Double {
            return Int(double)
        }
        if let string = self[key] as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    func double(_ key: String) -> Double {
        double(key, fallbackKey: nil)
    }

    func optionalDouble(_ key: String) -> Double? {
        if let double = self[key] as? Double {
            return double
        }
        if let int = self[key] as? Int {
            return Double(int)
        }
        if let string = self[key] as? String {
            return Double(string)
        }
        return nil
    }

    func double(_ key: String, fallbackKey: String?) -> Double {
        let keys = [key, fallbackKey].compactMap { $0 }
        for key in keys {
            if let double = self[key] as? Double {
                return double
            }
            if let int = self[key] as? Int {
                return Double(int)
            }
            if let string = self[key] as? String {
                return Double(string) ?? 0
            }
        }
        return 0
    }

    func number(_ key: String) -> Double? {
        if let double = self[key] as? Double {
            return double
        }
        if let int = self[key] as? Int {
            return Double(int)
        }
        if let string = self[key] as? String {
            return Double(string) ?? 0
        }
        return 0
    }

    func string(_ key: String, nestedUnder parentKey: String) -> String? {
        guard let parent = self[parentKey] as? [String: Any] else {
            return nil
        }
        return parent[key] as? String
    }
}

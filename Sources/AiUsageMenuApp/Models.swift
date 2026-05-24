import Foundation

enum UsageSource: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"
    case gemini = "Gemini"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .claude:
            "sparkles"
        case .codex:
            "terminal"
        case .gemini:
            "diamond"
        }
    }
}

struct TokenUsage: Codable, Equatable {
    var input: Int
    var cachedInput: Int
    var cacheCreationInput: Int
    var output: Int
    var reasoningOutput: Int

    static let zero = TokenUsage(
        input: 0,
        cachedInput: 0,
        cacheCreationInput: 0,
        output: 0,
        reasoningOutput: 0
    )

    var total: Int {
        input + cachedInput + cacheCreationInput + output + reasoningOutput
    }

    var billableApproximation: Int {
        input + cacheCreationInput + output + reasoningOutput
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            cacheCreationInput: lhs.cacheCreationInput + rhs.cacheCreationInput,
            output: lhs.output + rhs.output,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput
        )
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}

struct UsageEvent: Identifiable, Equatable {
    let id: String
    let source: UsageSource
    let timestamp: Date
    let usage: TokenUsage
    let model: String?
    let project: String?
}

struct RateLimitWindow: Equatable {
    let name: String
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date
}

struct RateLimitSnapshot: Equatable {
    let updatedAt: Date
    let windows: [RateLimitWindow]
}

struct ProjectUsage: Identifiable, Equatable {
    let name: String
    let usage: TokenUsage
    let eventCount: Int

    var id: String { name }
}

struct CLIVersionStatus: Identifiable, Equatable {
    let source: UsageSource
    let installedVersion: String?
    let latestVersion: String?
    let packageName: String
    let updateCommand: String
    let checkedAt: Date?
    let error: String?

    var id: UsageSource { source }

    var isOutdated: Bool {
        guard let installedVersion, let latestVersion else {
            return false
        }
        return VersionComparison.isVersion(installedVersion, olderThan: latestVersion)
    }
}

struct AppUpdateStatus: Equatable {
    let currentVersion: String
    let latestVersion: String?
    let downloadURL: URL?
    let releasePageURL: URL?
    let feedURL: URL?
    let githubRepository: String?
    let assetName: String?
    let checkedAt: Date?
    let error: String?

    var isConfigured: Bool {
        feedURL != nil || githubRepository != nil
    }

    var isUpdateAvailable: Bool {
        guard let latestVersion else {
            return false
        }
        return VersionComparison.isVersion(currentVersion, olderThan: latestVersion)
    }

    static let empty = AppUpdateStatus(
        currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
        latestVersion: nil,
        downloadURL: nil,
        releasePageURL: nil,
        feedURL: nil,
        githubRepository: nil,
        assetName: nil,
        checkedAt: nil,
        error: nil
    )
}

struct SourceUsageSummary: Equatable {
    let source: UsageSource
    let scannedFiles: Int
    let eventCount: Int
    let currentWindowEventCount: Int
    let currentWindowUsage: TokenUsage
    let todayUsage: TokenUsage
    let weekUsage: TokenUsage
    let lastEventAt: Date?
    let latestModel: String?
    let latestProject: String?
    let estimatedResetAt: Date?
    let estimatedWeeklyResetAt: Date?
    let rateLimits: [RateLimitWindow]
    let rateLimitUpdatedAt: Date?
    let topProjects: [ProjectUsage]
    let warning: String?

    static func empty(source: UsageSource) -> SourceUsageSummary {
        SourceUsageSummary(
            source: source,
            scannedFiles: 0,
            eventCount: 0,
            currentWindowEventCount: 0,
            currentWindowUsage: .zero,
            todayUsage: .zero,
            weekUsage: .zero,
            lastEventAt: nil,
            latestModel: nil,
            latestProject: nil,
            estimatedResetAt: nil,
            estimatedWeeklyResetAt: nil,
            rateLimits: [],
            rateLimitUpdatedAt: nil,
            topProjects: [],
            warning: nil
        )
    }

    var primaryPercent: Double? {
        rateLimits.first?.usedPercent
    }

    var hasActivity: Bool {
        eventCount > 0 ||
            currentWindowUsage.total > 0 ||
            todayUsage.total > 0 ||
            weekUsage.total > 0 ||
            !rateLimits.isEmpty
    }
}

struct UsageSnapshot: Equatable {
    let generatedAt: Date
    let summaries: [SourceUsageSummary]
    let cliVersions: [CLIVersionStatus]
    let appUpdate: AppUpdateStatus

    static let empty = UsageSnapshot(
        generatedAt: Date.distantPast,
        summaries: UsageSource.allCases.map(SourceUsageSummary.empty),
        cliVersions: [],
        appUpdate: .empty
    )

    func summary(for source: UsageSource) -> SourceUsageSummary {
        summaries.first { $0.source == source } ?? .empty(source: source)
    }

    var tightestLimit: (source: UsageSource, window: RateLimitWindow)? {
        summaries
            .flatMap { summary in
                summary.rateLimits.map { (source: summary.source, window: $0) }
            }
            .max { lhs, rhs in
                lhs.window.usedPercent < rhs.window.usedPercent
            }
    }

    func plainTextSummary() -> String {
        var lines = ["AI Usage", "Updated \(TimeFormat.exact(generatedAt))", ""]

        for summary in summaries {
            lines.append("\(summary.source.rawValue)")
            lines.append("5h billable: \(NumberFormat.compact(summary.currentWindowUsage.billableApproximation))")
            lines.append("Today billable: \(NumberFormat.compact(summary.todayUsage.billableApproximation))")
            lines.append("7d billable: \(NumberFormat.compact(summary.weekUsage.billableApproximation))")
            lines.append("Cached: \(NumberFormat.compact(summary.currentWindowUsage.cachedInput))")

            if summary.rateLimits.isEmpty {
                lines.append("5h reset: \(TimeFormat.reset(summary.estimatedResetAt))")
                lines.append("Weekly reset: \(TimeFormat.reset(summary.estimatedWeeklyResetAt))")
            } else {
                for limit in summary.rateLimits {
                    let remaining = max(0, 100 - limit.usedPercent)
                    lines.append("\(limit.name): \(NumberFormat.percent(limit.usedPercent)) used, \(NumberFormat.percent(remaining)) left, resets \(TimeFormat.reset(limit.resetsAt))")
                }
            }

            if let firstProject = summary.topProjects.first {
                lines.append("Top project: \(firstProject.name) \(NumberFormat.compact(firstProject.usage.billableApproximation))")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

enum VersionComparison {
    static func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericParts(lhs)
        let rhsParts = numericParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func numericParts(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .prefix(4)
            .map { Int($0) ?? 0 }
    }
}

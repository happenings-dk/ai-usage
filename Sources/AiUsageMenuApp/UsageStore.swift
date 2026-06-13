import Foundation

final class UsageStore {
    private let maxBytesPerTranscript = 512 * 1024
    private let maxFilesPerSource = 120

    func loadSnapshot(now: Date) throws -> UsageSnapshot {
        let summaries = loadUsageSummaries(now: now)
        let versionSnapshot = VersionStore().load(now: now)
        return UsageSnapshot(
            generatedAt: now,
            summaries: summaries,
            cliVersions: versionSnapshot.cliVersions,
            appUpdate: versionSnapshot.appUpdate
        )
    }

    func loadUsageSummaries(now: Date) -> [SourceUsageSummary] {
        let claude = loadClaudeSummary(now: now)
        let codex = loadCodexSummary(now: now)
        let gemini = loadGeminiSummary(now: now)
        let grok = loadGrokSummary(now: now)
        return [claude, codex, gemini, grok]
    }

    private func loadClaudeSummary(now: Date) -> SourceUsageSummary {
        let root = URL(fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath)
        let rateLimitSnapshot = loadClaudeRateLimitSnapshot(now: now)
        guard FileManager.default.fileExists(atPath: root.path) else {
            var empty = SourceUsageSummary.empty(source: .claude)
            if let rateLimitSnapshot {
                empty = SourceUsageSummary(
                    source: .claude,
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
                    rateLimits: rateLimitSnapshot.windows,
                    rateLimitUpdatedAt: rateLimitSnapshot.updatedAt,
                    topProjects: [],
                    extraDetails: [],
                    warning: nil
                )
            }
            return empty
        }

        do {
            var events: [UsageEvent] = []
            var scannedFiles = 0
            var seenMessageIDs = Set<String>()
            let cutoff = now.addingTimeInterval(-8 * 24 * 60 * 60)

            for file in jsonlFiles(under: root, modifiedAfter: cutoff) {
                scannedFiles += 1
                try autoreleasepool {
                    try scanLines(file: file) { line in
                        guard let event = ClaudeUsageParser.parse(line: line, fallbackProject: file.deletingLastPathComponent().lastPathComponent) else {
                            return
                        }
                        guard seenMessageIDs.insert(event.id).inserted else {
                            return
                        }
                        events.append(event)
                    }
                }
            }

            return summarize(
                events: events,
                source: .claude,
                scannedFiles: scannedFiles,
                now: now,
                rateLimits: rateLimitSnapshot?.windows ?? [],
                rateLimitUpdatedAt: rateLimitSnapshot?.updatedAt
            )
        } catch {
            return SourceUsageSummary(
                source: .claude,
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
                extraDetails: [],
                warning: error.localizedDescription
            )
        }
    }

    private func loadCodexSummary(now: Date) -> SourceUsageSummary {
        let root = URL(fileURLWithPath: NSString(string: "~/.codex/sessions").expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return SourceUsageSummary.empty(source: .codex)
        }

        do {
            var latestEventBySession = [String: UsageEvent]()
            var latestRateLimits: (timestamp: Date, windows: [RateLimitWindow])?
            var scannedFiles = 0
            let cutoff = now.addingTimeInterval(-8 * 24 * 60 * 60)

            for file in jsonlFiles(under: root, modifiedAfter: cutoff) {
                scannedFiles += 1
                try autoreleasepool {
                    try scanLines(file: file) { line in
                        guard let parsed = CodexUsageParser.parse(line: line, fallbackSessionID: file.deletingPathExtension().lastPathComponent) else {
                            return
                        }

                        if let event = parsed.event {
                            latestEventBySession[event.id] = event
                        }

                        if !parsed.rateLimits.isEmpty {
                            let timestamp = parsed.timestamp
                            if latestRateLimits == nil || timestamp > latestRateLimits!.timestamp {
                                latestRateLimits = (timestamp, parsed.rateLimits)
                            }
                        }
                    }
                }
            }

            let events = Array(latestEventBySession.values)
            return summarize(
                events: events,
                source: .codex,
                scannedFiles: scannedFiles,
                now: now,
                rateLimits: latestRateLimits?.windows ?? [],
                rateLimitUpdatedAt: latestRateLimits?.timestamp
            )
        } catch {
            return SourceUsageSummary(
                source: .codex,
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
                extraDetails: [],
                warning: error.localizedDescription
            )
        }
    }

    private func loadGeminiSummary(now: Date) -> SourceUsageSummary {
        let root = URL(fileURLWithPath: NSString(string: "~/.gemini/tmp").expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return SourceUsageSummary.empty(source: .gemini)
        }

        do {
            var events: [UsageEvent] = []
            var scannedFiles = 0
            let cutoff = now.addingTimeInterval(-8 * 24 * 60 * 60)

            for file in geminiSessionFiles(under: root, modifiedAfter: cutoff) {
                scannedFiles += 1
                try autoreleasepool {
                    events.append(contentsOf: try GeminiUsageParser.parse(file: file))
                }
            }

            return summarize(
                events: events,
                source: .gemini,
                scannedFiles: scannedFiles,
                now: now,
                rateLimits: [],
                rateLimitUpdatedAt: nil
            )
        } catch {
            return SourceUsageSummary(
                source: .gemini,
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
                extraDetails: [],
                warning: error.localizedDescription
            )
        }
    }

    private func loadGrokSummary(now: Date) -> SourceUsageSummary {
        let root = URL(fileURLWithPath: NSString(string: "~/.grok/sessions").expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return SourceUsageSummary.empty(source: .grok)
        }

        do {
            var parsedSignals: [GrokParsedSignals] = []
            var scannedFiles = 0
            let cutoff = now.addingTimeInterval(-8 * 24 * 60 * 60)

            for file in grokSignalFiles(under: root, modifiedAfter: cutoff) {
                scannedFiles += 1
                try autoreleasepool {
                    if let parsed = try GrokUsageParser.parse(signalsFile: file) {
                        parsedSignals.append(parsed)
                    }
                }
            }

            let latestSignals = parsedSignals.max { $0.event.timestamp < $1.event.timestamp }
            return summarize(
                events: parsedSignals.map(\.event),
                source: .grok,
                scannedFiles: scannedFiles,
                now: now,
                rateLimits: [],
                rateLimitUpdatedAt: nil,
                extraDetails: latestSignals.map(grokDetails) ?? []
            )
        } catch {
            return SourceUsageSummary(
                source: .grok,
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
                extraDetails: [],
                warning: error.localizedDescription
            )
        }
    }

    private func summarize(
        events: [UsageEvent],
        source: UsageSource,
        scannedFiles: Int,
        now: Date,
        rateLimits: [RateLimitWindow],
        rateLimitUpdatedAt: Date?,
        extraDetails: [SourceUsageDetail] = []
    ) -> SourceUsageSummary {
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let startOfDay = Calendar.autoupdatingCurrent.startOfDay(for: now)

        let currentEvents = events.filter { $0.timestamp >= fiveHoursAgo }
        let todayEvents = events.filter { $0.timestamp >= startOfDay }
        let weekEvents = events.filter { $0.timestamp >= sevenDaysAgo }

        let lastEventAt = events.map(\.timestamp).max()
        let latestEvent = events.max { $0.timestamp < $1.timestamp }
        let estimatedResetAt: Date?
        if let firstCurrentEvent = currentEvents.map(\.timestamp).min() {
            estimatedResetAt = firstCurrentEvent.addingTimeInterval(5 * 60 * 60)
        } else {
            estimatedResetAt = nil
        }

        let estimatedWeeklyResetAt: Date?
        if let firstWeekEvent = weekEvents.map(\.timestamp).min() {
            estimatedWeeklyResetAt = firstWeekEvent.addingTimeInterval(7 * 24 * 60 * 60)
        } else {
            estimatedWeeklyResetAt = nil
        }
        let topProjects = summarizeProjects(events: weekEvents)

        return SourceUsageSummary(
            source: source,
            scannedFiles: scannedFiles,
            eventCount: events.count,
            currentWindowEventCount: currentEvents.count,
            currentWindowUsage: currentEvents.reduce(.zero) { $0 + $1.usage },
            todayUsage: todayEvents.reduce(.zero) { $0 + $1.usage },
            weekUsage: weekEvents.reduce(.zero) { $0 + $1.usage },
            lastEventAt: lastEventAt,
            latestModel: latestEvent?.model,
            latestProject: latestEvent?.project,
            estimatedResetAt: estimatedResetAt,
            estimatedWeeklyResetAt: estimatedWeeklyResetAt,
            rateLimits: rateLimits,
            rateLimitUpdatedAt: rateLimitUpdatedAt,
            topProjects: topProjects,
            extraDetails: extraDetails,
            warning: nil
        )
    }

    private func grokDetails(from parsed: GrokParsedSignals) -> [SourceUsageDetail] {
        var details: [SourceUsageDetail] = []

        if let contextWindowUsage = parsed.contextWindowUsage {
            let value: String
            if let contextWindowTokens = parsed.contextWindowTokens {
                value = "\(NumberFormat.percent(contextWindowUsage)) of \(NumberFormat.compact(contextWindowTokens))"
            } else {
                value = NumberFormat.percent(contextWindowUsage)
            }
            details.append(SourceUsageDetail(title: "Context window", value: value))
        } else if let contextWindowTokens = parsed.contextWindowTokens {
            details.append(SourceUsageDetail(title: "Context window", value: NumberFormat.compact(contextWindowTokens)))
        }

        if let turnCount = parsed.turnCount {
            details.append(SourceUsageDetail(title: "Turns", value: NumberFormat.compact(turnCount)))
        }

        if let toolCallCount = parsed.toolCallCount {
            var value = "\(NumberFormat.compact(toolCallCount)) calls"
            if let toolFailureCount = parsed.toolFailureCount, toolFailureCount > 0 {
                value += ", \(NumberFormat.compact(toolFailureCount)) failed"
            }
            details.append(SourceUsageDetail(title: "Tools", value: value))
        }

        if let errorCount = parsed.errorCount, errorCount > 0 {
            details.append(SourceUsageDetail(title: "Errors", value: NumberFormat.compact(errorCount)))
        }

        if let avgResponseTimeMs = parsed.avgResponseTimeMs {
            details.append(SourceUsageDetail(title: "Avg response", value: TimeFormat.compactMilliseconds(avgResponseTimeMs)))
        }

        if let avgTimeToFirstTokenMs = parsed.avgTimeToFirstTokenMs {
            details.append(SourceUsageDetail(title: "First token", value: TimeFormat.compactMilliseconds(avgTimeToFirstTokenMs)))
        }

        return details
    }

    private func summarizeProjects(events: [UsageEvent]) -> [ProjectUsage] {
        struct Accumulator {
            var usage = TokenUsage.zero
            var eventCount = 0
        }

        var usageByProject = [String: Accumulator]()
        for event in events {
            let project = displayProjectName(event.project)
            var accumulator = usageByProject[project] ?? Accumulator()
            accumulator.usage += event.usage
            accumulator.eventCount += 1
            usageByProject[project] = accumulator
        }

        return usageByProject
            .map { name, accumulator in
                ProjectUsage(name: name, usage: accumulator.usage, eventCount: accumulator.eventCount)
            }
            .sorted {
                if $0.usage.billableApproximation == $1.usage.billableApproximation {
                    return $0.name < $1.name
                }
                return $0.usage.billableApproximation > $1.usage.billableApproximation
            }
            .prefix(3)
            .map { $0 }
    }

    private func displayProjectName(_ project: String?) -> String {
        guard let project, !project.isEmpty else {
            return "Unknown"
        }

        let url = URL(fileURLWithPath: project)
        let name = url.lastPathComponent
        return name.isEmpty ? project : name
    }

    private func loadClaudeRateLimitSnapshot(now: Date) -> RateLimitSnapshot? {
        let file = URL(fileURLWithPath: NSString(string: "~/.claude/ai-usage-rate-limits.json").expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }

        do {
            guard let snapshot = try ClaudeRateLimitCacheParser.parse(file: file),
                  !snapshot.windows.isEmpty else {
                return nil
            }

            let oldestUsefulUpdate = now.addingTimeInterval(-24 * 60 * 60)
            guard snapshot.updatedAt >= oldestUsefulUpdate else {
                return nil
            }

            return snapshot
        } catch {
            return nil
        }
    }

    private func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else {
                continue
            }

            do {
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else {
                    continue
                }
                guard let modified = values.contentModificationDate else {
                    continue
                }
                if modified < cutoff {
                    continue
                }
                files.append((file, modified))
            } catch {
                continue
            }
        }
        return files
            .sorted { $0.modified > $1.modified }
            .prefix(maxFilesPerSource)
            .map(\.url)
    }

    private func geminiSessionFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "json",
                  file.lastPathComponent.hasPrefix("session-"),
                  file.deletingLastPathComponent().lastPathComponent == "chats" else {
                continue
            }

            do {
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else {
                    continue
                }
                guard let modified = values.contentModificationDate else {
                    continue
                }
                if modified < cutoff {
                    continue
                }
                files.append((file, modified))
            } catch {
                continue
            }
        }
        return files
            .sorted { $0.modified > $1.modified }
            .prefix(maxFilesPerSource)
            .map(\.url)
    }

    private func grokSignalFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let file as URL in enumerator {
            guard file.lastPathComponent == "signals.json" else {
                continue
            }

            do {
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else {
                    continue
                }
                guard let modified = values.contentModificationDate else {
                    continue
                }
                if modified < cutoff {
                    continue
                }
                files.append((file, modified))
            } catch {
                continue
            }
        }
        return files
            .sorted { $0.modified > $1.modified }
            .prefix(maxFilesPerSource)
            .map(\.url)
    }

    private func scanLines(file: URL, handleLine: (String) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        if fileSize > UInt64(maxBytesPerTranscript) {
            try handle.seek(toOffset: fileSize - UInt64(maxBytesPerTranscript))
            _ = try handle.read(upToCount: 64 * 1024)
        } else {
            try handle.seek(toOffset: 0)
        }

        let newline = Data([0x0A])
        var buffer = Data()

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }

            buffer.append(chunk)
            while let range = buffer.firstRange(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)

                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                    continue
                }
                try handleLine(line)
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            try handleLine(line)
        }
    }
}

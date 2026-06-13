import Foundation

struct VersionSnapshot: Equatable {
    let cliVersions: [CLIVersionStatus]
    let appUpdate: AppUpdateStatus
}

final class VersionStore {
    private struct ToolDefinition {
        let source: UsageSource
        let executable: String
        let latestVersionProvider: LatestVersionProvider
        let updateCommand: String
    }

    private enum LatestVersionProvider {
        case npm(packageName: String)
        case grokUpdateCheck

        var packageName: String {
            switch self {
            case .npm(let packageName):
                packageName
            case .grokUpdateCheck:
                "grok"
            }
        }
    }

    private let tools = [
        ToolDefinition(
            source: .claude,
            executable: "claude",
            latestVersionProvider: .npm(packageName: "@anthropic-ai/claude-code"),
            updateCommand: "npm install -g @anthropic-ai/claude-code"
        ),
        ToolDefinition(
            source: .codex,
            executable: "codex",
            latestVersionProvider: .npm(packageName: "@openai/codex"),
            updateCommand: "npm install -g @openai/codex"
        ),
        ToolDefinition(
            source: .gemini,
            executable: "gemini",
            latestVersionProvider: .npm(packageName: "@google/gemini-cli"),
            updateCommand: "npm install -g @google/gemini-cli"
        ),
        ToolDefinition(
            source: .grok,
            executable: "grok",
            latestVersionProvider: .grokUpdateCheck,
            updateCommand: "grok update"
        )
    ]

    func load(now: Date) -> VersionSnapshot {
        VersionSnapshot(
            cliVersions: tools.map { loadToolVersion($0, now: now) },
            appUpdate: loadAppUpdate(now: now)
        )
    }

    private func loadToolVersion(_ tool: ToolDefinition, now: Date) -> CLIVersionStatus {
        let installedResult = CommandRunner.run(tool.executable, ["--version"], timeout: 2)
        let latestResult = loadLatestVersion(tool.latestVersionProvider)

        let installedVersion = VersionStore.extractVersion(from: installedResult.output)
        let latestVersion = VersionStore.extractVersion(from: latestResult.output)

        var errors: [String] = []
        if installedVersion == nil {
            errors.append(installedResult.error ?? "Not installed")
        }
        if latestVersion == nil {
            errors.append(latestResult.error ?? "Latest unavailable")
        }

        return CLIVersionStatus(
            source: tool.source,
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            packageName: tool.latestVersionProvider.packageName,
            updateCommand: tool.updateCommand,
            checkedAt: now,
            error: errors.isEmpty ? nil : errors.joined(separator: "; ")
        )
    }

    private func loadLatestVersion(_ provider: LatestVersionProvider) -> CommandRunner.Result {
        switch provider {
        case .npm(let packageName):
            return CommandRunner.run("npm", ["view", packageName, "version"], timeout: 4)
        case .grokUpdateCheck:
            let result = CommandRunner.run("grok", ["update", "--check", "--json"], timeout: 6)
            if let version = VersionStore.parseGrokLatestVersion(from: result.output) {
                return CommandRunner.Result(output: version, error: result.error)
            }
            return result
        }
    }

    private func loadAppUpdate(now: Date) -> AppUpdateStatus {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        if let githubRepository = configuredGitHubRepository() {
            return loadGitHubUpdate(repository: githubRepository, currentVersion: currentVersion, now: now)
        }

        guard let feedURL = configuredFeedURL() else {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: nil,
                downloadURL: nil,
                releasePageURL: nil,
                feedURL: nil,
                githubRepository: nil,
                assetName: nil,
                checkedAt: now,
                error: "No GitHub repo or feed configured"
            )
        }

        do {
            let data = try fetch(url: feedURL, timeout: 4)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VersionStoreError.invalidFeed
            }

            let latestVersion = object["version"] as? String
            let downloadURLString = object["download_url"] as? String ?? object["downloadURL"] as? String
            let downloadURL = downloadURLString.flatMap(URL.init(string:))

            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                downloadURL: downloadURL,
                releasePageURL: downloadURL,
                feedURL: feedURL,
                githubRepository: nil,
                assetName: downloadURL?.lastPathComponent,
                checkedAt: now,
                error: latestVersion == nil ? "Feed missing version" : nil
            )
        } catch {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: nil,
                downloadURL: nil,
                releasePageURL: nil,
                feedURL: feedURL,
                githubRepository: nil,
                assetName: nil,
                checkedAt: now,
                error: error.localizedDescription
            )
        }
    }

    private func loadGitHubUpdate(repository: String, currentVersion: String, now: Date) -> AppUpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: nil,
                downloadURL: nil,
                releasePageURL: nil,
                feedURL: nil,
                githubRepository: repository,
                assetName: nil,
                checkedAt: now,
                error: "Invalid GitHub repository"
            )
        }

        do {
            let data = try fetch(url: url, timeout: 4)
            return try VersionStore.parseGitHubRelease(
                data: data,
                currentVersion: currentVersion,
                repository: repository,
                checkedAt: now
            )
        } catch {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: nil,
                downloadURL: nil,
                releasePageURL: URL(string: "https://github.com/\(repository)/releases"),
                feedURL: nil,
                githubRepository: repository,
                assetName: nil,
                checkedAt: now,
                error: error.localizedDescription
            )
        }
    }

    private func configuredGitHubRepository() -> String? {
        let path = NSString(string: "~/.ai-usage/github-repo").expandingTildeInPath
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let bundled = Bundle.main.infoDictionary?["AIUsageGitHubRepository"] as? String,
           !bundled.isEmpty {
            return bundled
        }

        return "happenings-dk/ai-usage"
    }

    private func configuredFeedURL() -> URL? {
        let path = NSString(string: "~/.ai-usage/update-feed-url").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    private func fetch(url: URL, timeout: TimeInterval) throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = FetchResultBox()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                box.set(.failure(error))
            } else {
                box.set(.success(data ?? Data()))
            }
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw VersionStoreError.timeout
        }

        return try box.get()?.get() ?? Data()
    }

    static func extractVersion(from output: String) -> String? {
        let pattern = #"\d+(?:\.\d+){1,3}(?:[-+][A-Za-z0-9.-]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else {
            return nil
        }
        return String(output[range])
    }

    static func parseGitHubRelease(
        data: Data,
        currentVersion: String,
        repository: String,
        checkedAt: Date
    ) throws -> AppUpdateStatus {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VersionStoreError.invalidFeed
        }

        let tagName = object["tag_name"] as? String
        let latestVersion = tagName?.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let releasePageURL = (object["html_url"] as? String).flatMap(URL.init(string:))
        let assets = object["assets"] as? [[String: Any]] ?? []
        let appAsset = assets.first { asset in
            guard let name = asset["name"] as? String else {
                return false
            }
            let lowercased = name.lowercased()
            return lowercased.hasSuffix(".zip") &&
                (lowercased.contains("aiusage") || lowercased.contains("ai-usage") || lowercased.contains("ai_usage"))
        } ?? assets.first { asset in
            guard let name = asset["name"] as? String else {
                return false
            }
            return name.lowercased().hasSuffix(".zip")
        }

        let downloadURL = (appAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let assetName = appAsset?["name"] as? String

        return AppUpdateStatus(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadURL: downloadURL,
            releasePageURL: releasePageURL,
            feedURL: nil,
            githubRepository: repository,
            assetName: assetName,
            checkedAt: checkedAt,
            error: latestVersion == nil ? "Release missing tag" : nil
        )
    }

    static func parseGrokLatestVersion(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["latestVersion"] as? String
    }
}

private final class FetchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?

    func set(_ result: Result<Data, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Data, Error>? {
        lock.lock()
        let result = result
        lock.unlock()
        return result
    }
}

enum VersionStoreError: LocalizedError {
    case invalidFeed
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidFeed:
            "Invalid update feed"
        case .timeout:
            "Timed out"
        }
    }
}

enum CommandRunner {
    struct Result {
        let output: String
        let error: String?
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "\(NSHomeDirectory())/.grok/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(path):\(fallbackPath)"
        } else {
            environment["PATH"] = fallbackPath
        }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return Result(output: "", error: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return Result(output: "", error: "Timed out")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = [output, stderr].joined(separator: "\n")

        if process.terminationStatus != 0 {
            return Result(output: combined, error: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return Result(output: combined, error: nil)
    }
}

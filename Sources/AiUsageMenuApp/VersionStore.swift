import Foundation

struct VersionSnapshot: Equatable, Sendable {
    let cliVersions: [CLIVersionStatus]
    let appUpdate: AppUpdateStatus
}

final class VersionStore: @unchecked Sendable {
    private struct ToolDefinition: Sendable {
        let source: UsageSource
        let executable: String
        let latestVersionProvider: LatestVersionProvider
        let updateCommand: String
    }

    private enum LatestVersionProvider: Sendable {
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

    func loadConcurrently(now: Date) async -> VersionSnapshot {
        async let appUpdate = Task.detached(priority: .utility) {
            self.loadAppUpdate(now: now)
        }.value

        let cliVersions = await withTaskGroup(of: CLIVersionStatus.self) { group in
            for tool in tools {
                group.addTask {
                    await self.loadToolVersionConcurrently(tool, now: now)
                }
            }

            var versions: [CLIVersionStatus] = []
            for await version in group {
                versions.append(version)
            }
            return versions.sorted { lhs, rhs in
                let lhsIndex = UsageSource.allCases.firstIndex(of: lhs.source) ?? .max
                let rhsIndex = UsageSource.allCases.firstIndex(of: rhs.source) ?? .max
                return lhsIndex < rhsIndex
            }
        }

        return await VersionSnapshot(
            cliVersions: cliVersions,
            appUpdate: appUpdate
        )
    }

    func loadVersion(for source: UsageSource, now: Date) -> CLIVersionStatus {
        guard let tool = tools.first(where: { $0.source == source }) else {
            return CLIVersionStatus(
                source: source,
                installedVersion: nil,
                latestVersion: nil,
                packageName: source.rawValue.lowercased(),
                updateCommand: "",
                checkedAt: now,
                error: "Unsupported CLI"
            )
        }

        return loadToolVersion(tool, now: now)
    }

    func loadVersionConcurrently(for source: UsageSource, now: Date) async -> CLIVersionStatus {
        guard let tool = tools.first(where: { $0.source == source }) else {
            return loadVersion(for: source, now: now)
        }
        return await loadToolVersionConcurrently(tool, now: now)
    }

    func loadAppVersion(now: Date) -> AppUpdateStatus {
        loadAppUpdate(now: now)
    }

    func loadAppVersionConcurrently(now: Date) async -> AppUpdateStatus {
        await Task.detached(priority: .utility) {
            self.loadAppUpdate(now: now)
        }.value
    }

    private func loadToolVersion(_ tool: ToolDefinition, now: Date) -> CLIVersionStatus {
        let installedResult = CommandRunner.run(tool.executable, ["--version"], timeout: 8)
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
            updateCommand: VersionStore.recommendedUpdateCommand(
                for: tool.source,
                defaultCommand: tool.updateCommand,
                installedAt: installedResult.executableURL
            ),
            checkedAt: now,
            error: errors.isEmpty ? nil : errors.joined(separator: "; ")
        )
    }

    private func loadToolVersionConcurrently(
        _ tool: ToolDefinition,
        now: Date
    ) async -> CLIVersionStatus {
        async let installedResult = Task.detached(priority: .utility) {
            CommandRunner.run(tool.executable, ["--version"], timeout: 8)
        }.value
        async let latestResult = Task.detached(priority: .utility) {
            self.loadLatestVersion(tool.latestVersionProvider)
        }.value
        let (installed, latest) = await (installedResult, latestResult)

        let installedVersion = VersionStore.extractVersion(from: installed.output)
        let latestVersion = VersionStore.extractVersion(from: latest.output)
        var errors: [String] = []
        if installedVersion == nil {
            errors.append(installed.error ?? "Not installed")
        }
        if latestVersion == nil {
            errors.append(latest.error ?? "Latest unavailable")
        }

        return CLIVersionStatus(
            source: tool.source,
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            packageName: tool.latestVersionProvider.packageName,
            updateCommand: VersionStore.recommendedUpdateCommand(
                for: tool.source,
                defaultCommand: tool.updateCommand,
                installedAt: installed.executableURL
            ),
            checkedAt: now,
            error: errors.isEmpty ? nil : errors.joined(separator: "; ")
        )
    }

    static func recommendedUpdateCommand(
        for source: UsageSource,
        defaultCommand: String,
        installedAt executableURL: URL?
    ) -> String {
        guard source == .claude, let executableURL else {
            return defaultCommand
        }

        let path = executableURL.path
        if path.contains("/.local/bin/") || path.contains("/.local/share/claude/") {
            return "claude update"
        }
        return defaultCommand
    }

    private func loadLatestVersion(_ provider: LatestVersionProvider) -> CommandRunner.Result {
        switch provider {
        case .npm(let packageName):
            guard let url = VersionStore.npmLatestURL(packageName: packageName) else {
                return CommandRunner.Result(output: "", error: "Invalid npm package name")
            }

            do {
                let data = try fetch(url: url, timeout: 8)
                guard let version = VersionStore.parseNPMLatestVersion(from: data) else {
                    return CommandRunner.Result(output: "", error: "npm registry response is missing a version")
                }
                return CommandRunner.Result(output: version, error: nil)
            } catch {
                return CommandRunner.Result(output: "", error: error.localizedDescription)
            }
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
        guard let feedURL = configuredFeedURL() else {
            return loadGitHubUpdate(
                repository: configuredGitHubRepository(),
                currentVersion: currentVersion,
                now: now
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
            let sha256 = (object["sha256"] as? String)?.lowercased()

            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                downloadURL: downloadURL,
                releasePageURL: downloadURL,
                feedURL: feedURL,
                githubRepository: nil,
                assetName: downloadURL?.lastPathComponent,
                sha256: sha256,
                checksumURL: nil,
                checkedAt: now,
                error: VersionStore.updateMetadataError(
                    latestVersion: latestVersion,
                    downloadURL: downloadURL,
                    sha256: sha256
                )
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
                sha256: nil,
                checksumURL: nil,
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
                sha256: nil,
                checksumURL: nil,
                checkedAt: now,
                error: "Invalid GitHub repository"
            )
        }

        do {
            let data = try fetch(url: url, timeout: 4)
            let status = try VersionStore.parseGitHubRelease(
                data: data,
                currentVersion: currentVersion,
                repository: repository,
                checkedAt: now
            )
            guard status.isUpdateAvailable else {
                return status
            }
            guard let checksumURL = status.checksumURL,
                  let assetName = status.assetName else {
                return status.replacingVerification(
                    sha256: nil,
                    error: "Release missing checksums.txt; automatic install is disabled"
                )
            }

            do {
                let checksumData = try fetch(url: checksumURL, timeout: 4)
                guard let checksum = VersionStore.parseChecksumManifest(
                    checksumData,
                    assetName: assetName
                ) else {
                    return status.replacingVerification(
                        sha256: nil,
                        error: "Release checksum does not include \(assetName); automatic install is disabled"
                    )
                }
                return status.replacingVerification(sha256: checksum, error: nil)
            } catch {
                return status.replacingVerification(
                    sha256: nil,
                    error: "Could not verify release checksum: \(error.localizedDescription)"
                )
            }
        } catch {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                latestVersion: nil,
                downloadURL: nil,
                releasePageURL: URL(string: "https://github.com/\(repository)/releases"),
                feedURL: nil,
                githubRepository: repository,
                assetName: nil,
                sha256: nil,
                checksumURL: nil,
                checkedAt: now,
                error: error.localizedDescription
            )
        }
    }

    private func configuredGitHubRepository() -> String {
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
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.timeoutInterval = timeout
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

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

    static func npmLatestURL(packageName: String) -> URL? {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedPackageName = packageName.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ) else {
            return nil
        }
        return URL(string: "https://registry.npmjs.org/\(encodedPackageName)/latest")
    }

    static func parseNPMLatestVersion(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["version"] as? String
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
        let checksumAsset = assets.first { asset in
            (asset["name"] as? String)?.lowercased() == "checksums.txt"
        }
        let checksumURL = (checksumAsset?["browser_download_url"] as? String).flatMap(URL.init(string:))

        return AppUpdateStatus(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadURL: downloadURL,
            releasePageURL: releasePageURL,
            feedURL: nil,
            githubRepository: repository,
            assetName: assetName,
            sha256: nil,
            checksumURL: checksumURL,
            checkedAt: checkedAt,
            error: updateMetadataError(
                latestVersion: latestVersion,
                downloadURL: downloadURL,
                sha256: nil,
                requiresChecksum: false
            )
        )
    }

    static func parseChecksumManifest(_ data: Data, assetName: String) -> String? {
        guard let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            let components = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard components.count == 2 else {
                continue
            }

            let checksum = String(components[0]).lowercased()
            let listedName = String(components[1]).trimmingCharacters(
                in: CharacterSet(charactersIn: " *")
            )
            guard listedName == assetName,
                  checksum.count == 64,
                  checksum.allSatisfy({ $0.isHexDigit }) else {
                continue
            }
            return checksum
        }
        return nil
    }

    private static func updateMetadataError(
        latestVersion: String?,
        downloadURL: URL?,
        sha256: String?,
        requiresChecksum: Bool = true
    ) -> String? {
        if latestVersion == nil {
            return "Release missing version"
        }
        if downloadURL == nil {
            return "Release missing app download"
        }
        if requiresChecksum && sha256 == nil {
            return "Release missing SHA-256 checksum; automatic install is disabled"
        }
        return nil
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
    struct Result: Sendable {
        let output: String
        let error: String?
        let executableURL: URL?

        init(output: String, error: String?, executableURL: URL? = nil) {
            self.output = output
            self.error = error
            self.executableURL = executableURL
        }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Result {
        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        let searchDirectories = executableSearchDirectories(environment: environment)
        environment["PATH"] = searchDirectories.joined(separator: ":")

        guard let executableURL = resolveExecutable(
            named: executable,
            searchDirectories: searchDirectories
        ) else {
            return Result(
                output: "",
                error: "\(executable) was not found in your CLI install locations"
            )
        }

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return Result(
                output: "",
                error: error.localizedDescription,
                executableURL: executableURL
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return Result(output: "", error: "Timed out", executableURL: executableURL)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = [output, stderr].joined(separator: "\n")

        if process.terminationStatus != 0 {
            return Result(
                output: combined,
                error: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                executableURL: executableURL
            )
        }

        return Result(output: combined, error: nil, executableURL: executableURL)
    }

    static func executableSearchDirectories(
        environment: [String: String],
        homeDirectory: String = NSHomeDirectory(),
        nvmVersionNames: [String]? = nil,
        nvmDefaultAlias: String? = nil
    ) -> [String] {
        let homeURL = URL(fileURLWithPath: homeDirectory, isDirectory: true)
        let discoveredNVMVersions = nvmVersionNames ?? installedNVMVersionNames(homeURL: homeURL)
        let discoveredDefaultAlias = nvmDefaultAlias ?? readNVMDefaultAlias(homeURL: homeURL)
        let orderedNVMVersions = orderNVMVersions(
            discoveredNVMVersions,
            defaultAlias: discoveredDefaultAlias
        )

        var directories = [
            homeURL.appendingPathComponent(".local/bin").path,
            homeURL.appendingPathComponent(".grok/bin").path,
            homeURL.appendingPathComponent(".bun/bin").path,
            homeURL.appendingPathComponent(".volta/bin").path,
            homeURL.appendingPathComponent(".local/share/mise/shims").path,
            homeURL.appendingPathComponent(".asdf/shims").path,
            homeURL.appendingPathComponent("bin").path
        ]

        directories.append(contentsOf: orderedNVMVersions.map { versionName in
            homeURL
                .appendingPathComponent(".nvm/versions/node")
                .appendingPathComponent(versionName)
                .appendingPathComponent("bin")
                .path
        })
        directories.append(
            contentsOf: (environment["PATH"] ?? "")
                .split(separator: ":")
                .map(String.init)
        )
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])

        var seen = Set<String>()
        return directories.filter { directory in
            !directory.isEmpty && seen.insert(directory).inserted
        }
    }

    private static func resolveExecutable(
        named executable: String,
        searchDirectories: [String]
    ) -> URL? {
        let fileManager = FileManager.default
        if executable.contains("/") {
            return fileManager.isExecutableFile(atPath: executable)
                ? URL(fileURLWithPath: executable)
                : nil
        }

        for directory in searchDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func installedNVMVersionNames(homeURL: URL) -> [String] {
        let versionsURL = homeURL.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let urls = try? FileManager.default.contentsOfDirectory(
            at: versionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls?.map(\.lastPathComponent) ?? []
    }

    private static func readNVMDefaultAlias(homeURL: URL) -> String? {
        let aliasURL = homeURL.appendingPathComponent(".nvm/alias/default")
        guard let value = try? String(contentsOf: aliasURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderNVMVersions(
        _ versionNames: [String],
        defaultAlias: String?
    ) -> [String] {
        let sorted = versionNames.sorted { lhs, rhs in
            VersionComparison.compare(lhs, rhs) == .orderedDescending
        }
        guard let defaultAlias else {
            return sorted
        }

        let normalizedAlias = defaultAlias.trimmingCharacters(
            in: CharacterSet(charactersIn: "vV")
        )
        guard let defaultVersion = sorted.first(where: { versionName in
            let normalizedVersion = versionName.trimmingCharacters(
                in: CharacterSet(charactersIn: "vV")
            )
            return normalizedVersion == normalizedAlias ||
                normalizedVersion.hasPrefix("\(normalizedAlias).")
        }) else {
            return sorted
        }

        return [defaultVersion] + sorted.filter { $0 != defaultVersion }
    }
}

import Darwin
import Foundation

private enum UpdateHelperError: LocalizedError {
    case invalidArguments
    case invalidBundle
    case bundleIdentifierMismatch
    case versionMismatch
    case teamIdentifierMismatch
    case parentDidNotExit
    case appDidNotLaunch
    case rollbackFailed(String)
    case commandFailed(String)
    case atomicSwapFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "Invalid updater helper arguments"
        case .invalidBundle:
            "Replacement is not a valid app bundle"
        case .bundleIdentifierMismatch:
            "Replacement has an unexpected bundle identifier"
        case .versionMismatch:
            "Replacement has an unexpected version"
        case .teamIdentifierMismatch:
            "Replacement was signed by an unexpected developer"
        case .parentDidNotExit:
            "AI Usage did not quit in time for the update"
        case .appDidNotLaunch:
            "The updated AI Usage app did not start"
        case .rollbackFailed(let message):
            "The update failed and automatic rollback also failed: \(message)"
        case .commandFailed(let message):
            message.isEmpty ? "Update validation command failed" : message
        case .atomicSwapFailed(let code):
            "Could not atomically replace the app (errno \(code))"
        }
    }
}

private struct UpdateArguments {
    let currentApp: URL
    let replacementApp: URL
    let temporaryDirectory: URL
    let expectedBundleIdentifier: String
    let expectedVersion: String
    let expectedTeamIdentifier: String
    let parentProcessIdentifier: pid_t

    init(arguments: [String]) throws {
        guard arguments.count == 8,
              let parentProcessIdentifier = pid_t(arguments[7]) else {
            throw UpdateHelperError.invalidArguments
        }
        currentApp = URL(fileURLWithPath: arguments[1], isDirectory: true)
        replacementApp = URL(fileURLWithPath: arguments[2], isDirectory: true)
        temporaryDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
        expectedBundleIdentifier = arguments[4]
        expectedVersion = arguments[5]
        expectedTeamIdentifier = arguments[6]
        self.parentProcessIdentifier = parentProcessIdentifier
    }
}

private enum AIUsageUpdaterHelper {
    private static let maximumCommandOutputBytes = 16 * 1_024 * 1_024

    static func main() {
        do {
            let arguments = try UpdateArguments(arguments: CommandLine.arguments)
            var replacementContainsPreviousApp = false
            do {
                try waitForParentToExit(arguments.parentProcessIdentifier)
                try validate(arguments)
                try atomicSwap(arguments.currentApp, arguments.replacementApp)
                replacementContainsPreviousApp = true

                do {
                    try run("/usr/bin/open", [arguments.currentApp.path])
                    try waitForApplicationLaunch(at: arguments.currentApp)
                } catch let launchError {
                    do {
                        try atomicSwap(arguments.currentApp, arguments.replacementApp)
                        replacementContainsPreviousApp = false
                    } catch let rollbackError {
                        throw UpdateHelperError.rollbackFailed(
                            "\(launchError.localizedDescription); \(rollbackError.localizedDescription)"
                        )
                    }
                    _ = try? run("/usr/bin/open", [arguments.currentApp.path])
                    throw launchError
                }

                do {
                    try preservePreviousApp(
                        at: arguments.replacementApp,
                        beside: arguments.currentApp
                    )
                    replacementContainsPreviousApp = false
                } catch {
                    let warning = "AI Usage updated, but the previous app remains at "
                        + "\(arguments.replacementApp.path): \(error.localizedDescription)\n"
                    FileHandle.standardError.write(Data(warning.utf8))
                }
                try? FileManager.default.removeItem(at: arguments.temporaryDirectory)
            } catch {
                if !replacementContainsPreviousApp {
                    try? FileManager.default.removeItem(at: arguments.replacementApp)
                }
                try? FileManager.default.removeItem(at: arguments.temporaryDirectory)
                throw error
            }
        } catch {
            let message = "AI Usage update failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(1)
        }
    }

    private static func waitForParentToExit(_ processIdentifier: pid_t) throws {
        let deadline = Date().addingTimeInterval(30)
        while kill(processIdentifier, 0) == 0, Date() < deadline {
            usleep(100_000)
        }
        if kill(processIdentifier, 0) == 0 {
            throw UpdateHelperError.parentDidNotExit
        }
    }

    private static func validate(_ arguments: UpdateArguments) throws {
        guard let bundle = Bundle(url: arguments.replacementApp) else {
            throw UpdateHelperError.invalidBundle
        }
        guard bundle.bundleIdentifier == arguments.expectedBundleIdentifier else {
            throw UpdateHelperError.bundleIdentifierMismatch
        }
        guard bundle.infoDictionary?["CFBundleShortVersionString"] as? String == arguments.expectedVersion else {
            throw UpdateHelperError.versionMismatch
        }

        try run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", arguments.replacementApp.path]
        )
        let signingDetails = try run(
            "/usr/bin/codesign",
            ["-d", "--verbose=4", arguments.replacementApp.path]
        )
        let teamIdentifier = signingDetails
            .split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("TeamIdentifier=") }?
            .dropFirst("TeamIdentifier=".count)
        guard String(teamIdentifier ?? "") == arguments.expectedTeamIdentifier else {
            throw UpdateHelperError.teamIdentifierMismatch
        }
        try run(
            "/usr/sbin/spctl",
            ["--assess", "--type", "execute", "--verbose=2", arguments.replacementApp.path]
        )
    }

    private static func waitForApplicationLaunch(at appURL: URL) throws {
        guard let bundle = Bundle(url: appURL),
              let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String else {
            throw UpdateHelperError.invalidBundle
        }
        let executablePath = appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName)
            .path
        let deadline = Date().addingTimeInterval(15)

        while Date() < deadline {
            let processes = try run("/bin/ps", ["-axo", "command="])
            let isRunning = processes.split(whereSeparator: \.isNewline).contains { line in
                let command = line.trimmingCharacters(in: .whitespaces)
                return command == executablePath || command.hasPrefix(executablePath + " ")
            }
            if isRunning {
                return
            }
            usleep(100_000)
        }
        throw UpdateHelperError.appDidNotLaunch
    }

    private static func preservePreviousApp(at oldAppURL: URL, beside currentAppURL: URL) throws {
        let backupURL = currentAppURL.deletingLastPathComponent()
            .appendingPathComponent(".AiUsageMenu.previous.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.moveItem(at: oldAppURL, to: backupURL)
    }

    private static func atomicSwap(_ firstURL: URL, _ secondURL: URL) throws {
        let result = firstURL.path.withCString { firstPath in
            secondURL.path.withCString { secondPath in
                renamex_np(firstPath, secondPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw UpdateHelperError.atomicSwapFailed(errno)
        }
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-helper-command-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.close()

        let outputSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard outputSize <= maximumCommandOutputBytes else {
            throw UpdateHelperError.commandFailed("Validation command output was unexpectedly large")
        }
        let output = String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateHelperError.commandFailed(
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}

AIUsageUpdaterHelper.main()

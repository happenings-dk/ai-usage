import AppKit
import CryptoKit
import Foundation

private final class CappedDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let maximumBytes: Int64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(destinationURL: URL, maximumBytes: Int64) {
        self.destinationURL = destinationURL
        self.maximumBytes = maximumBytes
    }

    func download(from url: URL, using session: URLSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maximumBytes
            || totalBytesExpectedToWrite > maximumBytes {
            downloadTask.cancel()
            finish(with: .failure(AppUpdaterError.archiveTooLarge))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            finish(with: .failure(AppUpdaterError.invalidDownloadResponse))
            return
        }

        do {
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(size) <= maximumBytes else {
                throw AppUpdaterError.archiveTooLarge
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finish(with: .success(()))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<Void, any Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

enum AppUpdater {
    private static let expectedTeamIdentifier = "9JLJ6MJLMJ"
    private static let maximumArchiveBytes = 250 * 1_024 * 1_024
    private static let maximumArchiveEntries = 10_000
    private static let maximumExpandedArchiveBytes = 1_024 * 1_024 * 1_024
    private static let maximumExpandedEntryBytes = 250 * 1_024 * 1_024
    private static let maximumCommandOutputBytes = 16 * 1_024 * 1_024

    static func install(update: AppUpdateStatus) async throws {
        guard let downloadURL = update.downloadURL else {
            throw AppUpdaterError.missingDownloadURL
        }
        guard let expectedVersion = update.latestVersion else {
            throw AppUpdaterError.missingVersion
        }
        guard let expectedChecksum = update.sha256?.lowercased() else {
            throw AppUpdaterError.missingChecksum
        }

        let appURL = Bundle.main.bundleURL
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let updateID = UUID().uuidString
        let replacementURL = appURL.deletingLastPathComponent()
            .appendingPathComponent(".AIUsageMenu-\(updateID).update.app")
        var helperOwnsUpdateFiles = false
        defer {
            if !helperOwnsUpdateFiles {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                try? FileManager.default.removeItem(at: replacementURL)
            }
        }

        let archiveURL = temporaryDirectory.appendingPathComponent(update.assetName ?? "AiUsageMenu.zip")
        try await download(from: downloadURL, to: archiveURL)
        let actualChecksum = try sha256(at: archiveURL)
        guard actualChecksum == expectedChecksum else {
            throw AppUpdaterError.checksumMismatch(
                expected: expectedChecksum,
                actual: actualChecksum
            )
        }
        try validateArchiveEntries(at: archiveURL)

        let extractURL = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, extractURL.path])

        guard let extractedApp = findAppBundle(under: extractURL) else {
            throw AppUpdaterError.appBundleNotFound
        }
        try validate(
            appURL: extractedApp,
            expectedBundleIdentifier: Bundle.main.bundleIdentifier,
            expectedVersion: expectedVersion,
            expectedTeamIdentifier: requiredTeamIdentifier
        )

        let parentDirectory = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdaterError.installLocationNotWritable
        }
        try run("/usr/bin/ditto", [extractedApp.path, replacementURL.path])
        try validate(
            appURL: replacementURL,
            expectedBundleIdentifier: Bundle.main.bundleIdentifier,
            expectedVersion: expectedVersion,
            expectedTeamIdentifier: requiredTeamIdentifier
        )

        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let helperURL = Bundle.main.url(
                forAuxiliaryExecutable: "AIUsageUpdaterHelper"
              ) ?? helperURLInBundle else {
            throw AppUpdaterError.missingUpdaterHelper
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            appURL.path,
            replacementURL.path,
            temporaryDirectory.path,
            bundleIdentifier,
            expectedVersion,
            requiredTeamIdentifier,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        try process.run()
        helperOwnsUpdateFiles = true

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    static func sha256(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func download(from url: URL, to destinationURL: URL) async throws {
        if url.isFileURL {
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= maximumArchiveBytes else {
                throw AppUpdaterError.archiveTooLarge
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            let copiedSize = try destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard copiedSize <= maximumArchiveBytes else {
                throw AppUpdaterError.archiveTooLarge
            }
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let delegate = CappedDownloadDelegate(
            destinationURL: destinationURL,
            maximumBytes: Int64(maximumArchiveBytes)
        )
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        try await delegate.download(from: url, using: session)
    }

    private static func validate(
        appURL: URL,
        expectedBundleIdentifier: String?,
        expectedVersion: String,
        expectedTeamIdentifier: String
    ) throws {
        guard let bundle = Bundle(url: appURL) else {
            throw AppUpdaterError.invalidAppBundle
        }
        guard let expectedBundleIdentifier,
              bundle.bundleIdentifier == expectedBundleIdentifier else {
            throw AppUpdaterError.bundleIdentifierMismatch
        }

        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        guard version == expectedVersion else {
            throw AppUpdaterError.versionMismatch(
                expected: expectedVersion,
                actual: version ?? "unknown"
            )
        }

        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        let signingDetails = try run(
            "/usr/bin/codesign",
            ["-d", "--verbose=4", appURL.path]
        )
        let teamIdentifier = signingDetails
            .split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("TeamIdentifier=") }?
            .dropFirst("TeamIdentifier=".count)
        guard String(teamIdentifier ?? "") == expectedTeamIdentifier else {
            throw AppUpdaterError.teamIdentifierMismatch
        }
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", appURL.path])
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-command-\(UUID().uuidString).log")
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
            throw AppUpdaterError.commandOutputTooLarge
        }
        let output = String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw AppUpdaterError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func findAppBundle(under directory: URL) -> URL? {
        let appURL = directory.appendingPathComponent("AiUsageMenu.app", isDirectory: true)
        guard let values = try? appURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
        values.isDirectory == true,
        values.isSymbolicLink != true else {
            return nil
        }
        return appURL
    }

    private static func validateArchiveEntries(at archiveURL: URL) throws {
        let listing = try run("/usr/bin/unzip", ["-Z1", archiveURL.path])
        let entries = listing.split(whereSeparator: \.isNewline)
        guard !entries.isEmpty, entries.count <= maximumArchiveEntries else {
            throw AppUpdaterError.invalidArchiveLayout
        }

        for entry in entries {
            let path = String(entry)
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"),
                  !components.contains(".."),
                  let topLevel = components.first,
                  topLevel == "AiUsageMenu.app" || topLevel == "__MACOSX" else {
                throw AppUpdaterError.invalidArchiveLayout
            }
        }

        let verboseListing = try run("/usr/bin/unzip", ["-Z", "-v", archiveURL.path])
        var expandedArchiveBytes = 0
        var sizedEntryCount = 0
        for line in verboseListing.split(whereSeparator: \.isNewline) {
            let prefix = "uncompressed size:"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix),
                  let sizeText = trimmed.dropFirst(prefix.count).split(separator: " ").first,
                  let size = Int(sizeText) else {
                continue
            }
            guard size <= maximumExpandedEntryBytes else {
                throw AppUpdaterError.archiveTooLarge
            }
            let (newTotal, overflow) = expandedArchiveBytes.addingReportingOverflow(size)
            guard !overflow, newTotal <= maximumExpandedArchiveBytes else {
                throw AppUpdaterError.archiveTooLarge
            }
            expandedArchiveBytes = newTotal
            sizedEntryCount += 1
        }
        guard sizedEntryCount == entries.count else {
            throw AppUpdaterError.invalidArchiveLayout
        }
    }

    private static func sha256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static var requiredTeamIdentifier: String {
        Bundle.main.infoDictionary?["AIUsageExpectedTeamIdentifier"] as? String ?? expectedTeamIdentifier
    }

    private static var helperURLInBundle: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/AIUsageUpdaterHelper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}

enum AppUpdaterError: LocalizedError {
    case missingDownloadURL
    case missingVersion
    case missingChecksum
    case invalidDownloadResponse
    case checksumMismatch(expected: String, actual: String)
    case archiveTooLarge
    case invalidArchiveLayout
    case commandOutputTooLarge
    case appBundleNotFound
    case invalidAppBundle
    case bundleIdentifierMismatch
    case teamIdentifierMismatch
    case versionMismatch(expected: String, actual: String)
    case installLocationNotWritable
    case missingUpdaterHelper
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL:
            "No app update download URL"
        case .missingVersion:
            "The update does not declare a version"
        case .missingChecksum:
            "The update has no SHA-256 checksum, so automatic installation is disabled"
        case .invalidDownloadResponse:
            "The update download server returned an invalid response"
        case .checksumMismatch:
            "The downloaded update did not match its published checksum"
        case .archiveTooLarge:
            "The downloaded update is unexpectedly large"
        case .invalidArchiveLayout:
            "The downloaded update archive has an unsafe layout"
        case .commandOutputTooLarge:
            "An update validation command produced unexpectedly large output"
        case .appBundleNotFound:
            "Downloaded archive did not contain an app bundle"
        case .invalidAppBundle:
            "Downloaded update is not a valid app bundle"
        case .bundleIdentifierMismatch:
            "Downloaded update belongs to a different app"
        case .teamIdentifierMismatch:
            "Downloaded update was signed by an unexpected developer"
        case .versionMismatch(let expected, let actual):
            "Downloaded update is version \(actual), expected \(expected)"
        case .installLocationNotWritable:
            "AI Usage cannot update itself in its current folder"
        case .missingUpdaterHelper:
            "The installed app does not contain its update helper"
        case .commandFailed(let message):
            message.isEmpty ? "Update signature validation failed" : message
        }
    }
}

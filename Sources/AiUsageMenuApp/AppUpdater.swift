import AppKit
import Foundation

enum AppUpdater {
    static func install(update: AppUpdateStatus) throws {
        guard let downloadURL = update.downloadURL else {
            throw AppUpdaterError.missingDownloadURL
        }

        let appURL = Bundle.main.bundleURL
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-usage-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let archiveURL = temporaryDirectory.appendingPathComponent(update.assetName ?? "AiUsageMenu.zip")
        let archiveData = try Data(contentsOf: downloadURL)
        try archiveData.write(to: archiveURL, options: .atomic)

        let extractURL = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, extractURL.path])

        guard let extractedApp = findAppBundle(under: extractURL) else {
            throw AppUpdaterError.appBundleNotFound
        }

        let scriptURL = temporaryDirectory.appendingPathComponent("install-update.sh")
        let replacementURL = appURL.deletingLastPathComponent().appendingPathComponent(".AiUsageMenu.app.update")
        let script = """
        #!/bin/zsh
        set -euo pipefail
        sleep 1
        /bin/rm -rf \(shellQuote(replacementURL.path))
        /usr/bin/ditto \(shellQuote(extractedApp.path)) \(shellQuote(replacementURL.path))
        /bin/rm -rf \(shellQuote(appURL.path))
        /bin/mv \(shellQuote(replacementURL.path)) \(shellQuote(appURL.path))
        /usr/bin/open \(shellQuote(appURL.path))
        /bin/rm -rf \(shellQuote(temporaryDirectory.path))
        """
        try script.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AppUpdaterError.commandFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func findAppBundle(under directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let file as URL in enumerator {
            if file.pathExtension == "app" {
                return file
            }
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum AppUpdaterError: LocalizedError {
    case missingDownloadURL
    case appBundleNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL:
            "No app update download URL"
        case .appBundleNotFound:
            "Downloaded archive did not contain an app bundle"
        case .commandFailed(let message):
            message.isEmpty ? "Update command failed" : message
        }
    }
}

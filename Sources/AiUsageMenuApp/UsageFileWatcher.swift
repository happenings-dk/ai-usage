import CoreServices
import Foundation

/// Watches local CLI data directories and coalesces bursts into one refresh.
final class UsageFileWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai-usage.file-watcher")
    private let paths: [String]
    private let onChange: @Sendable () -> Void
    private var pendingChange: DispatchWorkItem?
    private var stream: FSEventStreamRef?

    init(paths: [String] = UsageFileWatcher.defaultPaths(), onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Starts recursively watching every available CLI data directory.
    func start() {
        queue.sync {
            guard stream == nil, !paths.isEmpty else {
                return
            }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                    kFSEventStreamCreateFlagWatchRoot |
                    kFSEventStreamCreateFlagUseCFTypes |
                    kFSEventStreamCreateFlagNoDefer
            )
            guard let stream = FSEventStreamCreate(
                nil,
                usageFileWatcherCallback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,
                flags
            ) else {
                return
            }

            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    /// Stops watching and releases the underlying FSEvents stream.
    func stop() {
        queue.sync {
            pendingChange?.cancel()
            pendingChange = nil
            guard let stream else {
                return
            }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    fileprivate func didReceiveEvents() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [onChange] in
            onChange()
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
    }

    private static func defaultPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [".claude", ".codex", ".gemini", ".grok"]
            .map { home.appendingPathComponent($0, isDirectory: true).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }
}

private let usageFileWatcherCallback: FSEventStreamCallback = {
    _, context, eventCount, _, _, _ in
    guard eventCount > 0, let context else {
        return
    }
    Unmanaged<UsageFileWatcher>.fromOpaque(context)
        .takeUnretainedValue()
        .didReceiveEvents()
}

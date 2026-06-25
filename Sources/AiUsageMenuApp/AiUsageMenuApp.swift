import SwiftUI

@main
struct AiUsageMenuApp: App {
    @State private var model = UsageViewModel()

    init() {
        runBridgeSmokeIfRequested()
        exportSnapshotIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            UsageDashboardView(model: model)
                .frame(width: 390, height: 820)
        } label: {
            Label {
                Text(model.menuBarTitle)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "chart.bar.xaxis")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 440)
                .padding(20)
        }
    }

    private func exportSnapshotIfRequested() {
        let arguments = CommandLine.arguments
        guard let exportIndex = arguments.firstIndex(of: "--export-snapshot") else {
            return
        }

        do {
            let snapshot = try UsageStore().loadSnapshot(now: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)

            let nextIndex = arguments.index(after: exportIndex)
            if nextIndex < arguments.endIndex, !arguments[nextIndex].hasPrefix("-") {
                let url = URL(fileURLWithPath: arguments[nextIndex])
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
            } else if let string = String(data: data, encoding: .utf8) {
                FileHandle.standardOutput.write(Data(string.utf8))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Foundation.exit(0)
        } catch {
            let message = "Failed to export AI usage snapshot: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(1)
        }
    }

    private func runBridgeSmokeIfRequested() {
        guard CommandLine.arguments.contains("--bridge-smoke") else {
            return
        }

        do {
            let snapshot = try UsageStore().loadSnapshot(now: Date())
            let bridge = BridgeServer.shared
            bridge.update(snapshot: snapshot)
            bridge.start()
            Thread.sleep(forTimeInterval: 0.25)
            let url = bridge.localhostURL?.absoluteString ?? bridge.bridgeURL?.absoluteString ?? "Bridge unavailable"
            FileHandle.standardOutput.write(Data("\(url)\n".utf8))
            RunLoop.current.run()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }
}

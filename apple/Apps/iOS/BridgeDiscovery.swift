import Foundation
import Network

/// A nearby bridge advertised through Bonjour.
struct DiscoveredBridge: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let deviceID: String?
    let endpoint: NWEndpoint
}

/// Browses the local network for AI Usage Mac bridges.
@MainActor
final class BridgeDiscovery {
    private var browser: NWBrowser?

    /// Starts browsing and reports a stable, sorted list whenever results change.
    func start(onChange: @escaping @MainActor ([DiscoveredBridge]) -> Void) {
        guard browser == nil else {
            return
        }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: BridgeProtocol.bonjourServiceType, domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { results, _ in
            let bridges = results.compactMap(Self.makeBridge).sorted { $0.name < $1.name }
            Task { @MainActor in
                onChange(bridges)
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state {
                browser.cancel()
            }
        }
        self.browser = browser
        browser.start(queue: .global(qos: .utility))
    }

    private nonisolated static func makeBridge(from result: NWBrowser.Result) -> DiscoveredBridge? {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return nil
        }
        let deviceID: String?
        if case .bonjour(let record) = result.metadata {
            deviceID = record["deviceID"]
        } else {
            deviceID = nil
        }
        return DiscoveredBridge(
            id: deviceID ?? result.endpoint.debugDescription,
            name: name,
            deviceID: deviceID,
            endpoint: result.endpoint
        )
    }
}

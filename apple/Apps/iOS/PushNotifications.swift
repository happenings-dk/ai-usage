import UIKit

/// Connects UIApplication remote-notification callbacks to the SwiftUI model.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    var backgroundRefreshHandler: (@MainActor @Sendable () async -> Bool)?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await PushRegistrationService.shared.setDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task {
            await PushRegistrationService.shared.setRegistrationError(error.localizedDescription)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let didRefresh = await backgroundRefreshHandler?() ?? false
            completionHandler(didRefresh ? .newData : .failed)
        }
    }
}

/// Stores the APNs device token and registers it with the paired relay.
actor PushRegistrationService {
    static let shared = PushRegistrationService()

    private let deviceTokenDefaultsKey = "apnsDeviceToken"
    private var lastPairing: BridgePairingPayload?

    func setDeviceToken(_ token: String) async {
        UserDefaults.standard.set(token, forKey: deviceTokenDefaultsKey)
        if let lastPairing {
            try? await register(token: token, pairing: lastPairing)
        }
    }

    func setRegistrationError(_ message: String) {
        UserDefaults.standard.set(message, forKey: "apnsRegistrationError")
    }

    func syncRegistration(pairing: BridgePairingPayload) async {
        lastPairing = pairing
        guard let token = UserDefaults.standard.string(forKey: deviceTokenDefaultsKey) else {
            return
        }
        try? await register(token: token, pairing: pairing)
    }

    private func register(token: String, pairing: BridgePairingPayload) async throws {
        guard let relayURL = pairing.relayURL,
              let relayChannel = pairing.relayChannel,
              let relayToken = pairing.relayToken,
              var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else {
            return
        }
        components.scheme = components.scheme == "wss" ? "https" : "http"
        components.path = "/v1/channels/\(relayChannel)/devices"
        components.query = nil
        guard let url = components.url else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(relayToken)", forHTTPHeaderField: BridgeProtocol.authorizationHeader)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeviceRegistration(deviceToken: token))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw PushRegistrationError.rejected
        }
    }
}

private struct DeviceRegistration: Encodable, Sendable {
    let deviceToken: String
    let platform = "ios"
}

private enum PushRegistrationError: Error {
    case rejected
}

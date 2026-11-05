//
//  HostedKycSessionMonitor.swift
//  BanxaPaymentSDK
//

import Foundation

/// Message types the hosted flow posts. The same literals are used by the space, JS and RN sides.
enum HostedKycMessageType {
    static let loading = "banxa:loading"
    static let ready = "banxa:ready"
    static let complete = "banxa:kyc-complete"
    static let error = "banxa:error"
}

/// What the hosted flow told the SDK, once the sender has been checked.
enum HostedKycEvent: Equatable {
    case complete(BanxaKycResult)
    case error(code: String?, message: String?)
    case ready(status: String)
    case loading(status: String)
    case rejected(BanxaKycRejectedMessage)
}

/// What to do with a navigation the web view is about to make.
enum HostedKycNavigationDecision: Equatable {
    case allow
    /// The return URL after the flow already completed: block it, but don't complete again.
    case cancel
    case cancelAndComplete(BanxaKycResult)
}

/// Decides how the hosted KYC web view reacts to messages, navigations and permission requests.
/// It knows nothing about WebKit, so every decision can be unit tested.
struct HostedKycSessionMonitor {
    static let requiredUsageDescriptionKeys = ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"]

    let session: KycSession
    let sessionURL: URL?
    private let returnURL: String?
    private let acceptedOrigins: [String]
    private let now: Date
    private(set) var didComplete = false

    /// - Parameters:
    ///   - session: The session being presented.
    ///   - returnURL: The `returnUrl` the session was created with. Navigating to it ends the flow.
    ///   - allowedOrigins: Extra origins trusted on top of the session URL's own.
    ///   - now: The current time, used for the expiry check.
    init(session: KycSession, returnURL: String?, allowedOrigins: [String], now: Date = Date()) {
        self.session = session
        self.sessionURL = URL(string: session.redirectURL).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        self.returnURL = returnURL
        self.now = now

        let extra = allowedOrigins.compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.acceptedOrigins = ([sessionURL].compactMap { $0 } + extra).compactMap(Self.origin(of:))
    }

    /// Whether the session's link has passed `expiresAt`. An unreadable `expiresAt` counts as not expired.
    var isExpired: Bool {
        guard let expirationDate = session.expirationDate else { return false }
        return expirationDate <= now
    }

    /// Returns why the session can't be presented, or `nil` when it can.
    /// - Parameters:
    ///   - isOSSupported: Whether the device can capture camera and microphone in a web view (iOS 14.3+).
    ///   - infoDictionary: The host app's `Info.plist`.
    /// - Returns: The first problem found, or `nil`.
    func preflightError(isOSSupported: Bool, infoDictionary: [String: Any]) -> BanxaKycError? {
        if sessionURL == nil {
            return .invalidSessionURL
        }
        if isExpired {
            return .sessionExpired
        }
        if !isOSSupported {
            return .unsupportedOSVersion
        }

        let missing = Self.requiredUsageDescriptionKeys.filter { key in
            let value = infoDictionary[key] as? String
            return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        guard missing.isEmpty else {
            return .missingUsageDescription(missing)
        }

        return nil
    }

    /// Turns a script message into an event, or `nil` when it should be ignored.
    /// - Parameters:
    ///   - body: The message body, normally a dictionary with `type`, `status`, `code` and `message`.
    ///   - origin: The sender's origin, as WebKit reports it.
    ///   - isMainFrame: Whether the sender is the top-level page.
    /// - Returns: The event to act on, or `nil`.
    mutating func handleMessage(body: Any, origin: String, isMainFrame: Bool) -> HostedKycEvent? {
        guard let payload = body as? [String: Any],
              let type = payload["type"] as? String,
              type.hasPrefix("banxa:") else {
            return nil
        }

        // A third-party frame inside the flow (e.g. the ID-capture vendor's) must not be able to fake completion.
        guard isMainFrame else {
            return .rejected(BanxaKycRejectedMessage(reason: .frame, type: type, origin: origin))
        }
        guard isAccepted(origin: origin) else {
            return .rejected(BanxaKycRejectedMessage(reason: .origin, type: type, origin: origin))
        }

        let status = payload["status"] as? String
        switch type {
        case HostedKycMessageType.complete:
            return complete(status: status ?? "complete", channel: .message).map(HostedKycEvent.complete)
        case HostedKycMessageType.error:
            return .error(code: Self.string(from: payload["code"]), message: payload["message"] as? String)
        case HostedKycMessageType.ready:
            return .ready(status: status ?? "ready")
        case HostedKycMessageType.loading:
            return .loading(status: status ?? "loading")
        default:
            return nil
        }
    }

    /// Decides whether a navigation goes ahead. Reaching the return URL ends the flow.
    /// - Parameter url: The URL the web view is about to load.
    /// - Returns: The decision for the navigation.
    mutating func handleNavigation(to url: URL) -> HostedKycNavigationDecision {
        guard let returnURL,
              let target = URL(string: returnURL),
              Self.withoutQuery(url) == Self.withoutQuery(target) else {
            return .allow
        }

        guard let result = complete(status: "complete", channel: .returnURL) else {
            return .cancel
        }
        return .cancelAndComplete(result)
    }

    /// Whether a page from this origin may use the camera and microphone.
    /// - Parameter origin: The requesting origin, as WebKit reports it.
    func shouldGrantMediaCapture(origin: String) -> Bool {
        isAccepted(origin: origin)
    }

    /// Builds an origin string from the parts of a `WKSecurityOrigin`. A port of `0` means the default port.
    /// - Parameters:
    ///   - scheme: The origin's scheme.
    ///   - host: The origin's host.
    ///   - port: The origin's port, or `0`.
    /// - Returns: An origin such as `https://kyc.banxa.com`.
    static func origin(scheme: String, host: String, port: Int) -> String {
        let scheme = scheme.lowercased()
        let host = host.lowercased()
        guard port != 0, port != defaultPort(for: scheme) else {
            return "\(scheme)://\(host)"
        }
        return "\(scheme)://\(host):\(port)"
    }

    private mutating func complete(status: String, channel: BanxaKycResult.Channel) -> BanxaKycResult? {
        guard !didComplete else { return nil }
        didComplete = true
        return BanxaKycResult(status: status, channel: channel)
    }

    private func isAccepted(origin: String) -> Bool {
        let normalized = URL(string: origin).flatMap(Self.origin(of:)) ?? origin
        return acceptedOrigins.contains(normalized)
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host, !host.isEmpty else { return nil }
        return origin(scheme: scheme, host: host, port: url.port ?? 0)
    }

    private static func defaultPort(for scheme: String) -> Int? {
        ["http": 80, "https": 443][scheme]
    }

    /// The URL with its query and fragment removed, so a return URL still matches when the flow appends parameters.
    private static func withoutQuery(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if let scheme = components.scheme, components.port == defaultPort(for: scheme) {
            components.port = nil
        }

        guard let string = components.string else { return nil }
        return string.hasSuffix("/") ? String(string.dropLast()) : string
    }

    private static func string(from value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let int = value as? Int {
            return String(int)
        }
        return nil
    }
}

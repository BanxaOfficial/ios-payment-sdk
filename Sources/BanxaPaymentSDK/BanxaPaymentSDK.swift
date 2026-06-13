// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import PrimerSDK

// MARK: - Environment

/// The Banxa backend environment a partner wants to target.
public enum BanxaEnvironment: Sendable {
    case sandbox
    case production
    case local
    case preprod
    
    /// Base host (scheme + domain) for the selected environment.
    /// Used by `BanxaConfig.baseURL` to build the partner-scoped API root.
    public var host: String {
        switch self {
        case .sandbox:    return "https://api.banxa-sandbox.com"
        case .production: return "https://api.banxa.com"
        case .preprod:    return "https://api.banxa-preprod.com"
        case .local:      return "http://localhost"
        }
    }
}

// MARK: - Config

/// Configuration values the partner provides to the SDK before starting a payment.
public struct BanxaConfig {
    public let apiKey: String
    public let partnerID: String
    public let environment: BanxaEnvironment
    public let primerSettings: PrimerSettings?
    
    /// Creates a config used by `BanxaPaymentSDK.configure(config:)`.
    /// - Parameters:
    ///   - apiKey: Banxa-issued API key sent as the `x-api-key` request header.
    ///   - partnerID: Partner slug used in the API base path (`/<partnerID>/v2`).
    ///   - environment: Banxa environment to hit. Defaults to `.sandbox`.
    ///   - primerSettings: Optional Primer settings forwarded as-is to `Primer.shared.configure`.
    public init(
        apiKey: String,
        partnerID: String,
        environment: BanxaEnvironment = .sandbox,
        primerSettings: PrimerSettings? = nil
    ) {
        self.apiKey = apiKey
        self.partnerID = partnerID
        self.environment = environment
        self.primerSettings = primerSettings
    }
    
    /// Fully-qualified API root for the partner: `<host>/<partnerID>/v2`.
    var baseURL: String { "\(environment.host)/\(partnerID)/v2" }
    
    /// Names of required credential fields that are missing or blank.
    /// Empty when both `apiKey` and `partnerID` are non-blank.
    var missingCredentialFields: [String] {
        var missing: [String] = []
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("apiKey")
        }
        if partnerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("partnerID")
        }
        return missing
    }
}

// MARK: - Delegate

/// Callbacks the SDK sends back to the partner for both Banxa flow events
/// and forwarded Primer drop-in checkout events.
@MainActor
public protocol BanxaPaymentSDKDelegate: AnyObject {}

/// Default no-op implementations make every method effectively optional.
public extension BanxaPaymentSDKDelegate {}

// MARK: - SDK

/// Headless Banxa payment SDK. Owns configuration, orchestrates the
/// eligibility -> create-order -> Primer drop-in flow, and forwards
/// Primer callbacks to the partner via `BanxaPaymentSDKDelegate`.
@MainActor
public final class BanxaPaymentSDK {
    public static let shared = BanxaPaymentSDK()
    public weak var delegate: BanxaPaymentSDKDelegate?
    
    private(set) var config: BanxaConfig?
    private let apiClient: APIClientProtocol
    
    /// Designated initializer. Tests can inject a stub `APIClient`.
    /// - Parameter apiClient: API client implementation. Defaults to `APIClient.shared`.
    private init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }
    
    /// Stores the partner's configuration and configures the underlying Primer SDK.
    /// Call once at app startup before invoking `startPayment(request:)`.
    /// - Parameter config: Partner credentials and optional Primer settings.
    public func configure(config: BanxaConfig) {
        self.config = config
        Primer.shared.configure(settings: config.primerSettings, delegate: self)
    }
    
    /// Kicks off the Banxa payment flow.
    ///
    /// Validates credentials, then runs eligibility check + create-order. If
    /// eligibility is ready and a `nativeToken` is returned, presents the
    /// Primer drop-in UI; otherwise hands the checkout URL back to the
    /// partner via `delegate.banxaDidReceiveCheckout(_:)`.
    /// - Parameter request: The order to be created.
    public func startPayment(request: CreateOrderRequest) {}
    
    /// Sequential async flow used by `startPayment(request:)`.
    /// - Parameters:
    ///   - request: The order to be created.
    ///   - config: Resolved partner configuration.
    private func runPaymentFlow(request: CreateOrderRequest, config: BanxaConfig) async {}
}

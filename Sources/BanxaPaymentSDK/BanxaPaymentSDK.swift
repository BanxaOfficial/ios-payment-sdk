// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import PrimerSDK
import UIKit

// MARK: - Environment

/// The Banxa backend environment a partner wants to target.
public enum BanxaEnvironment: Sendable {
    case sandbox
    case production
    case preprod
    
    /// Base host (scheme + domain) for the selected environment.
    /// Used by `BanxaConfig.baseURL` to build the partner-scoped API root.
    public var host: String {
        switch self {
        case .sandbox:    return "https://api.banxa-sandbox.com"
        case .production: return "https://api.banxa.com"
        case .preprod:    return "https://api.banxa-preprod.com"
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

// MARK: - Callback Types

/// Result of a successful checkout. Wraps the upstream provider payload
/// so partners never depend on the underlying payment provider SDK.
///
/// Native-flow completions populate `paymentId`, `orderId`, `status`.
/// Internal-WebView completions populate `rawQuery` with the query string
/// appended to the terminal success URL.
public struct BanxaCheckoutResult: Sendable {
    public let paymentId: String?
    public let orderId: String?
    public let status: String?
    public let rawQuery: String?

    public init(
        paymentId: String? = nil,
        orderId: String? = nil,
        status: String? = nil,
        rawQuery: String? = nil
    ) {
        self.paymentId = paymentId
        self.orderId = orderId
        self.status = status
        self.rawQuery = rawQuery
    }
}

// MARK: - Delegate

/// Callbacks the SDK sends back to the partner. All types are Banxa-owned —
/// partners never touch the underlying payment provider SDK.
@MainActor
public protocol BanxaPaymentSDKDelegate: AnyObject {

    /// Called when checkout completes successfully — from either the native
    /// in-app flow or the internal WebView flow.
    /// - Parameter result: Banxa-owned wrapper around the completed payment.
    func banxaDidCompleteCheckout(_ result: BanxaCheckoutResult)

    /// Called for any failure in the flow:
    /// - Banxa API errors (validation, network, decoding, `/eligibility` / `/buy` failures)
    /// - In-app checkout errors (card decline, 3DS failure, etc)
    /// - Internal WebView failure URL
    /// - Parameter error: The error describing the failure. Usually an `APIError`.
    func banxaDidFail(error: Error)

    /// Called when the user closes the checkout UI without completing.
    func banxaDidDismiss()
}

/// Default no-op implementations make every method effectively optional.
public extension BanxaPaymentSDKDelegate {
    func banxaDidCompleteCheckout(_ result: BanxaCheckoutResult) {}
    func banxaDidFail(error: Error) {}
    func banxaDidDismiss() {}
}

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
    init(apiClient: APIClientProtocol = APIClient.shared) {
        self.apiClient = apiClient
    }
    
    /// Stores the partner's configuration and configures the underlying Primer SDK.
    /// Call once at app startup before invoking `startPayment(request:)`.
    /// - Parameter config: Partner credentials and optional Primer settings.
    public func configure(config: BanxaConfig) {
        self.config = config
        Primer.shared.configure(settings: config.primerSettings, delegate: self)
    }
    
    /// Fetches the list of countries supported by Banxa (`GET /countries`).
    /// The list is the same for buy and sell orders.
    /// - Returns: Countries (and optional state subdivisions) available to this partner.
    /// - Throws: `APIError.sdkNotConfigured`, `APIError.missingCredentials`, or a
    ///   networking / decoding `APIError` from the Banxa API.
    public func fetchCountries() async throws -> [Country] {
        let config = try resolvedConfig()
        return try await apiClient.request(CountriesEndpoint(config: config))
    }
    
    /// Fetches fiat currencies supported by Banxa (`GET /fiats/{orderType}`).
    /// - Parameter orderType: `.buy` or `.sell` — availability can differ by order type.
    /// - Returns: Fiat currencies (with nested supported payment methods) for this partner.
    /// - Throws: `APIError.sdkNotConfigured`, `APIError.missingCredentials`, or a
    ///   networking / decoding `APIError` from the Banxa API.
    public func fetchFiats(orderType: OrderType) async throws -> [Fiat] {
        let config = try resolvedConfig()
        return try await apiClient.request(FiatsEndpoint(orderType: orderType, config: config))
    }
    
    /// Fetches cryptocurrencies supported by Banxa (`GET /crypto/{orderType}`).
    /// - Parameter orderType: `.buy` or `.sell` — availability can differ by order type.
    /// - Returns: Cryptocurrencies (with nested blockchain networks) for this partner.
    /// - Throws: `APIError.sdkNotConfigured`, `APIError.missingCredentials`, or a
    ///   networking / decoding `APIError` from the Banxa API.
    public func fetchCrypto(orderType: OrderType) async throws -> [Cryptocurrency] {
        let config = try resolvedConfig()
        return try await apiClient.request(CryptoEndpoint(orderType: orderType, config: config))
    }
    
    /// Fetches payment methods supported by Banxa (`GET /payment-methods/{orderType}`).
    /// - Parameters:
    ///   - orderType: `.buy` or `.sell` — availability can differ by order type.
    ///   - fiat: Optional fiat currency code to filter methods (e.g. `"USD"`).
    ///     When omitted, all payment methods for the order type are returned.
    /// - Returns: Payment methods (with supported fiat codes) for this partner.
    /// - Throws: `APIError.sdkNotConfigured`, `APIError.missingCredentials`, or a
    ///   networking / decoding `APIError` from the Banxa API.
    public func fetchPaymentMethods(orderType: OrderType, fiat: String? = nil) async throws -> [PaymentMethod] {
        let config = try resolvedConfig()
        return try await apiClient.request(
            PaymentMethodsEndpoint(orderType: orderType, fiat: fiat, config: config)
        )
    }
    
    /// Fetches a live quote from Banxa (`GET /quotes/{orderType}`).
    ///
    /// Banxa may return a single quote object or an array (when a discount code
    /// is applied). This method always normalizes the response to `[Quote]`.
    /// Do not cache quotes — call immediately before displaying a price.
    /// - Parameters:
    ///   - orderType: `.buy` or `.sell`.
    ///   - request: Fiat/crypto/payment method and amount parameters.
    /// - Returns: One or more quotes for the requested combination.
    /// - Throws: `APIError.sdkNotConfigured`, `APIError.missingCredentials`, or a
    ///   networking / decoding `APIError` from the Banxa API.
    public func fetchQuotes(orderType: OrderType, request: QuoteRequest) async throws -> [Quote] {
        let config = try resolvedConfig()
        let response: QuoteResponse = try await apiClient.request(
            QuotesEndpoint(orderType: orderType, request: request, config: config)
        )
        return response.quotes
    }
    
    /// Returns the configured `BanxaConfig`, or throws if the SDK has not been
    /// configured / is missing credentials.
    private func resolvedConfig() throws -> BanxaConfig {
        guard let config else {
            throw APIError.sdkNotConfigured
        }
        let missing = config.missingCredentialFields
        guard missing.isEmpty else {
            throw APIError.missingCredentials(missing)
        }
        return config
    }
    
    /// Kicks off the Banxa payment flow.
    ///
    /// Validates credentials, then runs eligibility check + create-order. If
    /// eligibility is ready and a `nativeToken` is returned, presents the
    /// Primer drop-in UI; otherwise hands the checkout URL back to the
    /// partner via `delegate.banxaDidReceiveCheckout(_:)`.
    /// - Parameter request: The order to be created.
    public func startPayment(request: CreateOrderRequest, controller: UIViewController) {
        guard let config else {
            delegate?.banxaDidFail(error: APIError.sdkNotConfigured)
            return
        }
        
        let missing = config.missingCredentialFields
        guard missing.isEmpty else {
            delegate?.banxaDidFail(error: APIError.missingCredentials(missing))
            return
        }
        
        Task { [weak self] in
            await self?.runPaymentFlow(request: request, config: config, controller: controller)
        }
    }
    
    /// Sequential async flow used by `startPayment(request:)`.
    /// - Parameters:
    ///   - request: The order to be created.
    ///   - config: Resolved partner configuration.
    private func runPaymentFlow(request: CreateOrderRequest, config: BanxaConfig, controller: UIViewController) async {
        do {
            let eligibility: EligibilityResponse = try await apiClient.request(
                CheckEligibilityEndpoint(request: request, config: config)
            )
            let order: CreateOrderResponse = try await apiClient.request(
                CreateOrderEndpoint(request: request, config: config)
            )
            
            if let token = order.nativeToken,
               !token.isEmpty,
               let banxaMethodID = request.paymentMethodID,
               !banxaMethodID.isEmpty {
                let primerType = mapToPrimerPaymentMethodType(banxaMethodID)
                Primer.shared.showPaymentMethod(
                    primerType,
                    intent: .checkout,
                    clientToken: token
                )
                
            } else if let url = order.checkoutUrl, !url.isEmpty {
                let vc = CheckoutWebViewController(
                    checkoutUrl: url, returnUrl: request.redirectURL,
                    onClose: { [weak self] in
                        self?.delegate?.banxaDidDismiss()
                    },
                    onSuccess: { [weak self] query in
                        self?.delegate?.banxaDidCompleteCheckout(
                            BanxaCheckoutResult(status: "success", rawQuery: query)
                        )
                    },
                    onFailure: { [weak self] query in
                        self?.delegate?.banxaDidFail(error: APIError.checkoutFailed(query))
                    },
                    returnUrlOnSuccess: "/status/",
                    returnUrlOnFailure: "/error/",
                    returnUrlOnCancelled: "/cancel/"
                )
                let navController = UINavigationController(rootViewController: vc)
                navController.modalPresentationStyle = .fullScreen
                controller.present(navController, animated: true)
            }
        } catch let error as APIError {
            delegate?.banxaDidFail(error: error)
        } catch {
            delegate?.banxaDidFail(error: APIError.unknown(error.localizedDescription))
        }
    }
    
    /// Maps a Banxa payment-method identifier (e.g. `"debit-credit-card"`,
    /// `"apple-pay"`) to the matching Primer payment-method-type constant
    /// (e.g. `"PAYMENT_CARD"`, `"APPLE_PAY"`). Unknown identifiers are
    /// returned unchanged so callers can pass through already-Primer values.
    private func mapToPrimerPaymentMethodType(_ banxaPaymentMethodID: String) -> String {
        switch banxaPaymentMethodID.lowercased() {
        case "debit-credit-card", "credit-card", "card", "primercc":
            return "PAYMENT_CARD"
        case "apple-pay":
            return "APPLE_PAY"
        case "google-pay":
            return "GOOGLE_PAY"
        case "paypal":
            return "PAYPAL"
        case "klarna":
            return "KLARNA"
        default:
            return banxaPaymentMethodID
        }
    }
}

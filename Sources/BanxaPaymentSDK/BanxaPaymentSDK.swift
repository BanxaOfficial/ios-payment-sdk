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

// MARK: - Delegate

/// Callbacks the SDK sends back to the partner for both Banxa flow events
/// and forwarded Primer drop-in checkout events.
@MainActor
public protocol BanxaPaymentSDKDelegate: AnyObject {
    // Banxa flow
    
    /// Called when the SDK has a checkout URL to hand back to the partner
    /// (paymentReady is false, or paymentReady is true but no nativeToken was returned).
    /// - Parameter response: The full create-order response from Banxa.
    func banxaDidReceiveCheckout(_ response: CreateOrderResponse)
    
    /// Called when the SDK has a checkout URL and need to execute the internal WebView.
    /// - Parameter status: the status and if any other query.
    func banxaDidWebViewCheckout(_ status: Bool, _ query: String?)
    
    /// Called for every URL navigation inside the internal checkout WebView,
    /// including intermediate steps (payment method picker, 3DS, status pages…).
    /// Use this to observe the full URL trail; the SDK still emits
    /// `banxaDidWebViewCheckout(_:_:)` separately for the final success/failure.
    /// - Parameter url: The URL the WebView is about to navigate to.
    func banxaWebViewDidNavigate(to url: URL)
    
    /// Called when the Banxa flow itself fails (validation, network, decoding, or API error).
    /// - Parameter error: The error describing the failure. Usually an `APIError`.
    func banxaDidFail(error: Error)
    
    /// Called when the user dismisses the Primer drop-in UI without completing checkout.
    func banxaDidDismiss()
    
    // Forwarded Primer callbacks
    
    /// Called when Primer drop-in checkout completes successfully.
    /// - Parameter data: The Primer checkout result payload.
    func banxaDidCompleteCheckout(_ data: PrimerCheckoutData)
    
    /// Called when Primer is about to refresh its client session.
    func banxaClientSessionWillUpdate()
    
    /// Called after Primer's client session has been refreshed.
    /// - Parameter clientSession: The updated client session.
    func banxaClientSessionDidUpdate(_ clientSession: PrimerClientSession)
    
    /// Called before Primer creates a payment. Use the decision handler to
    /// continue, abort with a custom error, or supply additional data.
    /// - Parameters:
    ///   - data: Payment method data Primer is about to submit.
    ///   - decisionHandler: Invoke exactly once to tell Primer how to proceed.
    func banxaWillCreatePayment(
        _ data: PrimerCheckoutPaymentMethodData,
        decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void
    )
    
    /// Called when Primer fails. Use the decision handler to provide a custom
    /// error message shown to the user.
    /// - Parameters:
    ///   - error: The error raised by Primer.
    ///   - data: Optional checkout data captured before the failure.
    ///   - decisionHandler: Invoke exactly once with a `PrimerErrorDecision`.
    func banxaDidFailWithError(
        _ error: Error,
        data: PrimerCheckoutData?,
        decisionHandler: @escaping (PrimerErrorDecision) -> Void
    )
    
    /// Called when Primer has tokenized a payment method.
    /// - Parameters:
    ///   - tokenData: Token information returned by Primer.
    ///   - decisionHandler: Invoke exactly once to resume or fail the flow.
    func banxaDidTokenizePaymentMethod(
        _ tokenData: PrimerPaymentMethodTokenData,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    )
    
    /// Called when Primer needs to resume the payment with a server token (e.g. 3DS).
    /// - Parameters:
    ///   - resumeToken: Resume token issued by Primer's backend.
    ///   - decisionHandler: Invoke exactly once to resume or fail the flow.
    func banxaDidResumeWith(
        _ resumeToken: String,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    )
    
    /// Called when the payment enters a pending state and Primer has supplemental info.
    /// - Parameter additionalInfo: Optional extra payload describing the pending state.
    func banxaDidEnterResumePending(_ additionalInfo: PrimerCheckoutAdditionalInfo?)
}

/// Default no-op implementations make every method effectively optional.
public extension BanxaPaymentSDKDelegate {
    func banxaDidReceiveCheckout(_ response: CreateOrderResponse) {}
    func banxaDidWebViewCheckout(_ status: Bool, _ query: String?) {}
    func banxaWebViewDidNavigate(to url: URL) {}
    func banxaDidFail(error: Error) {}
    func banxaDidDismiss() {}
    func banxaDidCompleteCheckout(_ data: PrimerCheckoutData) {}
    func banxaClientSessionWillUpdate() {}
    func banxaClientSessionDidUpdate(_ clientSession: PrimerClientSession) {}
    func banxaWillCreatePayment(
        _ data: PrimerCheckoutPaymentMethodData,
        decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void
    ) {
        decisionHandler(.continuePaymentCreation())
    }
    func banxaDidFailWithError(
        _ error: Error,
        data: PrimerCheckoutData?,
        decisionHandler: @escaping (PrimerErrorDecision) -> Void
    ) {
        decisionHandler(.fail(withErrorMessage: nil))
    }
    func banxaDidTokenizePaymentMethod(
        _ tokenData: PrimerPaymentMethodTokenData,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {}
    func banxaDidResumeWith(
        _ resumeToken: String,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {}
    func banxaDidEnterResumePending(_ additionalInfo: PrimerCheckoutAdditionalInfo?) {}
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
                print("[Banxa] showPaymentMethod -> banxaID:", banxaMethodID,
                      "primerType:", primerType,
                      "tokenLen:", token.count)
                Primer.shared.showPaymentMethod(
                    primerType,
                    intent: .checkout,
                    clientToken: token
                )
                
            } else if let url = order.checkoutUrl, !url.isEmpty {
                let vc = CheckoutWebViewController(
                    checkoutUrl: url, returnUrl: request.redirectURL,
                    onClose: {
                        self.delegate?.banxaDidDismiss()
                    }, onNavigationStateChange: { [weak self] url in
                        self?.delegate?.banxaWebViewDidNavigate(to: url)
                    },
                    onSuccess: { status in
                        self.delegate?.banxaDidWebViewCheckout(true, status)
                    },
                    onFailure: { status in
                        self.delegate?.banxaDidWebViewCheckout(false, status)
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

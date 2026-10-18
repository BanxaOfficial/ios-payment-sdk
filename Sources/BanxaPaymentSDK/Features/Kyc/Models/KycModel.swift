//
//  KycModel.swift
//  BanxaPaymentSDK
//

import Foundation

/// Verification level requested for a hosted KYC session.
public enum KycTier: String, Codable, Sendable {
    case standard
    /// Accepted by the API, but Banxa may still apply a stricter level.
    case express
    case enhanced
}

/// Request payload for `POST /kyc/sessions`.
public struct CreateKycSessionRequest: Encodable, Equatable, Sendable {
    public var externalCustomerID: String
    public var tier: KycTier?
    public var country: String?
    public var returnURL: String?

    enum CodingKeys: String, CodingKey {
        case externalCustomerID = "externalCustomerId"
        case tier
        case country
        case returnURL = "returnUrl"
    }

    /// Creates a KYC session request. Fields left `nil` are omitted from the body.
    /// - Parameters:
    ///   - externalCustomerID: Partner-side customer id. Sessions are reused per id for an hour.
    ///   - tier: Verification level. Banxa defaults to `.standard`.
    ///   - country: Two-letter country code (e.g. `"AU"`).
    ///   - returnURL: URL or deep link (e.g. `"myapp://kyc-done"`) the flow returns to when it ends.
    public init(
        externalCustomerID: String,
        tier: KycTier? = nil,
        country: String? = nil,
        returnURL: String? = nil
    ) {
        self.externalCustomerID = externalCustomerID
        self.tier = tier
        self.country = country
        self.returnURL = returnURL
    }
}

/// A hosted KYC session link returned by `POST /kyc/sessions`.
public struct KycSession: Codable, Equatable, Sendable {
    public let redirectURL: String
    /// ISO-8601 time the link stops working. Kept as a string so an unexpected format can't fail the decode.
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case redirectURL = "redirectUrl"
        case expiresAt
    }

    /// Creates a session from values your backend received from Banxa.
    /// - Parameters:
    ///   - redirectURL: The session's `redirectUrl`.
    ///   - expiresAt: The session's `expiresAt`.
    public init(redirectURL: String, expiresAt: String) {
        self.redirectURL = redirectURL
        self.expiresAt = expiresAt
    }

    /// `expiresAt` as a `Date`, or `nil` when it isn't valid ISO-8601.
    public var expirationDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }
}

/// Outcome of a hosted KYC flow that reached its end.
public struct BanxaKycResult: Equatable, Sendable {
    /// How the SDK learned the flow had ended.
    public enum Channel: Equatable, Sendable {
        /// The hosted flow posted a `banxa:kyc-complete` message.
        case message
        /// The hosted flow navigated to the return URL.
        case returnURL
    }

    /// The status the hosted flow reported, or `"complete"` when it gave none.
    /// The final verification result reaches your backend by webhook.
    public let status: String
    public let channel: Channel

    public init(status: String, channel: Channel) {
        self.status = status
        self.channel = channel
    }
}

/// A `banxa:*` message the SDK received but refused.
public struct BanxaKycRejectedMessage: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// The sender's origin isn't the session's origin or one of `allowedOrigins`.
        case origin
        /// The message came from an embedded frame rather than the page itself.
        case frame
    }

    public let reason: Reason
    public let type: String
    public let origin: String

    public init(reason: Reason, type: String, origin: String) {
        self.reason = reason
        self.type = type
        self.origin = origin
    }
}

/// Errors from presenting or running the hosted KYC flow.
/// Failures from `createKycSession(request:)` itself are thrown as `APIError`.
public enum BanxaKycError: LocalizedError, Equatable {
    case sessionExpired
    case invalidSessionURL
    case unsupportedOSVersion
    /// The host app's `Info.plist` is missing these camera / microphone usage keys.
    case missingUsageDescription([String])
    /// The hosted flow reported an error.
    case flowError(code: String?, message: String?)

    public var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "The KYC session has expired. Create a new session."
        case .invalidSessionURL:
            return "The KYC session's redirect URL is not a valid https URL."
        case .unsupportedOSVersion:
            return "Hosted KYC needs iOS 14.3 or later."
        case .missingUsageDescription(let keys):
            return "Add these keys to your app's Info.plist: \(keys.joined(separator: ", "))"
        case .flowError(let code, let message):
            let detail = message.flatMap { $0.isEmpty ? nil : $0 } ?? "KYC flow error"
            guard let code else { return detail }
            return "\(detail) (\(code))"
        }
    }
}

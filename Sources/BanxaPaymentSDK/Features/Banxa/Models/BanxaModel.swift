//
//  CreateOrder.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//
//

/// Request payload for both `/eligibility` and `/buy`.
public struct CreateOrderRequest: Identifiable, Codable, Equatable, Sendable {
    public var id: String?
    public var paymentMethodID: String?
    public var crypto: String
    public var blockchain: String?
    public var fiat: String
    public var fiatAmount: String
    public var cryptoAmount: String?
    public var walletAddress: String
    public var walletAddressTag: String?
    public var redirectURL: String
    public var subPartnerID: String?
    public var metadata: String?
    public var externalCustomerID: String?
    public var externalOrderID: String?
    public var discountCode: String?
    public let email: String
    
    enum  CodingKeys: String, CodingKey {
        case id
        case paymentMethodID = "paymentMethodId"
        case crypto = "crypto"
        case blockchain = "blockchain"
        case fiat = "fiat"
        case fiatAmount = "fiatAmount"
        case cryptoAmount = "cryptoAmount"
        case walletAddress = "walletAddress"
        case walletAddressTag = "walletAddressTag"
        case subPartnerID = "subPartnerId"
        case metadata = "metadata"
        case redirectURL = "redirectUrl"
        case externalCustomerID = "externalCustomerId"
        case externalOrderID = "externalOrderId"
        case discountCode = "discountCode"
        case email = "email"
    }
    
    /// Memberwise initializer with sensible defaults for optional fields.
    /// - Parameters:
    ///   - paymentMethodID: Banxa payment method id (e.g. `"apple-pay"`).
    ///   - crypto: Crypto asset symbol the user wants to buy (e.g. `"ETH"`).
    ///   - fiat: Fiat currency code being spent (e.g. `"EUR"`).
    ///   - fiatAmount: Fiat amount as a string (e.g. `"40"`).
    ///   - walletAddress: Destination wallet address.
    ///   - email: End-user's email address.
    ///   - redirectURL: URL Banxa redirects to after hosted checkout.
    ///   - id: Optional partner-supplied order id.
    ///   - blockchain: Optional explicit blockchain network.
    ///   - cryptoAmount: Optional crypto amount when ordering by crypto value.
    ///   - walletAddressTag: Optional tag/memo for chains that require it.
    ///   - subPartnerID: Optional sub-partner identifier.
    ///   - metadata: Optional opaque metadata string.
    ///   - externalCustomerID: Optional partner-side customer id.
    ///   - externalOrderID: Optional partner-side order id.
    ///   - discountCode: Optional promo / discount code.
    public init(
        crypto: String,
        fiat: String,
        fiatAmount: String,
        walletAddress: String,
        email: String,
        redirectURL: String,
        
        paymentMethodID: String? = nil,
        id: String? = nil,
        blockchain: String? = nil,
        cryptoAmount: String? = nil,
        walletAddressTag: String? = nil,
        subPartnerID: String? = nil,
        metadata: String? = nil,
        externalCustomerID: String? = nil,
        externalOrderID: String? = nil,
        discountCode: String? = nil
    ) {
        self.id = id
        self.paymentMethodID = paymentMethodID
        self.crypto = crypto
        self.fiat = fiat
        self.fiatAmount = fiatAmount
        self.walletAddress = walletAddress
        self.email = email
        
        self.blockchain = blockchain
        self.cryptoAmount = cryptoAmount
        self.walletAddressTag = walletAddressTag
        self.redirectURL = redirectURL
        self.subPartnerID = subPartnerID
        self.metadata = metadata
        self.externalCustomerID = externalCustomerID
        self.externalOrderID = externalOrderID
        self.discountCode = discountCode
    }
}

/// Response from `POST /buy`. Mirrors the Banxa `Order` schema.
public struct CreateOrderResponse: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let externalCustomerID: String?
    public let externalOrderID: String?
    public let orderType: String?
    public let fiat: String?
    public let fiatAmount: String?
    public let crypto: String?
    public let cryptoAmount: String?
    public let walletAddress: String?
    public let walletAddressTag: String?
    public let paymentMethodID: Int?
    public let paymentMethodType: String?
    public let status: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let checkoutUrl: String?
    public let nativeToken: String?
    public let blockchain: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case externalCustomerID = "externalCustomerId"
        case externalOrderID = "externalOrderId"
        case orderType
        case fiat
        case fiatAmount
        case crypto
        case cryptoAmount
        case walletAddress
        case walletAddressTag
        case paymentMethodID = "paymentMethodId"
        case paymentMethodType
        case status
        case createdAt
        case updatedAt
        case checkoutUrl
        case nativeToken
        case blockchain
    }
}

/// Response from `POST /eligibility`. `paymentReady` decides whether
/// the SDK presents Primer drop-in or hands a checkout URL to the partner.
public struct EligibilityResponse: Identifiable, Codable, Equatable, Sendable {
    public let id: String?
    public let paymentReady: Bool?
    public let kycRequirements: [String]?
}

// MARK: - Order type

/// Buy (on-ramp) or sell (off-ramp). Used as the `{orderType}` path segment on
/// configuration endpoints such as `/fiats/{orderType}`.
public enum OrderType: String, Codable, Sendable {
    case buy
    case sell
}

// MARK: - Countries

/// A subdivision (state / province) nested under a `Country`.
public struct CountryState: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let description: String
}

/// A country supported by Banxa, as returned by `GET /countries`.
public struct Country: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let description: String
    public let states: [CountryState]?
}

// MARK: - Fiats

/// A payment method available for a fiat currency, as nested under `Fiat`.
public struct FiatPaymentMethod: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let minimum: String?
    public let maximum: String?
}

/// A fiat currency supported by Banxa, as returned by `GET /fiats/{orderType}`.
public struct Fiat: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let description: String?
    public let symbol: String?
    public let supportedPaymentMethods: [FiatPaymentMethod]?
}

// MARK: - Crypto

/// A blockchain network associated with a cryptocurrency.
public struct CryptoBlockchain: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let description: String?
    public let isDefaultBlockchain: Bool?
    public let address: String?
    public let network: String?
    public let minimum: String?
    /// Country / state restrictions keyed by ISO country code
    /// (e.g. `["US": ["NY"], "CA": []]`).
    public let unsupportedCountries: [String: [String]]?
}

/// A cryptocurrency supported by Banxa, as returned by `GET /crypto/{orderType}`.
public struct Cryptocurrency: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let description: String?
    public let blockchains: [CryptoBlockchain]?
}

// MARK: - Payment methods

/// A payment method supported by Banxa, as returned by
/// `GET /payment-methods/{orderType}`.
public struct PaymentMethod: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
    public let supportedFiats: [String]?
}

// MARK: - Quotes

/// Query parameters for `GET /quotes/{orderType}`.
/// Provide either `fiatAmount` or `cryptoAmount` (or both — Banxa prefers crypto).
public struct QuoteRequest: Equatable, Sendable {
    public let paymentMethodID: String
    public let crypto: String
    public let blockchain: String
    public let fiat: String
    public let fiatAmount: String?
    public let cryptoAmount: String?
    public let externalCustomerID: String?
    public let ipAddress: String?
    public let discountCode: String?
    
    /// Creates a quote request.
    /// - Parameters:
    ///   - paymentMethodID: Banxa payment method id (e.g. `"debit-credit-card"`).
    ///   - crypto: Crypto asset symbol (e.g. `"ETH"`).
    ///   - blockchain: Blockchain network for the asset (e.g. `"ETH"`).
    ///   - fiat: Fiat currency code (e.g. `"USD"`).
    ///   - fiatAmount: Fiat amount to spend/receive. Provide this and/or `cryptoAmount`.
    ///   - cryptoAmount: Crypto amount. When both amounts are set, Banxa uses crypto.
    ///   - externalCustomerID: Optional partner-side customer id for tailored pricing.
    ///   - ipAddress: Optional customer IP for regional availability checks.
    ///   - discountCode: Optional promo / discount code.
    public init(
        paymentMethodID: String,
        crypto: String,
        blockchain: String,
        fiat: String,
        fiatAmount: String? = nil,
        cryptoAmount: String? = nil,
        externalCustomerID: String? = nil,
        ipAddress: String? = nil,
        discountCode: String? = nil
    ) {
        self.paymentMethodID = paymentMethodID
        self.crypto = crypto
        self.blockchain = blockchain
        self.fiat = fiat
        self.fiatAmount = fiatAmount
        self.cryptoAmount = cryptoAmount
        self.externalCustomerID = externalCustomerID
        self.ipAddress = ipAddress
        self.discountCode = discountCode
    }
}

/// Pre-discount amounts nested under `QuoteDiscount`.
/// Note: Banxa's wire key for the original network fee is misspelled
/// (`orginalNetworkFee`); it is mapped to `originalNetworkFee` here.
public struct QuoteOriginalAmounts: Codable, Equatable, Sendable {
    public let originalCryptoAmount: String?
    public let originalNetworkFee: String?
    public let originalProcessingFee: String?
    public let originalFiatAmount: String?
    
    enum CodingKeys: String, CodingKey {
        case originalCryptoAmount
        case originalNetworkFee = "orginalNetworkFee"
        case originalProcessingFee
        case originalFiatAmount
    }
}

/// Discount details included when a discount code was applied to the quote.
public struct QuoteDiscount: Codable, Equatable, Sendable {
    public let originalQuote: QuoteOriginalAmounts?
    public let discountCode: String?
}

/// A live quote returned by `GET /quotes/{orderType}`.
public struct Quote: Codable, Equatable, Sendable {
    public let paymentMethodID: String?
    public let cryptoAmount: String?
    public let fiatAmount: String?
    public let processingFee: String?
    public let networkFee: String?
    public let discount: QuoteDiscount?
    
    enum CodingKeys: String, CodingKey {
        case paymentMethodID = "paymentMethodId"
        case cryptoAmount
        case fiatAmount
        case processingFee
        case networkFee
        case discount
    }
}

/// Decodes Banxa's quote response, which may be a single object or an array.
struct QuoteResponse: Decodable, Sendable {
    let quotes: [Quote]
    
    init(quotes: [Quote]) {
        self.quotes = quotes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([Quote].self) {
            quotes = list
        } else {
            quotes = [try container.decode(Quote.self)]
        }
    }
}

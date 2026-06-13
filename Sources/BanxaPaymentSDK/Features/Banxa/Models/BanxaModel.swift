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
    public var paymentMethodID: String
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
        paymentMethodID: String,
        crypto: String,
        fiat: String,
        fiatAmount: String,
        walletAddress: String,
        email: String,
        redirectURL: String,
        
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

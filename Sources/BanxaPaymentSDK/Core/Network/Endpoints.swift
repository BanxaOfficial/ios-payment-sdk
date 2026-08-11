//
//  Endpoints.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//

import Foundation

/// Describes a single Banxa HTTP endpoint. Conformers contribute the
/// URL parts plus method, headers, and request body.
public protocol Endpoint: Sendable {
    var baseURL: String { get }
    var path: String { get }
    var method: String { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    /// Optional query string parameters appended when building the request.
    var queryItems: [URLQueryItem] { get }
}

public extension Endpoint {
    var body: Data? { nil }
    var queryItems: [URLQueryItem] { [] }
    
    /// Builds a `URLRequest` from the endpoint properties.
    /// - Returns: A configured `URLRequest` ready to be sent.
    /// - Throws: `APIError.invalidURL` if `baseURL + path` does not form a valid URL.
    func buildRequest() throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.httpBody = body
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        return r
    }
}

/// Default headers every Banxa endpoint uses.
/// - Parameter apiKey: Banxa-issued API key sent as `x-api-key`.
/// - Returns: Header dictionary with `Content-Type` and `x-api-key`.
private func banxaHeaders(apiKey: String) -> [String: String] {
    [
        "Content-Type": "application/json",
        "x-api-key": apiKey
    ]
}

/// JSON-encodes a request body using the type's own `CodingKeys`.
/// - Parameter value: Any `Encodable` payload.
/// - Returns: Encoded data, or `nil` if encoding throws.
private func encodeBody<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder().encode(value)
}

/// `POST /buy` — creates a fiat-to-crypto order.
public struct CreateOrderEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public var path: String { "/buy" }
    public var method: String { "POST" }
    public var body: Data?
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - request: The order payload to send.
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(request: CreateOrderRequest, config: BanxaConfig) {
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
        self.body = encodeBody(request)
    }
}

/// `POST /eligibility` — checks whether the order can be processed in-app
/// (paymentReady) or needs the hosted Banxa checkout URL.
public struct CheckEligibilityEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public var path: String { "/eligibility" }
    public var method: String { "POST" }
    public var body: Data?
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - request: The order payload to evaluate.
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(request: CreateOrderRequest, config: BanxaConfig) {
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
        self.body = encodeBody(request)
    }
}

/// `GET /countries` — retrieves countries supported by Banxa.
public struct CountriesEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public var path: String { "/countries" }
    public var method: String { "GET" }
    
    /// Creates the endpoint.
    /// - Parameter config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(config: BanxaConfig) {
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
    }
}

/// `GET /fiats/{orderType}` — retrieves fiat currencies supported by Banxa.
public struct FiatsEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public let orderType: OrderType
    public var path: String { "/fiats/\(orderType.rawValue)" }
    public var method: String { "GET" }
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - orderType: Buy or sell — selects which fiat list Banxa returns.
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(orderType: OrderType, config: BanxaConfig) {
        self.orderType = orderType
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
    }
}

/// `GET /crypto/{orderType}` — retrieves cryptocurrencies supported by Banxa.
public struct CryptoEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public let orderType: OrderType
    public var path: String { "/crypto/\(orderType.rawValue)" }
    public var method: String { "GET" }
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - orderType: Buy or sell — selects which crypto list Banxa returns.
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(orderType: OrderType, config: BanxaConfig) {
        self.orderType = orderType
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
    }
}

/// `GET /payment-methods/{orderType}` — retrieves payment methods supported by Banxa.
public struct PaymentMethodsEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public let orderType: OrderType
    public let fiat: String?
    public var path: String { "/payment-methods/\(orderType.rawValue)" }
    public var method: String { "GET" }
    public var queryItems: [URLQueryItem] {
        guard let fiat, !fiat.isEmpty else { return [] }
        return [URLQueryItem(name: "fiat", value: fiat)]
    }
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - orderType: Buy or sell — selects which payment-method list Banxa returns.
    ///   - fiat: Optional fiat currency code to filter methods (e.g. `"USD"`).
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(orderType: OrderType, fiat: String? = nil, config: BanxaConfig) {
        self.orderType = orderType
        self.fiat = fiat
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
    }
}

/// `GET /quotes/{orderType}` — retrieves a live quote for a fiat/crypto pair.
public struct QuotesEndpoint: Endpoint {
    public let baseURL: String
    public let headers: [String: String]
    public let orderType: OrderType
    public let request: QuoteRequest
    public var path: String { "/quotes/\(orderType.rawValue)" }
    public var method: String { "GET" }
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "paymentMethodId", value: request.paymentMethodID),
            URLQueryItem(name: "crypto", value: request.crypto),
            URLQueryItem(name: "blockchain", value: request.blockchain),
            URLQueryItem(name: "fiat", value: request.fiat)
        ]
        if let fiatAmount = request.fiatAmount {
            items.append(URLQueryItem(name: "fiatAmount", value: fiatAmount))
        }
        if let cryptoAmount = request.cryptoAmount {
            items.append(URLQueryItem(name: "cryptoAmount", value: cryptoAmount))
        }
        if let externalCustomerID = request.externalCustomerID {
            items.append(URLQueryItem(name: "externalCustomerId", value: externalCustomerID))
        }
        if let ipAddress = request.ipAddress {
            items.append(URLQueryItem(name: "ipAddress", value: ipAddress))
        }
        if let discountCode = request.discountCode {
            items.append(URLQueryItem(name: "discountCode", value: discountCode))
        }
        return items
    }
    
    /// Creates the endpoint.
    /// - Parameters:
    ///   - orderType: Buy or sell.
    ///   - request: Quote query parameters (fiat/crypto/payment method/amounts).
    ///   - config: Partner config used to derive `baseURL` and `x-api-key` header.
    init(orderType: OrderType, request: QuoteRequest, config: BanxaConfig) {
        self.orderType = orderType
        self.request = request
        self.baseURL = config.baseURL
        self.headers = banxaHeaders(apiKey: config.apiKey)
    }
}

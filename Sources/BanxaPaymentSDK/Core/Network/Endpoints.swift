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
}

public extension Endpoint {
    var body: Data? { nil }
    
    /// Builds a `URLRequest` from the endpoint properties.
    /// - Returns: A configured `URLRequest` ready to be sent.
    /// - Throws: `APIError.invalidURL` if `baseURL + path` does not form a valid URL.
    func buildRequest() throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
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

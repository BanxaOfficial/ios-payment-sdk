//
//  APIClient.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//

import Foundation

/// Abstraction over the network layer. Lets `BanxaPaymentSDK` be tested
/// with a stub client.
public protocol APIClientProtocol: Sendable {
    /// Sends an `Endpoint` and decodes the response.
    /// - Parameter endpoint: The endpoint describing the request.
    /// - Returns: A decoded value of type `T`.
    /// - Throws: `APIError` describing the failure (invalid URL, network,
    ///   non-2xx status, or decoding error).
    func request<T: Decodable & Sendable>(_ endpoint: any Endpoint) async throws -> T
}

/// Concrete `APIClientProtocol` backed by `URLSession` and `JSONDecoder`.
public final class APIClient: APIClientProtocol, @unchecked Sendable {
    public static let shared = APIClient()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    /// Creates an API client.
    /// - Parameter session: The `URLSession` used for requests. Defaults to `.shared`.
    public init(session: URLSession = .shared) {
        self.session = session
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    /// Builds a `URLRequest` from the endpoint, performs the network call,
    /// validates the HTTP status, and decodes the response body into `T`.
    /// In DEBUG builds the request and response are logged via `NetworkLogger`.
    /// - Parameter endpoint: The endpoint describing the request.
    /// - Returns: The decoded response.
    /// - Throws: `APIError.invalidURL`, `APIError.networkUnavailable`,
    ///   `APIError.unauthorized`, `APIError.serverError`, or
    ///   `APIError.decodingFailed`.
    public func request<T: Decodable & Sendable>(_ endpoint: any Endpoint) async throws -> T {
        let urlRequest = try endpoint.buildRequest()
        
#if DEBUG
        NetworkLogger.logRequest(urlRequest)
#endif
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            switch (error as NSError).code {
            case NSURLErrorNotConnectedToInternet:
                throw APIError.networkUnavailable
            case NSURLErrorTimedOut:
                throw APIError.serverError(408)
            default:
                throw APIError.unknown(error.localizedDescription)
            }
        }
        
        let httpResponse = response as? HTTPURLResponse
        
#if DEBUG
        NetworkLogger.logResponse(data, request: urlRequest, response: httpResponse)
#endif
        
        guard let http = httpResponse else {
            throw APIError.networkUnavailable
        }
        
        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw APIError.unauthorized
        case 422:
            // Banxa returns structured validation errors on these status codes.
            // Try to surface them as `.validation`; fall through to `.serverError`
            // if the body doesn't match the expected shape.
            if let parsed = try? decoder.decode(BanxaErrorResponse.self, from: data),
               parsed.errors != nil || parsed.message != nil {
                throw APIError.validation(
                    statusCode: http.statusCode,
                    message: parsed.message,
                    fieldErrors: parsed.errors ?? [:]
                )
            }
            throw APIError.serverError(http.statusCode)
        default:
            throw APIError.serverError(http.statusCode)
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
    
}

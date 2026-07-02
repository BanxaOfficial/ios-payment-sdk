//
//  Models.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//

import Foundation

/// Errors surfaced by the SDK's networking and configuration layers.
public enum APIError: LocalizedError {
    case invalidURL
    case serverError(Int)
    /// Validation error returned by the Banxa API (typically HTTP 400 / 422).
    /// `statusCode` is the HTTP status. `message` is the top-level `message`
    /// from the response body. `fieldErrors` is the per-field breakdown
    /// under `errors` (e.g. `["paymentMethodId": ["…"]]`).
    case validation(statusCode: Int, message: String?, fieldErrors: [String: [String]])
    case unauthorized
    case decodingFailed(String)
    case networkUnavailable
    case missingCredentials([String])
    case sdkNotConfigured
    case unknown(String)
    
    /// Human-readable description suitable for surfacing to the partner.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .serverError(let code):
            return "Server error: \(code)"
        case .validation(let statusCode, let message, let fieldErrors):
            let flat = fieldErrors
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value.joined(separator: " "))" }
                .joined(separator: "; ")
            if !flat.isEmpty, let message {
                return "\(message) (\(statusCode)) — \(flat)"
            }
            if !flat.isEmpty {
                return "Validation error (\(statusCode)) — \(flat)"
            }
            return message ?? "Validation error (\(statusCode))"
        case .unauthorized:
            return "Unauthorized"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .networkUnavailable:
            return "No internet connection."
        case .missingCredentials(let fields):
            return "Missing required credentials: \(fields.joined(separator: ", "))"
        case .sdkNotConfigured:
            return "BanxaPaymentSDK is not configured. Call configure(config:) first."
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

/// Wire-level shape of Banxa's validation error responses (HTTP 400/422).
/// Matches `{ "errors": {"paymentMethodId": ["…"]}, "message": "…" }`.
struct BanxaErrorResponse: Decodable {
    let errors: [String: [String]]?
    let message: String?
}

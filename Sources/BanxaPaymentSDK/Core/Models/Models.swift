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

//
//  NetworkLogger.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 13/06/26.
//

import Foundation

/// Helpers that print full HTTP request/response details in DEBUG builds.
enum NetworkLogger {
    /// Prints the outgoing request's URL, method, headers, and pretty-printed body.
    /// - Parameter request: The `URLRequest` about to be sent.
    static func logRequest(_ request: URLRequest) {
        let url = request.url?.absoluteString ?? "<no url>"
        let method = request.httpMethod ?? "<no method>"
        let headers = formatHeaders(request.allHTTPHeaderFields)
        let body = formatBody(request.httpBody)
        print("""
        ========================
        API REQUEST
        ========================
        URL:     \(url)
        Method:  \(method)
        Headers: \(headers)
        Body:    \(body)
        ========================
        """)
    }
    
    /// Prints the response URL, status code, headers, and pretty-printed body.
    /// - Parameters:
    ///   - data: Raw response body bytes.
    ///   - request: The originating `URLRequest`, used to print the URL.
    ///   - response: Optional `HTTPURLResponse`; status and headers are skipped if `nil`.
    static func logResponse(_ data: Data, request: URLRequest, response: HTTPURLResponse?) {
        let url = request.url?.absoluteString ?? "<no url>"
        let status = response.map { "\($0.statusCode)" } ?? "<no status>"
        let headers = formatHeaders(response?.allHeaderFields as? [String: String])
        let body = formatBody(request.httpBody)
        let response = formatBody(data)
        print("""
        ========================
        API RESPONSE
        ========================
        URL:     \(url)
        Status:  \(status)
        Headers: \(headers)
        Body:    \(body)
        Response:    \(response)
        ========================
        """)
    }
    
    /// Formats a header dictionary as an indented, alphabetically-sorted multiline string.
    /// - Parameter headers: Headers to print, or `nil`/empty.
    /// - Returns: `"<none>"` when empty, otherwise a newline-prefixed listing.
    private static func formatHeaders(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "<none>" }
        return "\n" + headers
            .sorted { $0.key < $1.key }
            .map { "    \($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
    
    /// Pretty-prints JSON when possible, otherwise falls back to UTF-8 text or a byte count.
    /// - Parameter data: Body data to format, or `nil`/empty.
    /// - Returns: A human-readable string representation.
    private static func formatBody(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "<empty>" }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: pretty, encoding: .utf8) {
            return "\n" + json
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }
}

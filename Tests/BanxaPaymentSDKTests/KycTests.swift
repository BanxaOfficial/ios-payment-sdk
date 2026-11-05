import Foundation
import Testing
@testable import BanxaPaymentSDK

// MARK: - Stub API client

private final class KycStubAPIClient: APIClientProtocol, @unchecked Sendable {
    var lastEndpoint: (any Endpoint)?
    var result: Result<Any, Error> = .failure(APIError.unknown("unset"))

    func request<T: Decodable & Sendable>(_ endpoint: any Endpoint) async throws -> T {
        lastEndpoint = endpoint
        switch result {
        case .success(let value):
            guard let typed = value as? T else {
                throw APIError.decodingFailed("Stub returned \(type(of: value)), expected \(T.self)")
            }
            return typed
        case .failure(let error):
            throw error
        }
    }
}

private func makeKycConfig(apiKey: String = "test-key", partnerID: String = "demo-partner") -> BanxaConfig {
    BanxaConfig(apiKey: apiKey, partnerID: partnerID, environment: .sandbox)
}

private let sessionURL = "https://kyc.banxa-sandbox.com/kyc/abc123?token=xyz"
private let sessionOrigin = "https://kyc.banxa-sandbox.com"
private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func makeSession(redirectURL: String = sessionURL, expiresIn seconds: TimeInterval = 3600) -> KycSession {
    let formatter = ISO8601DateFormatter()
    return KycSession(redirectURL: redirectURL, expiresAt: formatter.string(from: now.addingTimeInterval(seconds)))
}

private func makeMonitor(
    session: KycSession = makeSession(),
    returnURL: String? = nil,
    allowedOrigins: [String] = []
) -> HostedKycSessionMonitor {
    HostedKycSessionMonitor(session: session, returnURL: returnURL, allowedOrigins: allowedOrigins, now: now)
}

private func jsonObject(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - CreateKycSessionEndpoint

@Suite("CreateKycSessionEndpoint")
struct CreateKycSessionEndpointTests {

    @Test("builds POST /kyc/sessions against the partner base URL")
    func buildsRequest() throws {
        let request = try CreateKycSessionEndpoint(
            request: CreateKycSessionRequest(externalCustomerID: "cust-1"),
            config: makeKycConfig()
        ).buildRequest()

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.banxa-sandbox.com/demo-partner/v2/kyc/sessions")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("encodes every field with the API's key names")
    func encodesAllFields() throws {
        let request = try CreateKycSessionEndpoint(
            request: CreateKycSessionRequest(
                externalCustomerID: "cust-1",
                tier: .enhanced,
                country: "AU",
                returnURL: "myapp://kyc-done"
            ),
            config: makeKycConfig()
        ).buildRequest()

        let body = try jsonObject(request.httpBody)

        #expect(body["externalCustomerId"] as? String == "cust-1")
        #expect(body["tier"] as? String == "enhanced")
        #expect(body["country"] as? String == "AU")
        #expect(body["returnUrl"] as? String == "myapp://kyc-done")
        #expect(body.count == 4)
    }

    @Test("leaves nil optionals out of the body instead of sending null")
    func omitsNilOptionals() throws {
        let request = try CreateKycSessionEndpoint(
            request: CreateKycSessionRequest(externalCustomerID: "cust-1"),
            config: makeKycConfig()
        ).buildRequest()

        let body = try jsonObject(request.httpBody)

        #expect(body.keys.sorted() == ["externalCustomerId"])
    }

    @Test("sends a long externalCustomerId unchanged")
    func keepsLongCustomerID() throws {
        let longID = String(repeating: "a", count: 255)
        let request = try CreateKycSessionEndpoint(
            request: CreateKycSessionRequest(externalCustomerID: longID),
            config: makeKycConfig()
        ).buildRequest()

        let body = try jsonObject(request.httpBody)

        #expect(body["externalCustomerId"] as? String == longID)
    }
}

// MARK: - KycSession decoding

@Suite("KycSession decoding")
struct KycSessionDecodingTests {

    @Test("decodes the unwrapped session body")
    func decodesUnwrappedBody() throws {
        let json = """
        { "redirectUrl": "https://kyc.banxa.com/kyc/abc", "expiresAt": "2026-09-23T11:00:00+00:00" }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(KycSession.self, from: json)

        #expect(session.redirectURL == "https://kyc.banxa.com/kyc/abc")
        #expect(session.expiresAt == "2026-09-23T11:00:00+00:00")
    }

    @Test("parses an expiresAt with a +00:00 offset")
    func parsesOffset() throws {
        let session = KycSession(redirectURL: sessionURL, expiresAt: "2026-09-23T11:00:00+00:00")

        let date = try #require(session.expirationDate)

        #expect(date == Date(timeIntervalSince1970: 1_790_161_200))
    }

    @Test("parses an expiresAt with fractional seconds")
    func parsesFractionalSeconds() throws {
        let session = KycSession(redirectURL: sessionURL, expiresAt: "2026-09-23T11:00:00.250Z")

        let date = try #require(session.expirationDate)

        #expect(date == Date(timeIntervalSince1970: 1_790_161_200.25))
    }

    @Test("returns a nil expirationDate for an unknown format without failing the decode")
    func toleratesUnknownFormat() throws {
        let json = """
        { "redirectUrl": "https://kyc.banxa.com/kyc/abc", "expiresAt": "next tuesday" }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(KycSession.self, from: json)

        #expect(session.expiresAt == "next tuesday")
        #expect(session.expirationDate == nil)
    }
}

// MARK: - BanxaPaymentSDK.createKycSession

@Suite("BanxaPaymentSDK.createKycSession")
struct CreateKycSessionTests {

    @Test("returns the session from the API client")
    @MainActor
    func returnsSession() async throws {
        let stub = KycStubAPIClient()
        let expected = KycSession(redirectURL: sessionURL, expiresAt: "2026-09-23T11:00:00+00:00")
        stub.result = .success(expected)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeKycConfig())

        let session = try await sdk.createKycSession(request: CreateKycSessionRequest(externalCustomerID: "cust-1"))

        #expect(session == expected)
        #expect(stub.lastEndpoint is CreateKycSessionEndpoint)
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: KycStubAPIClient())

        do {
            _ = try await sdk.createKycSession(request: CreateKycSessionRequest(externalCustomerID: "cust-1"))
            Issue.record("Expected sdkNotConfigured to be thrown")
        } catch let error as APIError {
            guard case .sdkNotConfigured = error else {
                Issue.record("Expected sdkNotConfigured, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("throws missingCredentials when partnerID is blank")
    @MainActor
    func missingCredentials() async {
        let sdk = BanxaPaymentSDK(apiClient: KycStubAPIClient())
        sdk.configure(config: makeKycConfig(partnerID: " "))

        do {
            _ = try await sdk.createKycSession(request: CreateKycSessionRequest(externalCustomerID: "cust-1"))
            Issue.record("Expected missingCredentials to be thrown")
        } catch let error as APIError {
            guard case .missingCredentials(let fields) = error else {
                Issue.record("Expected missingCredentials, got \(error)")
                return
            }
            #expect(fields == ["partnerID"])
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("propagates a 403 from the API unchanged")
    @MainActor
    func propagatesForbidden() async {
        let stub = KycStubAPIClient()
        stub.result = .failure(APIError.serverError(403))

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeKycConfig())

        do {
            _ = try await sdk.createKycSession(request: CreateKycSessionRequest(externalCustomerID: "cust-1"))
            Issue.record("Expected serverError(403) to be thrown")
        } catch let error as APIError {
            guard case .serverError(let code) = error else {
                Issue.record("Expected serverError, got \(error)")
                return
            }
            #expect(code == 403)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }
}

// MARK: - HostedKycSessionMonitor

@Suite("HostedKycSessionMonitor messages")
struct HostedKycSessionMonitorMessageTests {

    @Test("completes on a kyc-complete message from the session origin in the main frame")
    func completesOnValidMessage() {
        var monitor = makeMonitor()

        let event = monitor.handleMessage(
            body: ["type": "banxa:kyc-complete", "status": "pending"],
            origin: sessionOrigin,
            isMainFrame: true
        )

        #expect(event == .complete(BanxaKycResult(status: "pending", channel: .message)))
    }

    @Test("reports a default status of complete when the message has none")
    func defaultsStatus() {
        var monitor = makeMonitor()

        let event = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)

        #expect(event == .complete(BanxaKycResult(status: "complete", channel: .message)))
    }

    @Test("rejects a message from another origin")
    func rejectsWrongOrigin() {
        var monitor = makeMonitor()

        let event = monitor.handleMessage(
            body: ["type": "banxa:kyc-complete"],
            origin: "https://evil.example.com",
            isMainFrame: true
        )

        #expect(event == .rejected(BanxaKycRejectedMessage(
            reason: .origin,
            type: "banxa:kyc-complete",
            origin: "https://evil.example.com"
        )))
        #expect(monitor.didComplete == false)
    }

    @Test("rejects a message from a sub-frame even when the origin matches")
    func rejectsSubFrame() {
        var monitor = makeMonitor()

        let event = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: false)

        #expect(event == .rejected(BanxaKycRejectedMessage(reason: .frame, type: "banxa:kyc-complete", origin: sessionOrigin)))
        #expect(monitor.didComplete == false)
    }

    @Test("accepts a message from a partner-allowed origin")
    func honoursAllowedOrigins() {
        var monitor = makeMonitor(allowedOrigins: [" https://verify.banxa.com/ignored/path "])

        let event = monitor.handleMessage(
            body: ["type": "banxa:kyc-complete"],
            origin: "https://verify.banxa.com",
            isMainFrame: true
        )

        #expect(event == .complete(BanxaKycResult(status: "complete", channel: .message)))
    }

    @Test("matches origins without regard to case or a default port")
    func normalisesOrigins() {
        var monitor = makeMonitor(session: makeSession(redirectURL: "HTTPS://KYC.Banxa-Sandbox.com:443/kyc/abc"))

        let event = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)

        #expect(event == .complete(BanxaKycResult(status: "complete", channel: .message)))
    }

    @Test("relays an error message with its code and message")
    func relaysError() {
        var monitor = makeMonitor()

        let event = monitor.handleMessage(
            body: ["type": "banxa:error", "code": 410, "message": "Link expired"],
            origin: sessionOrigin,
            isMainFrame: true
        )

        #expect(event == .error(code: "410", message: "Link expired"))
    }

    @Test("relays ready and loading with their default statuses")
    func relaysReadyAndLoading() {
        var monitor = makeMonitor()

        let ready = monitor.handleMessage(body: ["type": "banxa:ready"], origin: sessionOrigin, isMainFrame: true)
        let loading = monitor.handleMessage(body: ["type": "banxa:loading"], origin: sessionOrigin, isMainFrame: true)

        #expect(ready == .ready(status: "ready"))
        #expect(loading == .loading(status: "loading"))
    }

    @Test("ignores messages that are not banxa payloads")
    func ignoresForeignMessages() {
        var monitor = makeMonitor()

        #expect(monitor.handleMessage(body: ["type": "sumsub:step"], origin: sessionOrigin, isMainFrame: true) == nil)
        #expect(monitor.handleMessage(body: "banxa:kyc-complete", origin: sessionOrigin, isMainFrame: true) == nil)
        #expect(monitor.handleMessage(body: ["type": "banxa:unknown"], origin: sessionOrigin, isMainFrame: true) == nil)
        #expect(monitor.didComplete == false)
    }
}

@Suite("HostedKycSessionMonitor navigation")
struct HostedKycSessionMonitorNavigationTests {

    @Test("cancels and completes on an https return URL, ignoring the query")
    func completesOnHttpsReturnURL() throws {
        var monitor = makeMonitor(returnURL: "https://partner.example.com/kyc/done")

        let decision = monitor.handleNavigation(to: try #require(URL(string: "https://partner.example.com/kyc/done?status=ok")))

        #expect(decision == .cancelAndComplete(BanxaKycResult(status: "complete", channel: .returnURL)))
    }

    @Test("cancels and completes on a custom-scheme deep link")
    func completesOnDeepLink() throws {
        var monitor = makeMonitor(returnURL: "myapp://kyc-done")

        let decision = monitor.handleNavigation(to: try #require(URL(string: "myapp://kyc-done")))

        #expect(decision == .cancelAndComplete(BanxaKycResult(status: "complete", channel: .returnURL)))
    }

    @Test("allows navigation that does not match the return URL")
    func allowsOtherNavigation() throws {
        var monitor = makeMonitor(returnURL: "https://partner.example.com/kyc/done")

        #expect(monitor.handleNavigation(to: try #require(URL(string: sessionURL))) == .allow)
        #expect(monitor.handleNavigation(to: try #require(URL(string: "https://partner.example.com/kyc/other"))) == .allow)
        #expect(monitor.didComplete == false)
    }

    @Test("allows every navigation when no return URL is set")
    func allowsWithoutReturnURL() throws {
        var monitor = makeMonitor()

        #expect(monitor.handleNavigation(to: try #require(URL(string: "myapp://kyc-done"))) == .allow)
    }
}

@Suite("HostedKycSessionMonitor fire-once")
struct HostedKycSessionMonitorFireOnceTests {

    @Test("ignores a second completion message")
    func messageThenMessage() {
        var monitor = makeMonitor()

        _ = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)
        let second = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)

        #expect(second == nil)
    }

    @Test("still cancels the return URL after a completion message, without completing again")
    func messageThenReturnURL() throws {
        var monitor = makeMonitor(returnURL: "myapp://kyc-done")

        _ = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)
        let decision = monitor.handleNavigation(to: try #require(URL(string: "myapp://kyc-done")))

        #expect(decision == .cancel)
    }

    @Test("ignores a completion message after the return URL completed")
    func returnURLThenMessage() throws {
        var monitor = makeMonitor(returnURL: "myapp://kyc-done")

        _ = monitor.handleNavigation(to: try #require(URL(string: "myapp://kyc-done")))
        let event = monitor.handleMessage(body: ["type": "banxa:kyc-complete"], origin: sessionOrigin, isMainFrame: true)

        #expect(event == nil)
        #expect(monitor.didComplete)
    }
}

@Suite("HostedKycSessionMonitor session checks")
struct HostedKycSessionMonitorSessionTests {

    @Test("reports an expired session")
    func expired() {
        #expect(makeMonitor(session: makeSession(expiresIn: -1)).isExpired)
        #expect(makeMonitor(session: makeSession(expiresIn: 60)).isExpired == false)
    }

    @Test("treats an unparseable expiresAt as not expired")
    func unparseableIsNotExpired() {
        let monitor = makeMonitor(session: KycSession(redirectURL: sessionURL, expiresAt: "soon"))

        #expect(monitor.isExpired == false)
    }

    @Test("grants media capture only to accepted origins")
    func grantsMediaOnlyToAcceptedOrigins() {
        let monitor = makeMonitor(allowedOrigins: ["https://verify.banxa.com"])

        #expect(monitor.shouldGrantMediaCapture(origin: sessionOrigin))
        #expect(monitor.shouldGrantMediaCapture(origin: "https://verify.banxa.com"))
        #expect(monitor.shouldGrantMediaCapture(origin: "https://in.sumsub.com") == false)
    }

    @Test("builds an origin from WebKit's security-origin parts")
    func buildsOriginFromParts() {
        #expect(HostedKycSessionMonitor.origin(scheme: "https", host: "kyc.banxa.com", port: 0) == "https://kyc.banxa.com")
        #expect(HostedKycSessionMonitor.origin(scheme: "https", host: "kyc.banxa.com", port: 443) == "https://kyc.banxa.com")
        #expect(HostedKycSessionMonitor.origin(scheme: "http", host: "localhost", port: 5173) == "http://localhost:5173")
    }
}

@Suite("HostedKycSessionMonitor preflight")
struct HostedKycSessionMonitorPreflightTests {

    private let usageDescriptions: [String: Any] = [
        "NSCameraUsageDescription": "Verify your identity",
        "NSMicrophoneUsageDescription": "Record a liveness check",
    ]

    @Test("passes a valid session on a supported OS with both usage descriptions")
    func passes() {
        let error = makeMonitor().preflightError(isOSSupported: true, infoDictionary: usageDescriptions)

        #expect(error == nil)
    }

    @Test("fails a session whose redirect URL is not https")
    func invalidURL() {
        let monitor = makeMonitor(session: makeSession(redirectURL: "not a url"))

        #expect(monitor.preflightError(isOSSupported: true, infoDictionary: usageDescriptions) == .invalidSessionURL)
    }

    @Test("fails an expired session")
    func expiredSession() {
        let monitor = makeMonitor(session: makeSession(expiresIn: -1))

        #expect(monitor.preflightError(isOSSupported: true, infoDictionary: usageDescriptions) == .sessionExpired)
    }

    @Test("fails on an unsupported OS")
    func unsupportedOS() {
        #expect(makeMonitor().preflightError(isOSSupported: false, infoDictionary: usageDescriptions) == .unsupportedOSVersion)
    }

    @Test("names every missing or blank usage description")
    func missingUsageDescriptions() {
        let error = makeMonitor().preflightError(
            isOSSupported: true,
            infoDictionary: ["NSCameraUsageDescription": "  "]
        )

        #expect(error == .missingUsageDescription(["NSCameraUsageDescription", "NSMicrophoneUsageDescription"]))
    }
}

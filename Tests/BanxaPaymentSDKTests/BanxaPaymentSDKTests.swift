import Foundation
import Testing
@testable import BanxaPaymentSDK

// MARK: - Stub API client

private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
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

private func makeConfig(
    apiKey: String = "test-key",
    partnerID: String = "demo-partner",
    environment: BanxaEnvironment = .sandbox
) -> BanxaConfig {
    BanxaConfig(apiKey: apiKey, partnerID: partnerID, environment: environment)
}

// MARK: - CountriesEndpoint

@Suite("CountriesEndpoint")
struct CountriesEndpointTests {

    @Test("builds GET /countries against the partner base URL")
    func buildsRequest() throws {
        let endpoint = CountriesEndpoint(config: makeConfig())
        let request = try endpoint.buildRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.banxa-sandbox.com/demo-partner/v2/countries")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == nil)
    }

    @Test("uses production host when configured")
    func productionHost() throws {
        let endpoint = CountriesEndpoint(config: makeConfig(environment: .production))
        let request = try endpoint.buildRequest()

        #expect(request.url?.absoluteString == "https://api.banxa.com/demo-partner/v2/countries")
    }
}

// MARK: - Country decoding

@Suite("Country decoding")
struct CountryDecodingTests {

    @Test("decodes countries with nested states")
    func decodesWithStates() throws {
        let json = """
        [
          {
            "id": "US",
            "description": "United States of America",
            "states": [
              { "id": "AL", "description": "Alabama" },
              { "id": "NY", "description": "New York" }
            ]
          },
          {
            "id": "AU",
            "description": "Australia"
          }
        ]
        """.data(using: .utf8)!

        let countries = try JSONDecoder().decode([Country].self, from: json)

        #expect(countries.count == 2)
        #expect(countries[0].id == "US")
        #expect(countries[0].description == "United States of America")
        #expect(countries[0].states?.count == 2)
        #expect(countries[0].states?[0].id == "AL")
        #expect(countries[0].states?[1].description == "New York")
        #expect(countries[1].id == "AU")
        #expect(countries[1].states == nil)
    }
}

// MARK: - BanxaPaymentSDK.fetchCountries

@Suite("BanxaPaymentSDK.fetchCountries")
struct FetchCountriesTests {

    @Test("returns decoded countries from the API client")
    @MainActor
    func returnsCountries() async throws {
        let stub = StubAPIClient()
        let expected = [
            Country(id: "US", description: "United States of America", states: [
                CountryState(id: "AL", description: "Alabama")
            ])
        ]
        stub.result = .success(expected)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        let countries = try await sdk.fetchCountries()

        #expect(countries == expected)
        #expect(stub.lastEndpoint is CountriesEndpoint)
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())

        await #expect(throws: APIError.self) {
            _ = try await sdk.fetchCountries()
        }
    }

    @Test("throws missingCredentials when apiKey is blank")
    @MainActor
    func missingCredentials() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())
        sdk.configure(config: makeConfig(apiKey: "  "))

        do {
            _ = try await sdk.fetchCountries()
            Issue.record("Expected missingCredentials to be thrown")
        } catch let error as APIError {
            guard case .missingCredentials(let fields) = error else {
                Issue.record("Expected missingCredentials, got \(error)")
                return
            }
            #expect(fields == ["apiKey"])
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("propagates API client failures")
    @MainActor
    func propagatesFailure() async {
        let stub = StubAPIClient()
        stub.result = .failure(APIError.unauthorized)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        do {
            _ = try await sdk.fetchCountries()
            Issue.record("Expected unauthorized to be thrown")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                Issue.record("Expected unauthorized, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }
}

// MARK: - FiatsEndpoint

@Suite("FiatsEndpoint")
struct FiatsEndpointTests {

    @Test("builds GET /fiats/buy against the partner base URL")
    func buildsBuyRequest() throws {
        let endpoint = FiatsEndpoint(orderType: .buy, config: makeConfig())
        let request = try endpoint.buildRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.banxa-sandbox.com/demo-partner/v2/fiats/buy")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.httpBody == nil)
    }

    @Test("builds GET /fiats/sell path for sell order type")
    func buildsSellRequest() throws {
        let endpoint = FiatsEndpoint(orderType: .sell, config: makeConfig(environment: .production))
        let request = try endpoint.buildRequest()

        #expect(request.url?.absoluteString == "https://api.banxa.com/demo-partner/v2/fiats/sell")
    }
}

// MARK: - Fiat decoding

@Suite("Fiat decoding")
struct FiatDecodingTests {

    @Test("decodes fiats with nested payment methods")
    func decodesWithPaymentMethods() throws {
        let json = """
        [
          {
            "id": "USD",
            "description": "US Dollar",
            "symbol": "$",
            "supportedPaymentMethods": [
              {
                "id": "debit-credit-card",
                "name": "Credit Debit Card",
                "minimum": "10",
                "maximum": "50000"
              }
            ]
          },
          {
            "id": "EUR",
            "description": "Euro",
            "symbol": "€"
          }
        ]
        """.data(using: .utf8)!

        let fiats = try JSONDecoder().decode([Fiat].self, from: json)

        #expect(fiats.count == 2)
        #expect(fiats[0].id == "USD")
        #expect(fiats[0].symbol == "$")
        #expect(fiats[0].supportedPaymentMethods?.count == 1)
        #expect(fiats[0].supportedPaymentMethods?[0].id == "debit-credit-card")
        #expect(fiats[0].supportedPaymentMethods?[0].minimum == "10")
        #expect(fiats[0].supportedPaymentMethods?[0].maximum == "50000")
        #expect(fiats[1].id == "EUR")
        #expect(fiats[1].supportedPaymentMethods == nil)
    }
}

// MARK: - BanxaPaymentSDK.fetchFiats

@Suite("BanxaPaymentSDK.fetchFiats")
struct FetchFiatsTests {

    @Test("returns decoded fiats from the API client")
    @MainActor
    func returnsFiats() async throws {
        let stub = StubAPIClient()
        let expected = [
            Fiat(
                id: "USD",
                description: "US Dollar",
                symbol: "$",
                supportedPaymentMethods: [
                    FiatPaymentMethod(id: "debit-credit-card", name: "Credit Debit Card", minimum: "10", maximum: "50000")
                ]
            )
        ]
        stub.result = .success(expected)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        let fiats = try await sdk.fetchFiats(orderType: .buy)

        #expect(fiats == expected)
        let endpoint = try #require(stub.lastEndpoint as? FiatsEndpoint)
        #expect(endpoint.orderType == .buy)
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())

        await #expect(throws: APIError.self) {
            _ = try await sdk.fetchFiats(orderType: .buy)
        }
    }
}

// MARK: - CryptoEndpoint

@Suite("CryptoEndpoint")
struct CryptoEndpointTests {

    @Test("builds GET /crypto/buy against the partner base URL")
    func buildsBuyRequest() throws {
        let endpoint = CryptoEndpoint(orderType: .buy, config: makeConfig())
        let request = try endpoint.buildRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.banxa-sandbox.com/demo-partner/v2/crypto/buy")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.httpBody == nil)
    }

    @Test("builds GET /crypto/sell path for sell order type")
    func buildsSellRequest() throws {
        let endpoint = CryptoEndpoint(orderType: .sell, config: makeConfig(environment: .production))
        let request = try endpoint.buildRequest()

        #expect(request.url?.absoluteString == "https://api.banxa.com/demo-partner/v2/crypto/sell")
    }
}

// MARK: - Cryptocurrency decoding

@Suite("Cryptocurrency decoding")
struct CryptocurrencyDecodingTests {

    @Test("decodes cryptocurrencies with nested blockchains")
    func decodesWithBlockchains() throws {
        let json = """
        [
          {
            "id": "AAVE",
            "description": "Ethereum (ERC-20)",
            "blockchains": [
              {
                "id": "ETH",
                "description": "Ethereum (ERC-20)",
                "isDefaultBlockchain": true,
                "address": "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9",
                "network": "1",
                "minimum": "1",
                "unsupportedCountries": {
                  "US": ["NY"],
                  "CA": []
                }
              }
            ]
          },
          {
            "id": "BTC",
            "description": "Bitcoin"
          }
        ]
        """.data(using: .utf8)!

        let assets = try JSONDecoder().decode([Cryptocurrency].self, from: json)

        #expect(assets.count == 2)
        #expect(assets[0].id == "AAVE")
        #expect(assets[0].blockchains?.count == 1)
        #expect(assets[0].blockchains?[0].id == "ETH")
        #expect(assets[0].blockchains?[0].isDefaultBlockchain == true)
        #expect(assets[0].blockchains?[0].address == "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9")
        #expect(assets[0].blockchains?[0].unsupportedCountries?["US"] == ["NY"])
        #expect(assets[0].blockchains?[0].unsupportedCountries?["CA"] == [])
        #expect(assets[1].id == "BTC")
        #expect(assets[1].blockchains == nil)
    }
}

// MARK: - BanxaPaymentSDK.fetchCrypto

@Suite("BanxaPaymentSDK.fetchCrypto")
struct FetchCryptoTests {

    @Test("returns decoded cryptocurrencies from the API client")
    @MainActor
    func returnsCrypto() async throws {
        let stub = StubAPIClient()
        let expected = [
            Cryptocurrency(
                id: "ETH",
                description: "Ethereum",
                blockchains: [
                    CryptoBlockchain(
                        id: "ETH",
                        description: "Ethereum",
                        isDefaultBlockchain: true,
                        address: nil,
                        network: "1",
                        minimum: "0.01",
                        unsupportedCountries: nil
                    )
                ]
            )
        ]
        stub.result = .success(expected)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        let assets = try await sdk.fetchCrypto(orderType: .sell)

        #expect(assets == expected)
        let endpoint = try #require(stub.lastEndpoint as? CryptoEndpoint)
        #expect(endpoint.orderType == .sell)
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())

        await #expect(throws: APIError.self) {
            _ = try await sdk.fetchCrypto(orderType: .buy)
        }
    }
}

// MARK: - PaymentMethodsEndpoint

@Suite("PaymentMethodsEndpoint")
struct PaymentMethodsEndpointTests {

    @Test("builds GET /payment-methods/buy without fiat filter")
    func buildsWithoutFiat() throws {
        let endpoint = PaymentMethodsEndpoint(orderType: .buy, config: makeConfig())
        let request = try endpoint.buildRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.banxa-sandbox.com/demo-partner/v2/payment-methods/buy")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.httpBody == nil)
    }

    @Test("appends fiat query parameter when provided")
    func buildsWithFiat() throws {
        let endpoint = PaymentMethodsEndpoint(
            orderType: .sell,
            fiat: "USD",
            config: makeConfig(environment: .production)
        )
        let request = try endpoint.buildRequest()

        #expect(request.url?.absoluteString == "https://api.banxa.com/demo-partner/v2/payment-methods/sell?fiat=USD")
    }
}

// MARK: - PaymentMethod decoding

@Suite("PaymentMethod decoding")
struct PaymentMethodDecodingTests {

    @Test("decodes payment methods with supported fiats")
    func decodesWithSupportedFiats() throws {
        let json = """
        [
          {
            "id": "apple-pay",
            "name": "Apple Pay",
            "description": "Conveniently buy digital currency using your personal VISA or MasterCard.",
            "supportedFiats": ["CAD", "EUR", "USD"]
          },
          {
            "id": "debit-credit-card",
            "name": "Credit Debit Card"
          }
        ]
        """.data(using: .utf8)!

        let methods = try JSONDecoder().decode([PaymentMethod].self, from: json)

        #expect(methods.count == 2)
        #expect(methods[0].id == "apple-pay")
        #expect(methods[0].name == "Apple Pay")
        #expect(methods[0].supportedFiats == ["CAD", "EUR", "USD"])
        #expect(methods[1].id == "debit-credit-card")
        #expect(methods[1].supportedFiats == nil)
    }
}

// MARK: - BanxaPaymentSDK.fetchPaymentMethods

@Suite("BanxaPaymentSDK.fetchPaymentMethods")
struct FetchPaymentMethodsTests {

    @Test("returns decoded payment methods and forwards fiat filter")
    @MainActor
    func returnsPaymentMethods() async throws {
        let stub = StubAPIClient()
        let expected = [
            PaymentMethod(
                id: "apple-pay",
                name: "Apple Pay",
                description: "Pay with Apple Pay",
                supportedFiats: ["USD", "EUR"]
            )
        ]
        stub.result = .success(expected)

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        let methods = try await sdk.fetchPaymentMethods(orderType: .buy, fiat: "USD")

        #expect(methods == expected)
        let endpoint = try #require(stub.lastEndpoint as? PaymentMethodsEndpoint)
        #expect(endpoint.orderType == .buy)
        #expect(endpoint.fiat == "USD")
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())

        await #expect(throws: APIError.self) {
            _ = try await sdk.fetchPaymentMethods(orderType: .buy)
        }
    }
}

// MARK: - QuotesEndpoint

private func makeQuoteRequest(
    fiatAmount: String? = "200",
    cryptoAmount: String? = nil,
    discountCode: String? = nil
) -> QuoteRequest {
    QuoteRequest(
        paymentMethodID: "debit-credit-card",
        crypto: "ETH",
        blockchain: "ETH",
        fiat: "USD",
        fiatAmount: fiatAmount,
        cryptoAmount: cryptoAmount,
        discountCode: discountCode
    )
}

@Suite("QuotesEndpoint")
struct QuotesEndpointTests {

    @Test("builds GET /quotes/buy with required query parameters")
    func buildsRequest() throws {
        let endpoint = QuotesEndpoint(
            orderType: .buy,
            request: makeQuoteRequest(),
            config: makeConfig()
        )
        let request = try endpoint.buildRequest()
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keyed = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(request.httpMethod == "GET")
        #expect(url.path == "/demo-partner/v2/quotes/buy")
        #expect(keyed["paymentMethodId"] == "debit-credit-card")
        #expect(keyed["crypto"] == "ETH")
        #expect(keyed["blockchain"] == "ETH")
        #expect(keyed["fiat"] == "USD")
        #expect(keyed["fiatAmount"] == "200")
        #expect(keyed["cryptoAmount"] == nil)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
    }

    @Test("includes optional query parameters when set")
    func buildsWithOptionals() throws {
        let endpoint = QuotesEndpoint(
            orderType: .sell,
            request: QuoteRequest(
                paymentMethodID: "apple-pay",
                crypto: "BTC",
                blockchain: "BTC",
                fiat: "EUR",
                cryptoAmount: "0.01",
                externalCustomerID: "cust-1",
                ipAddress: "1.2.3.4",
                discountCode: "XMAS"
            ),
            config: makeConfig(environment: .production)
        )
        let request = try endpoint.buildRequest()
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keyed = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(url.absoluteString.hasPrefix("https://api.banxa.com/demo-partner/v2/quotes/sell?"))
        #expect(keyed["cryptoAmount"] == "0.01")
        #expect(keyed["externalCustomerId"] == "cust-1")
        #expect(keyed["ipAddress"] == "1.2.3.4")
        #expect(keyed["discountCode"] == "XMAS")
        #expect(keyed["fiatAmount"] == nil)
    }
}

// MARK: - Quote decoding

@Suite("Quote decoding")
struct QuoteDecodingTests {

    @Test("decodes a single quote object as a one-element list")
    func decodesSingleObject() throws {
        let json = """
        {
          "paymentMethodId": "debit-credit-card",
          "cryptoAmount": "0.03564700",
          "fiatAmount": "200.00",
          "processingFee": "0.92",
          "networkFee": "1.67"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(QuoteResponse.self, from: json)

        #expect(response.quotes.count == 1)
        #expect(response.quotes[0].paymentMethodID == "debit-credit-card")
        #expect(response.quotes[0].cryptoAmount == "0.03564700")
        #expect(response.quotes[0].fiatAmount == "200.00")
        #expect(response.quotes[0].processingFee == "0.92")
        #expect(response.quotes[0].networkFee == "1.67")
        #expect(response.quotes[0].discount == nil)
    }

    @Test("decodes an array with discount and Banxa's orginalNetworkFee typo")
    func decodesArrayWithDiscount() throws {
        let json = """
        [
          {
            "paymentMethodId": "debit-credit-card",
            "cryptoAmount": "0.03564700",
            "fiatAmount": "200.00",
            "processingFee": "0.92",
            "networkFee": "1.67",
            "discount": {
              "originalQuote": {
                "originalCryptoAmount": "0.235214",
                "orginalNetworkFee": "0.00",
                "originalProcessingFee": "0.00",
                "originalFiatAmount": "500.00"
              },
              "discountCode": "XMAS"
            }
          }
        ]
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(QuoteResponse.self, from: json)

        #expect(response.quotes.count == 1)
        #expect(response.quotes[0].discount?.discountCode == "XMAS")
        #expect(response.quotes[0].discount?.originalQuote?.originalNetworkFee == "0.00")
        #expect(response.quotes[0].discount?.originalQuote?.originalFiatAmount == "500.00")
    }
}

// MARK: - BanxaPaymentSDK.fetchQuotes

@Suite("BanxaPaymentSDK.fetchQuotes")
struct FetchQuotesTests {

    @Test("returns normalized quotes from the API client")
    @MainActor
    func returnsQuotes() async throws {
        let stub = StubAPIClient()
        let expected = [
            Quote(
                paymentMethodID: "debit-credit-card",
                cryptoAmount: "0.03564700",
                fiatAmount: "200.00",
                processingFee: "0.92",
                networkFee: "1.67",
                discount: nil
            )
        ]
        stub.result = .success(QuoteResponse(quotes: expected))

        let sdk = BanxaPaymentSDK(apiClient: stub)
        sdk.configure(config: makeConfig())

        let quotes = try await sdk.fetchQuotes(orderType: .buy, request: makeQuoteRequest())

        #expect(quotes == expected)
        let endpoint = try #require(stub.lastEndpoint as? QuotesEndpoint)
        #expect(endpoint.orderType == .buy)
    }

    @Test("throws sdkNotConfigured when configure was never called")
    @MainActor
    func notConfigured() async {
        let sdk = BanxaPaymentSDK(apiClient: StubAPIClient())

        await #expect(throws: APIError.self) {
            _ = try await sdk.fetchQuotes(orderType: .buy, request: makeQuoteRequest())
        }
    }
}

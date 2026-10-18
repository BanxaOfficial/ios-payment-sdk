# BanxaPaymentSDK

A headless iOS SDK that lets partners initiate Banxa fiat-to-crypto orders and complete the payment through the [Primer](https://github.com/primer-io/primer-sdk-ios) drop-in checkout. The SDK orchestrates the full flow — eligibility check, order creation, and Primer presentation — and forwards every relevant event back to the partner via a single delegate.

## Features

- Headless API: configure once, start a payment with a single call.
- Automatic eligibility + create-order pipeline against the Banxa API.
- Configuration helpers for supported countries, fiats, crypto, payment methods, and live quotes (`fetchCountries`, `fetchFiats`, `fetchCrypto`, `fetchPaymentMethods`, `fetchQuotes`).
- Built-in Primer drop-in presentation when a native token is available.
- Hosted-checkout fallback URL handed back to the partner when in-app payment is not possible.
- Hosted KYC: verify a customer through Banxa's hosted flow before any order (`createKycSession`, `startKyc`).
- Strongly-typed request/response models and `APIError` cases.
- Swift 6 / Swift concurrency, `@MainActor`-isolated public surface.

## Requirements

- iOS 13.1+
- Xcode 16+
- Swift 6.0+
- A Banxa partner account (`apiKey` + `partnerID`).

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/BanxaOfficial/ios-payment-sdk", from: "1.0.0")
]
```

And add `BanxaPaymentSDK` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "BanxaPaymentSDK", package: "ios-payment-sdk")
    ]
)
```

#### Through Xcode

1. **File → Add Package Dependencies…**
2. Enter the repository URL.
3. Select **BanxaPaymentSDK** and add it to your app target.

> The SDK transitively pulls in `PrimerSDK` (`>= 2.49.0`).

## Configuration

Configure the SDK once, ideally at app launch (for example in `AppDelegate` or your `App` entry point).

```swift
import BanxaPaymentSDK

let config = BanxaConfig(
    apiKey: "YOUR_BANXA_API_KEY",
    partnerID: "your-partner-slug",
    environment: .sandbox            // .sandbox | .preprod | .production
)

BanxaPaymentSDK.shared.configure(config: config)
BanxaPaymentSDK.shared.delegate = self
```

### Environments

| Environment   | Host                                  |
| ------------- | ------------------------------------- |
| `.sandbox`    | `https://api.banxa-sandbox.com`       |
| `.preprod`    | `https://api.banxa-preprod.com`       |
| `.production` | `https://api.banxa.com`               |

The effective API base URL is `<host>/<partnerID>/v2`.

## Configuration Endpoints

After `configure(config:)`, you can fetch Banxa-supported configuration data. These calls are `async throws` and require a configured SDK with non-blank credentials.

### Countries

`GET /{partnerID}/v2/countries` — supported countries (identical for buy and sell).

```swift
let countries = try await BanxaPaymentSDK.shared.fetchCountries()
// countries: [Country]
// Country.id / .description, optional Country.states: [CountryState]
```

| Type           | Fields                                      |
| -------------- | ------------------------------------------- |
| `Country`      | `id`, `description`, `states: [CountryState]?` |
| `CountryState` | `id`, `description`                         |

### Fiats

`GET /{partnerID}/v2/fiats/{orderType}` — supported fiat currencies for buy or sell.

```swift
let fiats = try await BanxaPaymentSDK.shared.fetchFiats(orderType: .buy)
// fiats: [Fiat]
// Fiat.id / .description / .symbol, optional .supportedPaymentMethods: [FiatPaymentMethod]
```

| Type                | Fields                                              |
| ------------------- | --------------------------------------------------- |
| `OrderType`         | `.buy`, `.sell`                                     |
| `Fiat`              | `id`, `description?`, `symbol?`, `supportedPaymentMethods: [FiatPaymentMethod]?` |
| `FiatPaymentMethod` | `id`, `name?`, `minimum?`, `maximum?`               |

### Crypto

`GET /{partnerID}/v2/crypto/{orderType}` — supported cryptocurrencies for buy or sell.

```swift
let assets = try await BanxaPaymentSDK.shared.fetchCrypto(orderType: .buy)
// assets: [Cryptocurrency]
// Cryptocurrency.id / .description, optional .blockchains: [CryptoBlockchain]
```

| Type              | Fields                                                                 |
| ----------------- | ---------------------------------------------------------------------- |
| `Cryptocurrency`  | `id`, `description?`, `blockchains: [CryptoBlockchain]?`               |
| `CryptoBlockchain`| `id`, `description?`, `isDefaultBlockchain?`, `address?`, `network?`, `minimum?`, `unsupportedCountries: [String: [String]]?` |

### Payment Methods

`GET /{partnerID}/v2/payment-methods/{orderType}` — supported payment methods for buy or sell. Optionally filter with `?fiat=`.

```swift
let methods = try await BanxaPaymentSDK.shared.fetchPaymentMethods(orderType: .buy)
let usdOnly = try await BanxaPaymentSDK.shared.fetchPaymentMethods(orderType: .buy, fiat: "USD")
// methods: [PaymentMethod]
// PaymentMethod.id / .name / .description, optional .supportedFiats: [String]
```

| Type            | Fields                                              |
| --------------- | --------------------------------------------------- |
| `PaymentMethod` | `id`, `name?`, `description?`, `supportedFiats: [String]?` |

### Quotes

`GET /{partnerID}/v2/quotes/{orderType}` — live pricing for a fiat/crypto/payment-method combination. Do not cache; call immediately before showing a price. Banxa may return a single object or an array (with discount codes); `fetchQuotes` always returns `[Quote]`.

```swift
let request = QuoteRequest(
    paymentMethodID: "debit-credit-card",
    crypto: "ETH",
    blockchain: "ETH",
    fiat: "USD",
    fiatAmount: "200"
)
let quotes = try await BanxaPaymentSDK.shared.fetchQuotes(orderType: .buy, request: request)
// quotes[0].cryptoAmount / .fiatAmount / .processingFee / .networkFee
```

| Type                   | Fields                                                                 |
| ---------------------- | ---------------------------------------------------------------------- |
| `QuoteRequest`         | `paymentMethodID`, `crypto`, `blockchain`, `fiat`, `fiatAmount?`, `cryptoAmount?`, `externalCustomerID?`, `ipAddress?`, `discountCode?` |
| `Quote`                | `paymentMethodID?`, `cryptoAmount?`, `fiatAmount?`, `processingFee?`, `networkFee?`, `discount: QuoteDiscount?` |
| `QuoteDiscount`        | `originalQuote: QuoteOriginalAmounts?`, `discountCode?`                |
| `QuoteOriginalAmounts` | `originalCryptoAmount?`, `originalNetworkFee?`, `originalProcessingFee?`, `originalFiatAmount?` |

> Provide either `fiatAmount` or `cryptoAmount` (or both — Banxa prefers crypto when both are set).

## Starting a Payment

Build a `CreateOrderRequest` and call `startPayment(request:controller:)`. Pass the view controller that should host any WebView fallback presentation.

```swift
let request = CreateOrderRequest(
    crypto: "ETH",
    fiat: "EUR",
    fiatAmount: "40",
    walletAddress: "0x0000000000000000000000000000000000000000",
    email: "user@example.com",
    redirectURL: "your-app-scheme://banxa-return",
    paymentMethodID: "debit-credit-card"
)

BanxaPaymentSDK.shared.startPayment(request: request, controller: self)
```

## Handling Callbacks

Conform to `BanxaPaymentSDKDelegate` to receive Banxa flow events and in-app checkout results. All callback types are Banxa-owned — partners never import or reference the underlying payment provider SDK. Every method has a default no-op implementation, so implement only what you need.

For checkout, the delegate has three methods — one for success, one for failure, one for dismissal. Hosted KYC has its own three (see [Hosted KYC](#hosted-kyc)), so a KYC event never reaches your checkout handlers. Each has a default no-op implementation, so implement only what you need.

```swift
import BanxaPaymentSDK

extension MyViewController: BanxaPaymentSDKDelegate {

    func banxaDidCompleteCheckout(_ result: BanxaCheckoutResult) {
        // Success — from either the native in-app flow or the internal WebView.
        // Native path populates paymentId / orderId / status.
        // WebView path populates rawQuery with the terminal success URL query string.
        print("Paid:", result.paymentId ?? result.rawQuery ?? "-")
    }

    func banxaDidFail(error: Error) {
        // Any failure: Banxa API / validation / network / decoding errors,
        // in-app checkout errors (card decline, 3DS), or WebView failure URL.
        // Banxa-side failures are `APIError`.
        print("Failed:", error.localizedDescription)
    }

    func banxaDidDismiss() {
        // User closed the checkout UI without completing.
    }
}
```

> All delegate callbacks are delivered on the main actor.

### Callback types

| Type                    | Purpose                                                                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `BanxaCheckoutResult`   | Success payload. `paymentId` / `orderId` / `status` for the native flow; `rawQuery` for the internal WebView flow.                   |
| `APIError`              | Failure reason for `banxaDidFail(error:)` when the SDK originates the error (see [Error Handling](#error-handling)).                 |

## Hosted KYC

If you don't run your own KYC, send the customer through Banxa's hosted verification **before** they place an order. It takes two steps: create a session, then present it.

### 1. Create a session

We recommend creating the session on **your backend** (`POST /{partner}/v2/kyc/sessions`), so your API key isn't shipped in the app. Send the two returned fields to the app and build the session there:

```swift
let session = KycSession(redirectURL: response.redirectUrl, expiresAt: response.expiresAt)
```

You can also create it from the app:

```swift
let session = try await BanxaPaymentSDK.shared.createKycSession(
    request: CreateKycSessionRequest(
        externalCustomerID: "customer-123",
        tier: .standard,                 // optional: .standard (default), .express, .enhanced
        country: "AU",                   // optional, two-letter code
        returnURL: "myapp://kyc-done"    // optional, an https URL or a deep link
    )
)
```

| Field                | Type      | Required | Notes                                                                                   |
| -------------------- | --------- | -------- | --------------------------------------------------------------------------------------- |
| `externalCustomerID` | String    | Yes      | Your customer id, up to 255 characters. Sent unchanged.                                 |
| `tier`               | KycTier?  | No       | Banxa defaults to `.standard`. `.express` is accepted, but Banxa may apply a stricter level. |
| `country`            | String?   | No       | Two-letter country code.                                                                |
| `returnURL`          | String?   | No       | Where the flow returns when it ends. An https URL or a deep link such as `myapp://kyc-done`. |

- Calling it again for the same `externalCustomerID` within **one hour** returns the same link, so retrying is safe.
- The link stops working at `expiresAt`. Create a new session after that.
- `APIError.serverError(403)`: hosted KYC isn't enabled for your partner account. Contact Banxa.
- `APIError.serverError(502)`: a temporary upstream error. Retry.

### 2. Present the flow

```swift
BanxaPaymentSDK.shared.startKyc(
    session: session,
    controller: self,
    returnURL: "myapp://kyc-done"   // the same returnURL the session was created with
)
```

`startKyc` doesn't need `configure(config:)`, so it works with a session your backend created. It presents the flow as a page sheet and reports through three delegate methods:

```swift
extension MyViewController: BanxaPaymentSDKDelegate {

    func banxaDidCompleteKyc(_ result: BanxaKycResult) {
        // The customer finished the flow. Fires once.
        // This is NOT the verification decision — that reaches your backend by webhook.
    }

    func banxaKycDidFail(error: BanxaKycError) {
        // The session couldn't be presented, or the flow reported an error.
    }

    func banxaDidDismissKyc() {
        // The customer closed the sheet before finishing.
    }
}
```

The SDK detects the end of the flow in two ways and reports whichever comes first:

- The flow posts a `banxa:kyc-complete` message (`result.channel == .message`).
- The flow navigates to your `returnURL` (`result.channel == .returnURL`). The SDK stops that navigation and closes the sheet, so a deep link never shows an error page and an https URL never opens inside the sheet.

Only messages from the page itself are accepted, and only from the session URL's origin. If the flow sends the customer across another Banxa host, pass it in `allowedOrigins`.

There is no status endpoint to poll. Use the **KYC webhook** on your backend for the verification result.

### Camera and microphone

The flow captures ID documents and a liveness video. Add both keys to your app's `Info.plist`, or `startKyc` fails with `.missingUsageDescription`:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera to verify your identity.</string>
<key>NSMicrophoneUsageDescription</key>
<string>We use the microphone for the identity liveness check.</string>
```

Camera access inside a web view needs **iOS 14.3 or later**. On older versions `startKyc` fails with `.unsupportedOSVersion` instead of opening a flow that can't capture documents.

### `BanxaKycError`

| Case                                | Meaning                                                                 |
| ----------------------------------- | ----------------------------------------------------------------------- |
| `.sessionExpired`                   | The session passed `expiresAt`. Create a new one.                       |
| `.invalidSessionURL`                | The session's `redirectURL` isn't a valid https URL.                    |
| `.unsupportedOSVersion`             | The device runs iOS older than 14.3.                                    |
| `.missingUsageDescription([String])`| These camera / microphone keys are missing from your `Info.plist`.     |
| `.flowError(code:message:)`         | The hosted flow reported an error.                                      |

### Embedding the view controller directly

To present it yourself, or to see the `ready`, `loading` and rejected-message events, use `HostedKycWebViewController`:

```swift
let vc = HostedKycWebViewController(
    session: session,
    returnURL: "myapp://kyc-done",
    onComplete: { result in /* ... */ },
    onError: { error in /* ... */ },
    onMessageRejected: { rejected in print("Refused", rejected.type, "from", rejected.origin) },
    onClose: { /* ... */ }
)
if let error = vc.preflightError() {
    // Handle it instead of presenting.
} else {
    present(vc.wrappedInNavigationController(), animated: true)
}
```

## Models

### `CreateOrderRequest`

| Field                | Type     | Required | Notes                                              |
| -------------------- | -------- | -------- | -------------------------------------------------- |
| `crypto`             | String   | Yes      | Crypto asset symbol (e.g. `"ETH"`).                |
| `fiat`               | String   | Yes      | Fiat currency code (e.g. `"EUR"`).                 |
| `fiatAmount`         | String   | Yes      | Fiat amount as a string.                           |
| `walletAddress`      | String   | Yes      | Destination wallet address.                        |
| `email`              | String   | Yes      | End-user's email address.                          |
| `redirectURL`        | String   | Yes      | URL Banxa redirects to after hosted checkout.      |
| `paymentMethodID`    | String?  | No       | Banxa payment method id (e.g. `"debit-credit-card"`, `"apple-pay"`). |
| `id`                 | String?  | No       | Partner-supplied order id.                         |
| `blockchain`         | String?  | No       | Explicit blockchain network.                       |
| `cryptoAmount`       | String?  | No       | Crypto amount when ordering by crypto value.       |
| `walletAddressTag`   | String?  | No       | Tag/memo for chains that require it.               |
| `subPartnerID`       | String?  | No       | Sub-partner identifier.                            |
| `metadata`           | String?  | No       | Opaque metadata string.                            |
| `externalCustomerID` | String?  | No       | Partner-side customer id.                          |
| `externalOrderID`    | String?  | No       | Partner-side order id.                             |
| `discountCode`       | String?  | No       | Promo / discount code.                             |


## Error Handling

Errors are surfaced through `banxaDidFail(error:)` as `APIError`:

| Case                            | Meaning                                                          |
| ------------------------------- | ---------------------------------------------------------------- |
| `.invalidURL`                   | The endpoint URL could not be built.                             |
| `.serverError(Int)`             | Non-2xx HTTP response.                                           |
| `.unauthorized`                 | 401 from Banxa — check `apiKey`.                                 |
| `.decodingFailed(String)`       | Response payload failed to decode.                               |
| `.networkUnavailable`           | No network connectivity.                                         |
| `.missingCredentials([String])` | `apiKey` and/or `partnerID` were blank in `BanxaConfig`.         |
| `.sdkNotConfigured`             | `startPayment` was called before `configure(config:)`.           |
| `.checkoutFailed(String?)`      | Internal WebView reached the failure URL. Payload is the raw query string. |
| `.unknown(String)`              | Any other unexpected error.                                      |

Each case provides a human-readable `errorDescription`.

## URL Scheme

If you use redirect-based payment methods (3DS, hosted checkout return, Apple Pay flows), register a URL scheme in your `Info.plist` and use the same scheme as the `redirectURL` on `CreateOrderRequest` when appropriate.

## Example

```swift
import SwiftUI
import BanxaPaymentSDK

@main
struct DemoApp: App {

    init() {
        let config = BanxaConfig(
            apiKey: ProcessInfo.processInfo.environment["BANXA_API_KEY"] ?? "",
            partnerID: "demo-partner",
            environment: .sandbox
        )
        BanxaPaymentSDK.shared.configure(config: config)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class CheckoutCoordinator: NSObject, BanxaPaymentSDKDelegate {

    override init() {
        super.init()
        BanxaPaymentSDK.shared.delegate = self
    }

    func buy(from controller: UIViewController) {
        let request = CreateOrderRequest(
            crypto: "ETH",
            fiat: "EUR",
            fiatAmount: "40",
            walletAddress: "0x...",
            email: "user@example.com",
            redirectURL: "demo://banxa-return",
            paymentMethodID: "debit-credit-card"
        )
        BanxaPaymentSDK.shared.startPayment(request: request, controller: controller)
    }

    func banxaDidCompleteCheckout(_ result: BanxaCheckoutResult) {
        print("Payment complete:", result.paymentId ?? result.rawQuery ?? "-")
    }

    func banxaDidFail(error: Error) {
        print("Payment failed:", error.localizedDescription)
    }

    func banxaDidDismiss() {
        print("User dismissed checkout")
    }
}
```

## Payment Methods & Supported Fiats

| Payment Method ID | Supported Fiats |
|-------------------|----------------|
| `payid-bank-transfer` | `AUD` |
| `pix` | `BRL` |
| `zar-bank-transfer` | `ZAR` |
| `pse` | `COP` |
| `khipu` | `CLP` |
| `debit-credit-card` | `AED`, `ARS`, `AUD`, `BRL`, `CAD`, `CHF`, `CZK`, `DKK`, `EUR`, `GBP`, `HKD`, `IDR`, `INR`, `JPY`, `KRW`, `MXN`, `MYR`, `NGN`, `NOK`, `NZD`, `PHP`, `PLN`, `QAR`, `RUB`, `SAR`, `SEK`, `SGD`, `THB`, `TRY`, `TWD`, `USD`, `VND`, `ZAR` |
| `apple-pay` | `AUD`, `EUR`, `GBP`, `USD` |
| `google-pay` | `AUD`, `EUR`, `USD` |
| `interac-bank-transfer` | `CAD` |
| `klarna-paynow` | `EUR` |
| `ideal-bank-transfer` | `AUD`, `EUR` |
| `sepa-bank-transfer` | `EUR` |
| `gbp-bank-transfer` | `GBP` |
| `spei` | `MXN` |

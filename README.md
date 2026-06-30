# BanxaPaymentSDK

A headless iOS SDK that lets partners initiate Banxa fiat-to-crypto orders and complete the payment through the [Primer](https://github.com/primer-io/primer-sdk-ios) drop-in checkout. The SDK orchestrates the full flow — eligibility check, order creation, and Primer presentation — and forwards every relevant event back to the partner via a single delegate.

## Features

- Headless API: configure once, start a payment with a single call.
- Automatic eligibility + create-order pipeline against the Banxa API.
- Built-in Primer drop-in presentation when a native token is available.
- Hosted-checkout fallback URL handed back to the partner when in-app payment is not possible.
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
    .package(url: "https://github.com/BanxaOfficial/ios-payment-sdk.git", from: "1.0.0")
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
import PrimerSDK

let primerSettings = PrimerSettings(
    paymentHandling: .auto,
)

let config = BanxaConfig(
    apiKey: "YOUR_BANXA_API_KEY",
    partnerID: "your-partner-slug",
    environment: .sandbox,           // .sandbox | .preprod | .production
    primerSettings: primerSettings   // optional
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

## Starting a Payment

Build a `CreateOrderRequest` and call `startPayment(request:)`:

```swift
let request = CreateOrderRequest(
    paymentMethodID: "debit-credit-card",
    crypto: "ETH",
    fiat: "EUR",
    fiatAmount: "40",
    walletAddress: "0x0000000000000000000000000000000000000000",
    email: "user@example.com",
    redirectURL: "your-app-scheme://banxa-return"
)

BanxaPaymentSDK.shared.startPayment(request: request)
```

## Handling Callbacks

Conform to `BanxaPaymentSDKDelegate` to receive both Banxa flow events and forwarded Primer drop-in callbacks. All methods have default no-op implementations — implement only what you need.

```swift
extension MyViewController: BanxaPaymentSDKDelegate {

    // MARK: Banxa flow

    func banxaDidReceiveCheckout(_ response: CreateOrderResponse) {
        // No native token — present `response.checkoutUrl` in a web view.
    }

    func banxaDidFail(error: Error) {
        // Validation, network, decoding or API error. Typically an `APIError`.
        print("Banxa error:", error.localizedDescription)
    }

    func banxaDidDismiss() {
        // User closed the Primer drop-in without completing checkout.
    }

    // MARK: Forwarded Primer callbacks

    func banxaDidCompleteCheckout(_ data: PrimerCheckoutData) {
        // Payment completed successfully.
    }

    func banxaClientSessionWillUpdate() { }
    func banxaClientSessionDidUpdate(_ clientSession: PrimerClientSession) { }

    func banxaWillCreatePayment(
        _ data: PrimerCheckoutPaymentMethodData,
        decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void
    ) {
        decisionHandler(.continuePaymentCreation())
    }

    func banxaDidFailWithError(
        _ error: Error,
        data: PrimerCheckoutData?,
        decisionHandler: @escaping (PrimerErrorDecision) -> Void
    ) {
        decisionHandler(.fail(withErrorMessage: error.localizedDescription))
    }

    func banxaDidTokenizePaymentMethod(
        _ tokenData: PrimerPaymentMethodTokenData,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) { }

    func banxaDidResumeWith(
        _ resumeToken: String,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) { }

    func banxaDidEnterResumePending(_ additionalInfo: PrimerCheckoutAdditionalInfo?) { }
}
```

> All delegate callbacks are delivered on the main actor.

## Models

### `CreateOrderRequest`

| Field                | Type     | Required | Notes                                              |
| -------------------- | -------- | -------- | -------------------------------------------------- |
| `paymentMethodID`    | String   | Yes      | Banxa payment method id (e.g. `"apple-pay"`).      |
| `crypto`             | String   | Yes      | Crypto asset symbol (e.g. `"ETH"`).                |
| `fiat`               | String   | Yes      | Fiat currency code (e.g. `"EUR"`).                 |
| `fiatAmount`         | String   | Yes      | Fiat amount as a string.                           |
| `walletAddress`      | String   | Yes      | Destination wallet address.                        |
| `email`              | String   | Yes      | End-user's email address.                          |
| `redirectURL`        | String   | Yes      | URL Banxa redirects to after hosted checkout.      |
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
| `.unknown(String)`              | Any other unexpected error.                                      |

Each case provides a human-readable `errorDescription`.

## URL Scheme

If you use redirect-based payment methods (3DS, hosted checkout return, Apple Pay flows), configure a URL scheme in your `Info.plist` and pass it to `PrimerSettings.paymentMethodOptions(urlScheme:)`. Make sure the same scheme is used as the `redirectURL` on `CreateOrderRequest` when appropriate.

## Example

```swift
import SwiftUI
import BanxaPaymentSDK
import PrimerSDK

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

    func buy() {
        let request = CreateOrderRequest(
            paymentMethodID: "debit-credit-card",
            crypto: "ETH",
            fiat: "EUR",
            fiatAmount: "40",
            walletAddress: "0x...",
            email: "user@example.com",
            redirectURL: "demo://banxa-return"
        )
        BanxaPaymentSDK.shared.startPayment(request: request)
    }

    func banxaDidCompleteCheckout(_ data: PrimerCheckoutData) {
        print("Payment complete:", data)
    }

    func banxaDidFail(error: Error) {
        print("Payment failed:", error.localizedDescription)
    }

    func banxaDidReceiveCheckout(_ response: CreateOrderResponse) {
        // Present `response.checkoutUrl` in a web view.
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

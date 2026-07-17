//
//  PrimerSDK.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//

import PrimerSDK

/// Bridges `PrimerDelegate` callbacks to the partner-facing
/// `BanxaPaymentSDKDelegate`. Primer types never cross this boundary — every
/// payload is translated into a Banxa-owned equivalent before the partner sees it.
extension BanxaPaymentSDK: @MainActor PrimerDelegate {

    /// Called by Primer when checkout completes successfully.
    public func primerDidCompleteCheckoutWithData(_ data: PrimerCheckoutData) {
        delegate?.banxaDidCompleteCheckout(Self.map(data))
        Primer.shared.dismiss()
    }

    /// Called by Primer when checkout fails. Notifies the partner and lets
    /// Primer fall back to its default failure UI.
    public func primerDidFailWithError(
        _ error: Error,
        data: PrimerCheckoutData?,
        decisionHandler: @escaping ((PrimerErrorDecision) -> Void)
    ) {
        delegate?.banxaDidFail(error: error)
        decisionHandler(.fail(withErrorMessage: nil))
        Primer.shared.dismiss()
    }

    /// Called by Primer when the user dismisses the drop-in UI.
    public func primerDidDismiss() {
        delegate?.banxaDidDismiss()
    }

    // MARK: - Type translation

    private static func map(_ data: PrimerCheckoutData) -> BanxaCheckoutResult {
        BanxaCheckoutResult(
            paymentId: data.payment?.id,
            orderId: data.payment?.orderId,
            status: data.payment?.status
        )
    }
}

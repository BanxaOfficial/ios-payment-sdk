//
//  PrimerSDK.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 05/06/26.
//

import PrimerSDK

/// Bridges `PrimerDelegate` callbacks to the partner-facing
/// `BanxaPaymentSDKDelegate`. Each method forwards its arguments through
/// without modification.
extension BanxaPaymentSDK: @MainActor PrimerDelegate {
    /// Called by Primer when checkout completes successfully.
    /// - Parameter data: Primer's checkout result payload.
    public func primerDidCompleteCheckoutWithData(_ data: PrimerCheckoutData) {
        delegate?.banxaDidCompleteCheckout(data)
    }
    
    /// Called by Primer just before its client session is refreshed.
    public func primerClientSessionWillUpdate() {
        delegate?.banxaClientSessionWillUpdate()
    }
    
    /// Called by Primer after the client session has been refreshed.
    /// - Parameter clientSession: The updated client session.
    public func primerClientSessionDidUpdate(_ clientSession: PrimerClientSession) {
        delegate?.banxaClientSessionDidUpdate(clientSession)
    }
    
    /// Called by Primer before creating a payment. Forwards the decision
    /// to the partner, defaulting to `.continuePaymentCreation()` when
    /// no delegate is set.
    /// - Parameters:
    ///   - data: Payment method data Primer is about to submit.
    ///   - decisionHandler: Tells Primer whether to continue or abort.
    public func primerWillCreatePaymentWithData(
        _ data: PrimerCheckoutPaymentMethodData,
        decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void
    ) {
        if let delegate {
            delegate.banxaWillCreatePayment(data, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.continuePaymentCreation())
        }
    }
    
    /// Called by Primer when checkout fails. Forwards to the partner, or
    /// fails silently with no custom message when no delegate is set.
    /// - Parameters:
    ///   - error: The error reported by Primer.
    ///   - data: Optional checkout data captured before the failure.
    ///   - decisionHandler: Carries the partner's error message back to Primer.
    public func primerDidFailWithError(
        _ error: Error,
        data: PrimerCheckoutData?,
        decisionHandler: @escaping ((PrimerErrorDecision) -> Void)
    ) {
        if let delegate {
            delegate.banxaDidFailWithError(error, data: data, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.fail(withErrorMessage: nil))
        }
    }
    
    /// Called by Primer when the user dismisses the drop-in UI.
    public func primerDidDismiss() {
        delegate?.banxaDidDismiss()
    }
    
    /// Called by Primer when a payment method has been tokenized.
    /// - Parameters:
    ///   - paymentMethodTokenData: Token information returned by Primer.
    ///   - decisionHandler: Tells Primer how to resume the flow.
    public func primerDidTokenizePaymentMethod(
        _ paymentMethodTokenData: PrimerPaymentMethodTokenData,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {
        delegate?.banxaDidTokenizePaymentMethod(paymentMethodTokenData, decisionHandler: decisionHandler)
    }
    
    /// Called by Primer when the payment must be resumed with a server token
    /// (e.g. after 3DS).
    /// - Parameters:
    ///   - resumeToken: Resume token from Primer's backend.
    ///   - decisionHandler: Tells Primer how to resume the flow.
    public func primerDidResumeWith(
        _ resumeToken: String,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {
        delegate?.banxaDidResumeWith(resumeToken, decisionHandler: decisionHandler)
    }
    
    /// Called by Primer when the payment enters a pending state.
    /// - Parameter additionalInfo: Optional extra payload describing the pending state.
    public func primerDidEnterResumePendingWithPaymentAdditionalInfo(
        _ additionalInfo: PrimerCheckoutAdditionalInfo?
    ) {
        delegate?.banxaDidEnterResumePending(additionalInfo)
    }
}

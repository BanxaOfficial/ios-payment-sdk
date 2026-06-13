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
    public func primerDidCompleteCheckoutWithData(_ data: PrimerCheckoutData) {}
    
    /// Called by Primer just before its client session is refreshed.
    public func primerClientSessionWillUpdate() {}
    
    /// Called by Primer after the client session has been refreshed.
    /// - Parameter clientSession: The updated client session.
    public func primerClientSessionDidUpdate(_ clientSession: PrimerClientSession) {}
    
    /// Called by Primer before creating a payment. Forwards the decision
    /// to the partner, defaulting to `.continuePaymentCreation()` when
    /// no delegate is set.
    /// - Parameters:
    ///   - data: Payment method data Primer is about to submit.
    ///   - decisionHandler: Tells Primer whether to continue or abort.
    public func primerWillCreatePaymentWithData(
        _ data: PrimerCheckoutPaymentMethodData,
        decisionHandler: @escaping (PrimerPaymentCreationDecision) -> Void
    ) {}
    
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
    ) {}
    
    /// Called by Primer when the user dismisses the drop-in UI.
    public func primerDidDismiss() {}
    
    /// Called by Primer when a payment method has been tokenized.
    /// - Parameters:
    ///   - paymentMethodTokenData: Token information returned by Primer.
    ///   - decisionHandler: Tells Primer how to resume the flow.
    public func primerDidTokenizePaymentMethod(
        _ paymentMethodTokenData: PrimerPaymentMethodTokenData,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {}
    
    /// Called by Primer when the payment must be resumed with a server token
    /// (e.g. after 3DS).
    /// - Parameters:
    ///   - resumeToken: Resume token from Primer's backend.
    ///   - decisionHandler: Tells Primer how to resume the flow.
    public func primerDidResumeWith(
        _ resumeToken: String,
        decisionHandler: @escaping (PrimerResumeDecision) -> Void
    ) {}
    
    /// Called by Primer when the payment enters a pending state.
    /// - Parameter additionalInfo: Optional extra payload describing the pending state.
    public func primerDidEnterResumePendingWithPaymentAdditionalInfo(
        _ additionalInfo: PrimerCheckoutAdditionalInfo?
    ) {}
}

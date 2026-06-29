//
//  CheckoutWebView.swift
//  BanxaPaymentSDK
//
//  Created by Jagadishwar Enagurthi on 29/06/26.
//

import UIKit
import WebKit

// MARK: - CheckoutWebViewController
/// A UIViewController that embeds a Banxa-hosted checkout page in a WKWebView.
/// Usage:
///
///     let vc = CheckoutWebViewController(
///         checkoutUrl: "https://checkout.banxa.com/...",
///         returnUrlOnSuccess: "banxa://success",
///         onSuccess: { url in print("Paid!", url) },
///         onClose: { print("Dismissed") }
///     )
///     present(vc.wrappedInNavigationController(), animated: true)
///
public final class CheckoutWebViewController: UIViewController {

    public let checkoutUrl: String
    public var onClose: (() -> Void)?
    public var onNavigationStateChange: ((URL) -> Void)?
    public var onSuccess: ((String) -> Void)?
    public var onFailure: ((String) -> Void)?
    public var onCancelled: ((String) -> Void)?
    public var returnUrlOnSuccess: String?
    public var returnUrlOnFailure: String?
    public var returnUrlOnCancelled: String?
    public var returnUrl: String

    // MARK: - Private views

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Init

    public init(
        checkoutUrl: String,
        returnUrl: String,
        onClose: (() -> Void)? = nil,
        onNavigationStateChange: ((URL) -> Void)? = nil,
        onSuccess: ((String) -> Void)? = nil,
        onFailure: ((String) -> Void)? = nil,
        onCancelled: ((String) -> Void)? = nil,
        returnUrlOnSuccess: String? = nil,
        returnUrlOnFailure: String? = nil,
        returnUrlOnCancelled: String? = nil
    ) {
        self.checkoutUrl = checkoutUrl
        self.onClose = onClose
        self.onNavigationStateChange = onNavigationStateChange
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onCancelled = onCancelled
        self.returnUrlOnSuccess = returnUrlOnSuccess
        self.returnUrlOnFailure = returnUrlOnFailure
        self.returnUrlOnCancelled = returnUrlOnCancelled
        self.returnUrl = returnUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupWebView()
        loadCheckoutUrl()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
//        title = "Checkout"
        view.backgroundColor = .systemBackground
        let closeButton = UIButton()
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .black
        closeButton.backgroundColor = .clear
        closeButton.addTarget( self, action:  #selector(closeTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: closeButton)
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func loadCheckoutUrl() {
        guard let url = URL(string: checkoutUrl) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismissAndClose()
    }

    // MARK: - URL checking

    /// Checks the URL against each return-URL pattern.
    /// Returns true and auto-dismisses when a pattern matches.
    @discardableResult
    private func checkUrl(_ urlString: String) -> Bool {
        if let pattern = returnUrlOnSuccess, urlString.contains(pattern) {
            onSuccess?(urlString)
            dismissAndClose()
            return true
        }
        if let pattern = returnUrlOnFailure, urlString.contains(pattern) {
            onFailure?(urlString)
            dismissAndClose()
            return true
        }
        if let pattern = returnUrlOnCancelled, urlString.contains(pattern) {
            onCancelled?(urlString)
            dismissAndClose()
            return true
        }
        return false
    }

    private func dismissAndClose() {
        dismiss(animated: true) { [weak self] in
            self?.onClose?()
        }
    }
}

// MARK: - WKNavigationDelegate

extension CheckoutWebViewController: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
          
            decisionHandler(.allow)
            return
        }

        if checkUrl(url.absoluteString) {
            decisionHandler(.cancel)
            return
        }

        onNavigationStateChange?(url)
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
        if let url = webView.url?.absoluteString, url.contains(self.returnUrl) {
            loadingIndicator.stopAnimating()
            self.onSuccess?(url)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }
}

// MARK: - Convenience helpers

public extension CheckoutWebViewController {

    /// Wraps self in a UINavigationController configured as a page sheet.
    /// Call present(wrappedInNavigationController(), animated: true) from any UIViewController.
    func wrappedInNavigationController() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        return nav
    }
}

public extension UIViewController {

    /// Present a CheckoutWebViewController as a page sheet from this view controller.
    ///
    /// Usage:
    ///
    ///     presentCheckoutWebView(
    ///         checkoutUrl: "https://checkout.banxa.com/...",
    ///         returnUrlOnSuccess: "banxa://success",
    ///         onSuccess: { url in print("Paid!", url) }
    ///     )
    ///
    func presentCheckoutWebView(
        checkoutUrl: String,
        returnUrl: String,
        onClose: (() -> Void)? = nil,
        onNavigationStateChange: ((URL) -> Void)? = nil,
        onSuccess: ((String) -> Void)? = nil,
        onFailure: ((String) -> Void)? = nil,
        onCancelled: ((String) -> Void)? = nil,
        returnUrlOnSuccess: String? = nil,
        returnUrlOnFailure: String? = nil,
        returnUrlOnCancelled: String? = nil
    ) {
        let vc = CheckoutWebViewController(
            checkoutUrl: checkoutUrl, returnUrl: returnUrl,
            onClose: onClose,
            onNavigationStateChange: onNavigationStateChange,
            onSuccess: onSuccess,
            onFailure: onFailure,
            onCancelled: onCancelled,
            returnUrlOnSuccess: returnUrlOnSuccess,
            returnUrlOnFailure: returnUrlOnFailure,
            returnUrlOnCancelled: returnUrlOnCancelled
        )
        present(vc.wrappedInNavigationController(), animated: true)
    }
}

//
//  HostedKycWebViewController.swift
//  BanxaPaymentSDK
//

import UIKit
import WebKit

// MARK: - HostedKycWebViewController
/// A UIViewController that runs Banxa's hosted KYC flow in a WKWebView.
/// Usage:
///
///     let vc = HostedKycWebViewController(
///         session: session,
///         returnURL: "myapp://kyc-done",
///         onComplete: { result in print("KYC submitted", result.status) }
///     )
///     present(vc.wrappedInNavigationController(), animated: true)
///
public final class HostedKycWebViewController: UIViewController {

    static let messageHandlerName = "banxaKyc"

    /// The hosted flow sends completion with `window.parent.postMessage(payload, merchantOrigin)`. In a
    /// top-level web view that targets the page itself, and WebKit drops it because the origins differ.
    /// Wrapping `postMessage` hands `banxa:*` payloads to the native handler before that check runs.
    static let bridgeScript = """
    (function () {
      var handlers = window.webkit && window.webkit.messageHandlers;
      var handler = handlers && handlers.\(messageHandlerName);
      if (!handler) { return; }
      var original = window.postMessage;
      window.postMessage = function (message) {
        try {
          if (message && typeof message === 'object' && typeof message.type === 'string'
              && message.type.indexOf('banxa:') === 0) {
            handler.postMessage(JSON.parse(JSON.stringify(message)));
          }
        } catch (e) {}
        return original.apply(this, arguments);
      };
    })();
    """

    public let session: KycSession
    public var onComplete: ((BanxaKycResult) -> Void)?
    public var onError: ((BanxaKycError) -> Void)?
    public var onReady: ((String) -> Void)?
    public var onLoading: ((String) -> Void)?
    public var onMessageRejected: ((BanxaKycRejectedMessage) -> Void)?
    /// Called when the customer closes the sheet before the flow completes.
    public var onClose: (() -> Void)?

    private var monitor: HostedKycSessionMonitor

    // MARK: - Private views

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // The content controller retains its handlers, so it gets a weak proxy instead of self.
        config.userContentController.add(WeakScriptMessageHandler(target: self), name: Self.messageHandlerName)

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

    /// - Parameters:
    ///   - session: The session to present.
    ///   - returnURL: The `returnUrl` the session was created with. Reaching it ends the flow.
    ///   - allowedOrigins: Extra origins trusted on top of the session URL's own.
    ///   - onComplete: Called once when the flow ends, by message or return URL.
    ///   - onError: Called when the session can't be presented, or the flow reports an error.
    ///   - onReady: Called when the flow reports it is ready.
    ///   - onLoading: Called when the flow reports it is loading.
    ///   - onMessageRejected: Called when a `banxa:*` message is refused. Useful when an integration never completes.
    ///   - onClose: Called when the customer closes the sheet before the flow completes.
    public init(
        session: KycSession,
        returnURL: String? = nil,
        allowedOrigins: [String] = [],
        onComplete: ((BanxaKycResult) -> Void)? = nil,
        onError: ((BanxaKycError) -> Void)? = nil,
        onReady: ((String) -> Void)? = nil,
        onLoading: ((String) -> Void)? = nil,
        onMessageRejected: ((BanxaKycRejectedMessage) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.session = session
        self.monitor = HostedKycSessionMonitor(session: session, returnURL: returnURL, allowedOrigins: allowedOrigins)
        self.onComplete = onComplete
        self.onError = onError
        self.onReady = onReady
        self.onLoading = onLoading
        self.onMessageRejected = onMessageRejected
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Returns why the session can't be presented on this device, or `nil` when it can.
    public func preflightError() -> BanxaKycError? {
        var isOSSupported = false
        if #available(iOS 14.3, *) {
            isOSSupported = true
        }
        return monitor.preflightError(
            isOSSupported: isOSSupported,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()

        if let error = preflightError() {
            onError?(error)
            return
        }

        setupWebView()
        loadSession()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        view.backgroundColor = .systemBackground
        let closeButton = UIButton()
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .clear
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: closeButton)
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
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

    private func loadSession() {
        guard let url = monitor.sessionURL else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onClose?()
        }
    }

    private func complete(with result: BanxaKycResult) {
        onComplete?(result)
        dismiss(animated: true)
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        let securityOrigin = message.frameInfo.securityOrigin
        let origin = HostedKycSessionMonitor.origin(
            scheme: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port
        )

        switch monitor.handleMessage(body: message.body, origin: origin, isMainFrame: message.frameInfo.isMainFrame) {
        case .complete(let result):
            complete(with: result)
        case .error(let code, let message):
            onError?(.flowError(code: code, message: message))
        case .ready(let status):
            onReady?(status)
        case .loading(let status):
            onLoading?(status)
        case .rejected(let rejected):
            onMessageRejected?(rejected)
        case nil:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension HostedKycWebViewController: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        switch monitor.handleNavigation(to: url) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .cancelAndComplete(let result):
            decisionHandler(.cancel)
            complete(with: result)
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }
}

// MARK: - WKUIDelegate

extension HostedKycWebViewController: WKUIDelegate {

    @available(iOS 15.0, *)
    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        let requester = HostedKycSessionMonitor.origin(scheme: origin.protocol, host: origin.host, port: origin.port)
        decisionHandler(monitor.shouldGrantMediaCapture(origin: requester) ? .grant : .deny)
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension HostedKycWebViewController: UIAdaptivePresentationControllerDelegate {

    /// A swipe-down closes the sheet without the close button, so it is reported here.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onClose?()
    }
}

// MARK: - Convenience helpers

public extension HostedKycWebViewController {

    /// Wraps self in a UINavigationController configured as a page sheet.
    /// Call present(wrappedInNavigationController(), animated: true) from any UIViewController.
    func wrappedInNavigationController() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        return nav
    }
}

// MARK: - WeakScriptMessageHandler

/// Forwards script messages to a controller without keeping it alive.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: HostedKycWebViewController?

    init(target: HostedKycWebViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(message)
    }
}

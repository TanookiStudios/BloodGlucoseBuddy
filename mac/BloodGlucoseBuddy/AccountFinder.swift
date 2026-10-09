import SwiftUI
import WebKit

/// Shows Dexcom's own sign-in page. When it lands on the profile page, reads the account ID from the address.
/// Only the address is read; what the user types on Dexcom's page never reaches this app.
struct DexcomAccountFinder: NSViewRepresentable {
    let startURL: URL
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // nothing from this sign-in is kept
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        let coordinator = context.coordinator
        // The profile page is a single-page app, so watch the address itself, not just page loads.
        coordinator.observation = web.observe(\.url, options: [.new]) { web, _ in
            DispatchQueue.main.async { coordinator.check(web.url) }
        }
        web.load(URLRequest(url: startURL))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFound: (String) -> Void
        var observation: NSKeyValueObservation?
        private var found = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func check(_ url: URL?) {
            guard !found, let id = DexcomParser.accountID(fromProfileURL: url) else { return }
            found = true
            onFound(id)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { check(webView.url) }
    }
}

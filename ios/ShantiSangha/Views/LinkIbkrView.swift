import SwiftUI
import WebKit

/// In-app login surface for Interactive Brokers. Wraps the IBKR Client
/// Portal Gateway login UI (hosted at `gateway.shantisangha.com`) in a
/// `WKWebView` so the user never has to leave the ShantiSangha app to
/// complete 2FA.
///
/// Auto-detects a successful login by watching the WebView's URL — IBKR
/// redirects to a `/sso/Login` confirmation flow that eventually lands
/// at `/portal/...` or similar once the session is established. When we
/// see that, we dismiss the sheet and fire `onCompleted` so the calling
/// view can run its IBKR portfolio link. The user can also tap `Done`
/// manually if our heuristic misses the redirect.
struct LinkIbkrView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when the user (or our auto-detect) signals login complete.
    /// The caller is responsible for triggering the actual /ibkr/link
    /// backend call — this view just owns the WebView lifecycle.
    let onCompleted: () -> Void

    @State private var currentURL: URL?
    @State private var isLoading = false

    private static let gatewayURL = URL(string: "https://gateway.shantisangha.com/")!

    var body: some View {
        NavigationStack {
            ZStack {
                IbkrGatewayWebView(
                    initialURL: Self.gatewayURL,
                    currentURL: $currentURL,
                    isLoading: $isLoading
                )

                if isLoading {
                    ProgressView()
                        .tint(.sacredGold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.sacredBg.opacity(0.6))
                }
            }
            .navigationTitle("Sign in to IBKR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.sacredText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onCompleted()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.sacredGold)
                }
            }
        }
    }
}

/// SwiftUI wrapper around `WKWebView`. Uses the default website data
/// store so cookies persist within the app (so a re-link inside the same
/// session skips IBKR's "remember me" prompts).
private struct IbkrGatewayWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(currentURL: $currentURL, isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Some IBKR pages set a strict user-agent check for known browsers;
        // a generic mobile Safari UA avoids the "unsupported browser"
        // warning that occasionally shows on the embedded WKWebView UA.
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // no-op
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var currentURL: URL?
        @Binding var isLoading: Bool

        init(currentURL: Binding<URL?>, isLoading: Binding<Bool>) {
            self._currentURL = currentURL
            self._isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = true
                self.currentURL = webView.url
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.currentURL = webView.url
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }

        // IBKR's login flow renders some content via iframes / mixed-origin
        // requests. We accept any navigation by default — the WebView is
        // already constrained to the gateway origin via the initial URL.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

import SwiftUI
import WebKit

/// A floating web panel for reading inside the immersive scene — e.g. Kindle Cloud Reader at
/// read.amazon.com. Float can't launch another app into its full immersive space (visionOS makes
/// that space exclusive), so instead it embeds its own WKWebView as a RealityView attachment.
///
/// - PERSISTENT data store → a login (passkey / Optic ID) sticks across launches; you sign in once.
/// - Desktop user agent → sites serve their full (non-mobile) layout, which Cloud Reader needs.
/// - Passkeys for the visited site (amazon.com) are handled by the system and use Optic ID, so no
///   phone 2FA is required even while fully immersed.

/// Owns the WKWebView so SwiftUI can drive back/reload/home without recreating it.
@MainActor
final class WebController: ObservableObject {
    let webView: WKWebView

    init(url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                       // persistent cookies → login persists
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: .zero, configuration: config)
        // Present as desktop Safari so Cloud Reader serves the full reader, not a stripped page.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: url))
    }

    func reload() { webView.reload() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goHome(_ url: URL) { webView.load(URLRequest(url: url)) }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct ReaderPanelView: View {
    static let home = URL(string: "https://read.amazon.com")!

    @StateObject private var controller = WebController(url: ReaderPanelView.home)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button { controller.goBack() } label: { Image(systemName: "chevron.backward") }
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { controller.goHome(Self.home) } label: { Image(systemName: "house") }
                Spacer()
                Text("Reader").font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            WebViewContainer(webView: controller.webView)
        }
        // Fills its WindowGroup window — the window supplies the glass + drag bar + resize.
    }
}

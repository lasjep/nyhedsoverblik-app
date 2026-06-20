import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif

final class WebViewModel: ObservableObject {
    @Published var url: URL?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle = ""
    @Published var estimatedProgress: Double = 0

    // Popup-vindue (window.open — login/oprettelses-flows).
    // Vises som et ark ovenpå browseren med egen luk-knap.
    @Published var popup: WebViewModel? = nil

    let webView: WKWebView

    /// Hoved-webview med egen konfiguration
    init() {
        let cfg = WKWebViewConfiguration()
        // Persistent data store — cookies overlever app-genstarter
        cfg.websiteDataStore = .default()
        #if os(macOS)
        // Web-inspektør til debugging (kun macOS)
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        webView = Self.styled(WKWebView(frame: .zero, configuration: cfg))
    }

    /// Popup-webview — SKAL bruge den konfiguration WebKit leverer,
    /// ellers deles session/cookies ikke med hovedvinduet
    init(popupWebView: WKWebView) {
        webView = Self.styled(popupWebView)
    }

    private static func styled(_ wv: WKWebView) -> WKWebView {
        #if os(macOS)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        #else
        // Swipe frem/tilbage med fingeren som i Safari
        wv.allowsBackForwardNavigationGestures = true
        #endif
        return wv
    }

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
    }

    func goBack()    { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload()    { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func closePopup() { popup = nil }

    func clear() {
        url = nil
        popup = nil
        webView.loadHTMLString("", baseURL: nil)
    }
}

// MARK: – Platform-wrapper (NSViewRepresentable på macOS, UIViewRepresentable på iOS)

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let model: WebViewModel
    private var obs: [NSKeyValueObservation] = []

    init(model: WebViewModel) {
        self.model = model
        super.init()
        let wv = model.webView
        obs = [
            wv.observe(\.isLoading)          { [weak self] wv, _ in self?.model.isLoading = wv.isLoading },
            wv.observe(\.canGoBack)           { [weak self] wv, _ in self?.model.canGoBack = wv.canGoBack },
            wv.observe(\.canGoForward)        { [weak self] wv, _ in self?.model.canGoForward = wv.canGoForward },
            wv.observe(\.title)               { [weak self] wv, _ in self?.model.pageTitle = wv.title ?? "" },
            wv.observe(\.estimatedProgress)   { [weak self] wv, _ in self?.model.estimatedProgress = wv.estimatedProgress },
        ]
    }

    // Popup-vinduer (window.open / target=_blank — login- og oprettelses-flows):
    // WebKit kræver at vi returnerer et NYT webview bygget med den leverede
    // konfiguration (deler session med hovedvinduet). Vises som ark ovenpå.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popupView = WKWebView(frame: .zero, configuration: configuration)
        model.popup = WebViewModel(popupWebView: popupView)
        return popupView
    }

    // Sitet kalder window.close() når login-flowet er færdigt → luk arket
    func webViewDidClose(_ webView: WKWebView) {
        if webView === model.popup?.webView {
            model.popup = nil
        }
    }

    // Webindholds-processen døde (hukommelsespres, GPU-fejl m.m.) —
    // uden denne står man med en permanent sort skærm. Genindlæs.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

#if os(macOS)
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView.navigationDelegate = context.coordinator
        model.webView.uiDelegate = context.coordinator
        return model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator(model: model) }
}
#else
struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView.navigationDelegate = context.coordinator
        model.webView.uiDelegate = context.coordinator
        return model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator(model: model) }
}
#endif

// MARK: – Browser-panel med toolbar

struct BrowserPanel: View {
    @ObservedObject var model: WebViewModel
    @EnvironmentObject var store: FeedStore

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 6) {
                // Luk-knap
                if model.url != nil {
                    #if os(iOS)
                    Button {
                        store.closeBrowser()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Nyheder")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    #else
                    Button {
                        store.closeBrowser()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .help("Luk artikel (Esc)")
                    #endif
                }

                Button { model.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                #if os(iOS)
                .opacity(0)  // skjult på iOS — brug browser swipe-gesture i stedet
                .frame(width: 0)
                #endif

                Button { model.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                #if os(iOS)
                .opacity(0)
                .frame(width: 0)
                #endif

                Button {
                    if model.isLoading { model.stopLoading() } else { model.reload() }
                } label: {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                }

                // URL-bar (read-only med kilde-tekst)
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(model.url?.scheme == "https" ? 1 : 0)
                    Text(model.url.map { displayHost($0) } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.platformTextBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.platformSeparator, lineWidth: 1))

                Button {
                    guard let url = model.url else { return }
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .URL)
                    #else
                    UIPasteboard.general.url = url
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Kopiér link")
                .disabled(model.url == nil)

                Button {
                    guard let url = model.url else { return }
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    UIApplication.shared.open(url)
                    #endif
                } label: {
                    Image(systemName: "safari")
                }
                .help("Åbn i Safari")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.platformWindowBackground)

            // Progress-bar
            if model.isLoading {
                GeometryReader { geo in
                    Color.accentColor
                        .frame(width: geo.size.width * model.estimatedProgress)
                        .animation(.linear(duration: 0.2), value: model.estimatedProgress)
                }
                .frame(height: 2)
            } else {
                Divider()
            }

            // Web-indhold
            if store.selectedArticle != nil {
                WebViewRepresentable(model: model)
            } else {
                emptyState
            }
        }
        .onKeyPress(.escape) {
            if store.selectedArticle != nil {
                store.closeBrowser()
                return .handled
            }
            return .ignored
        }
        // Popup-vindue (login/oprettelse) som ark ovenpå browseren
        .sheet(isPresented: Binding(
            get: { model.popup != nil },
            set: { if !$0 { model.closePopup() } }
        )) {
            if let popup = model.popup {
                PopupBrowserView(model: popup) {
                    model.closePopup()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Vælg en artikel")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Klik på en overskrift for at læse den her")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformWindowBackground)
    }

    private func displayHost(_ url: URL) -> String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}

// MARK: – Popup-vindue (login-flows m.m.) med egen toolbar

struct PopupBrowserView: View {
    @ObservedObject var model: WebViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Luk vindue")

                Text(model.pageTitle.isEmpty
                     ? (model.webView.url?.host?.replacingOccurrences(of: "www.", with: "") ?? "Login")
                     : model.pageTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.platformWindowBackground)

            Divider()

            WebViewRepresentable(model: model)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}

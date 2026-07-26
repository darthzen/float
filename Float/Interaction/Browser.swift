import SwiftUI
import WebKit

/// A tabbed web browser embedded in a Float window.
///
/// Float can't launch Safari into its own full immersive space (visionOS makes that space
/// exclusive), so the web has to come to us: this is a real WKWebView browser living in a
/// floating window you can put wherever you're lying.
///
/// - PERSISTENT data store, shared by every tab → a login (passkey / Optic ID) sticks across
///   tabs AND across launches; you sign in to Amazon or Apple once.
/// - Desktop user agent → sites serve their full layout. Kindle Cloud Reader in particular
///   serves a stripped page to anything it thinks is mobile.
/// - Passkeys for the visited site are handled by the system and use Optic ID, so no phone
///   2FA is required even while fully immersed.

// MARK: - Session persistence

/// One visited page. `lastVisit` is what the history list sorts on; repeat visits to the same
/// URL update the existing row rather than stacking duplicates, which is what makes a history
/// list usable rather than a scroll of the same page forty times.
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { url }
    var url: String
    var title: String
    var lastVisit: Date
    var visits: Int
}

/// What survives a quit: the open tabs and which one was in front.
private struct BrowserSession: Codable {
    var tabURLs: [String]
    var selectedIndex: Int
    var history: [HistoryEntry]
}

// MARK: - A tab

/// One tab: a WKWebView plus the observable chrome state the UI binds to.
///
/// Each tab keeps its own web view for the whole life of the window. Recreating a web view to
/// show a different page would throw away that page's scroll position, form state and JS
/// context, which is exactly what "tabs" are supposed to preserve.
@MainActor
@Observable
final class BrowserTab: NSObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    var title: String = "New Tab"
    var urlString: String = ""
    var isLoading = false
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false

    /// Called on every completed navigation so the model can record history. Set by the model
    /// rather than making the tab know about storage.
    var onNavigated: ((URL, String) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(url: URL?, dataStore: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore                     // shared → one login for all tabs
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.allowsInlineMediaPlayback = true
        // Streaming sites (and Cloud Reader's page-turn audio cues) should not demand a tap
        // that a floating window makes awkward to deliver.
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = BrowserModel.desktopUserAgent
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        observe()
        if let url { load(url) }
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    /// Mirror WKWebView's KVO properties into observable state.
    ///
    /// These fire on the main thread — WebKit guarantees it — but the closures are nonisolated
    /// as far as Swift 6 is concerned, hence `assumeIsolated` rather than a `Task` hop. A hop
    /// would make the progress bar lag its own navigation by a runloop turn.
    private func observe() {
        // Written out one by one rather than through a generic helper: a generic over
        // `KeyPath<WKWebView, V>` needs the key path to be Sendable to cross into the
        // observation closure, and key path literals are not.
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated {
                    if let t = view.title, !t.isEmpty { self.title = t }
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated { self.urlString = view.url?.absoluteString ?? "" }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated { self.isLoading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated { self.progress = view.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated { self.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { view, _ in
                MainActor.assumeIsolated { self.canGoForward = view.canGoForward }
            },
        ]
    }
}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        onNavigated?(url, webView.title?.isEmpty == false ? webView.title! : url.host() ?? "Page")
    }

    /// Target="_blank" links have no frame to load into and would otherwise silently do
    /// nothing — the classic "this link is broken" bug in an embedded web view. Load them in
    /// the tab that asked instead of dropping them.
    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.targetFrame == nil, let url = action.request.url {
            webView.load(URLRequest(url: url))
            return .cancel
        }
        return .allow
    }
}

// MARK: - The browser

@MainActor
@Observable
final class BrowserModel {
    /// Present as desktop Safari. Cloud Reader serves a stripped page to anything it reads as
    /// mobile, and visionOS's own UA is not on anyone's tested list.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// First-run page only. After that the browser reopens whatever was last open — which for
    /// Rick means it comes back to the Kindle without ever being told to.
    static let defaultHome = URL(string: "https://read.amazon.com")!

    /// Fixed jumping-off points. Deliberately short: this is a shortcut row, not a bookmark
    /// manager, and anything else is a search away.
    static let shortcuts: [(name: String, icon: String, url: String)] = [
        ("Kindle",    "book",              "https://read.amazon.com"),
        ("Apple TV",  "play.tv",           "https://tv.apple.com"),
        ("YouTube",   "play.rectangle",    "https://www.youtube.com"),
        ("Netflix",   "film",              "https://www.netflix.com"),
    ]

    private static let maxHistory = 2000

    var tabs: [BrowserTab] = []
    var selectedID: UUID?
    var history: [HistoryEntry] = []

    /// One store for every tab, and the `.default()` one so it is written to disk rather than
    /// living and dying with the process.
    private let dataStore = WKWebsiteDataStore.default()

    var selected: BrowserTab? { tabs.first { $0.id == selectedID } }

    init() {
        restore()
        if tabs.isEmpty { newTab(url: Self.defaultHome) }
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL?) -> BrowserTab {
        let tab = BrowserTab(url: url, dataStore: dataStore)
        tab.onNavigated = { [weak self] url, title in
            self?.record(url: url, title: title)
        }
        tabs.append(tab)
        selectedID = tab.id
        saveSession()
        return tab
    }

    func close(_ tab: BrowserTab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.stop()
        tabs.remove(at: idx)
        if selectedID == tab.id {
            // Select the neighbour rather than always falling to the first tab — closing the
            // third of five should leave you on the fourth, not thrown back to the start.
            selectedID = tabs[safe: idx]?.id ?? tabs.last?.id
        }
        if tabs.isEmpty { newTab(url: Self.defaultHome) }
        saveSession()
    }

    /// Open a URL in the current tab, or in a new one if there is somehow none.
    func open(_ url: URL) {
        if let selected { selected.load(url) } else { newTab(url: url) }
    }

    // MARK: Address bar

    /// Interpret what was typed: a URL if it plausibly is one, otherwise a web search.
    ///
    /// "Plausibly a URL" means it has a scheme, or it has a dot and no spaces. That second
    /// test is what stops `swift concurrency` becoming `http://swift concurrency` while still
    /// letting `read.amazon.com` work without anyone typing `https://`.
    func submit(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        if let url = URL(string: raw), url.scheme != nil, url.host != nil {
            open(url); return
        }
        if !raw.contains(" "), raw.contains("."),
           let url = URL(string: "https://" + raw) {
            open(url); return
        }
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: raw)]
        if let url = comps.url { open(url) }
    }

    // MARK: History

    private func record(url: URL, title: String) {
        // about:blank and the like are navigations but not places you went.
        guard url.scheme == "http" || url.scheme == "https" else { return }
        let key = url.absoluteString
        if let i = history.firstIndex(where: { $0.url == key }) {
            history[i].lastVisit = .now
            history[i].visits += 1
            history[i].title = title
        } else {
            history.append(HistoryEntry(url: key, title: title, lastVisit: .now, visits: 1))
        }
        history.sort { $0.lastVisit > $1.lastVisit }
        if history.count > Self.maxHistory { history.removeLast(history.count - Self.maxHistory) }
        saveSession()
    }

    func clearHistory() {
        history.removeAll()
        saveSession()
    }

    // MARK: Persistence

    private static var sessionURL: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Float", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("browser.json")
    }

    /// Debounced so a page that fires several navigations (redirect chains, SPAs pushing
    /// state) doesn't rewrite the whole history file once per hop.
    private var saveTask: Task<Void, Never>?

    private func saveSession() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let session = BrowserSession(
                tabURLs: self.tabs.map(\.urlString).filter { !$0.isEmpty },
                selectedIndex: self.tabs.firstIndex { $0.id == self.selectedID } ?? 0,
                history: self.history)
            guard let data = try? JSONEncoder().encode(session) else { return }
            try? data.write(to: Self.sessionURL, options: .atomic)
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.sessionURL),
              let session = try? JSONDecoder().decode(BrowserSession.self, from: data)
        else { return }
        history = session.history
        for str in session.tabURLs {
            newTab(url: URL(string: str))
        }
        if tabs.indices.contains(session.selectedIndex) {
            selectedID = tabs[session.selectedIndex].id
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Views

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    @State private var model = BrowserModel()
    @State private var addressText = ""
    @State private var showHistory = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            toolbar
            Divider()
            content
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet(model: model) { showHistory = false }
        }
        // Handoff. There is no public API for Safari's iCloud Tabs — that list is private to
        // Safari — but this is the supported way to get "the page I was just reading" from a
        // Mac or iPhone onto the headset: with Safari frontmost on the other device, Float
        // appears in the Dock, and opening it lands here.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { model.newTab(url: url) }
        }
        .onChange(of: model.selected?.urlString ?? "") { _, new in
            if !addressFocused { addressText = new }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.tabs) { tab in
                    let isSelected = tab.id == model.selectedID
                    HStack(spacing: 6) {
                        if tab.isLoading {
                            ProgressView().controlSize(.mini)
                        }
                        Text(tab.title)
                            .lineLimit(1)
                            .font(.callout)
                        Button {
                            model.close(tab)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                    }
                    .frame(maxWidth: 190)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelected ? AnyShapeStyle(.regularMaterial)
                                           : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        model.selectedID = tab.id
                        addressText = tab.urlString
                    }
                }
                Button {
                    model.newTab(url: nil)
                    addressText = ""
                    addressFocused = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { model.selected?.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!(model.selected?.canGoBack ?? false))
            Button { model.selected?.goForward() } label: { Image(systemName: "chevron.forward") }
                .disabled(!(model.selected?.canGoForward ?? false))
            Button {
                if model.selected?.isLoading == true { model.selected?.stop() }
                else { model.selected?.reload() }
            } label: {
                Image(systemName: model.selected?.isLoading == true ? "xmark" : "arrow.clockwise")
            }

            TextField("Search or enter address", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($addressFocused)
                .onSubmit {
                    model.submit(addressText)
                    addressFocused = false
                }

            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }

            Menu {
                ForEach(BrowserModel.shortcuts, id: \.name) { s in
                    Button {
                        if let url = URL(string: s.url) { model.open(url) }
                    } label: {
                        Label(s.name, systemImage: s.icon)
                    }
                }
            } label: {
                Image(systemName: "star")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            if let tab = model.selected {
                // `id:` forces a fresh container per tab. Without it SwiftUI reuses the
                // representable and shows the previous tab's web view after a switch.
                WebViewContainer(webView: tab.webView)
                    .id(tab.id)
                if tab.isLoading {
                    ProgressView(value: tab.progress)
                        .progressViewStyle(.linear)
                }
            }
        }
    }
}

private struct HistorySheet: View {
    let model: BrowserModel
    var dismiss: () -> Void
    @State private var query = ""

    private var results: [HistoryEntry] {
        guard !query.isEmpty else { return model.history }
        return model.history.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.url.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock")
                }
                ForEach(results) { entry in
                    Button {
                        if let url = URL(string: entry.url) { model.open(url) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title).lineLimit(1)
                            Text(entry.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) { model.clearHistory() }
                        .disabled(model.history.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }
}

import SwiftUI
import Combine
import UserNotifications

enum ViewMode: String, CaseIterable {
    case grid    = "grid"
    case list    = "list"
    case compact = "compact"
    case themes  = "themes"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system      = "system"
    case light       = "light"
    case dark        = "dark"
    case blackOrange = "blackOrange"
    case blackBlue   = "blackBlue"
    case blackGreen  = "blackGreen"
    case slatePurple = "slatePurple"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:      return "Systemstandard"
        case .light:       return "Lys"
        case .dark:        return "Mørk"
        case .blackOrange: return "Sort & Orange"
        case .blackBlue:   return "Sort & Blå"
        case .blackGreen:  return "Sort & Grøn"
        case .slatePurple: return "Skifer & Lilla"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:                      return nil
        case .light:                       return .light
        case .dark, .blackOrange,
             .blackBlue, .blackGreen,
             .slatePurple:                 return .dark
        }
    }

    var accentColor: Color {
        switch self {
        case .system, .light, .dark:       return .accentColor
        case .blackOrange:                 return Color(red: 1.0, green: 0.45, blue: 0.0)
        case .blackBlue:                   return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .blackGreen:                  return Color(red: 0.15, green: 0.85, blue: 0.45)
        case .slatePurple:                 return Color(red: 0.7, green: 0.4, blue: 1.0)
        }
    }

    // Baggrundsfarve for de mørke custom temaer
    var backgroundColor: Color? {
        switch self {
        case .blackOrange, .blackBlue, .blackGreen: return Color(red: 0.06, green: 0.06, blue: 0.06)
        case .slatePurple:                          return Color(red: 0.1, green: 0.09, blue: 0.13)
        default:                                    return nil
        }
    }
}

@MainActor
final class FeedStore: ObservableObject {
    // Afledte, cachede outputs — genberegnes kun når input ændres (rebuild())
    @Published private(set) var articlesBySource: [String: [Article]] = [:]  // filtreret + seen-markeret
    @Published private(set) var visibleArticles: [Article] = []              // flad liste til liste/kompakt/panel
    @Published private(set) var feedItems: [FeedItem] = []                   // med clusters, til grid
    @Published private(set) var sourceErrors: [String: String] = [:]         // kilde-id → fejlbesked

    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var selectedSourceID: String = "__all__"   // "__all__" = alle

    // Filtre
    @Published var filterSport = true
    @Published var filterClickbait = true
    @Published var hideSeen = false
    @Published var searchText = ""
    @Published var disabledSourceIDs: Set<String> = []
    @Published var blockedKeywords: [String] = []

    // Visningsindstillinger
    @Published var viewMode: ViewMode = .grid
    @Published var showThumbnails = true
    @Published var aiRewrite = false
    @Published var gridMinWidth: Double = 190
    @Published var listFontSize: Double = 14
    @Published var appTheme: AppTheme = .system
    @Published var serifHeadlines = true   // New York (serif) ↔ SF Pro (sans)

    var headlineFontDesign: Font.Design { serifHeadlines ? .serif : .default }

    // Browser
    @Published var selectedArticle: Article? = nil
    let webViewModel = WebViewModel()

    // Refresh
    @Published var refreshIntervalMinutes: Int = 15
    @Published var nextRefreshAt: Date?

    // AI
    @Published var apiKey: String = ""
    @Published var rewrittenTitles: [String: String] = [:]   // original → rewritten
    @Published var isRewriting = false
    // Titler AI'en har flagget som sport — supplerer ordliste-filteret i isSport(),
    // der ikke kender atletnavne ("Pogacar vinder igen" har hverken sport-ord eller -URL)
    private var aiSportTitles: Set<String> = []

    // Breaking news
    @Published var breakingNewsEnabled: Bool = false
    private var notifiedArticleIDs: Set<String> = []
    private var notifiedOrder: [String] = []

    @Published var customSources: [FeedSource] = []

    // Rå (ufiltrerede) artikler per kilde — filtre anvendes i rebuild()
    private var rawBySource: [String: [Article]] = [:]
    // Conditional GET-cache: kilde-id → (ETag, Last-Modified)
    private var httpCache: [String: (etag: String?, lastModified: String?)] = [:]

    private var seenIDs: Set<String> = []
    private var seenOrder: [String] = []
    private let seenFileURL: URL
    private let rewrittenFileURL: URL
    private let aiSportFileURL: URL
    private let notifiedFileURL: URL
    private let customSourcesFileURL: URL

    private var bag = Set<AnyCancellable>()

    var sources: [FeedSource] { defaultFeeds + customSources }

    var activeSources: [FeedSource] {
        sources.filter { !disabledSourceIDs.contains($0.id) }
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nyhedsoverblik")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if os(macOS)
        // Migrér fra gammel ~/.config/nyhedsoverblik/ til ~/Library/Application Support/nyhedsoverblik/
        let oldDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nyhedsoverblik")
        if FileManager.default.fileExists(atPath: oldDir.path) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: oldDir.path)) ?? []
            for name in files {
                let src = oldDir.appendingPathComponent(name)
                let dst = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }
        #endif
        seenFileURL = dir.appendingPathComponent("seen.json")
        rewrittenFileURL = dir.appendingPathComponent("rewritten.json")
        aiSportFileURL = dir.appendingPathComponent("aisport.json")
        notifiedFileURL = dir.appendingPathComponent("notified.json")
        customSourcesFileURL = dir.appendingPathComponent("custom_sources.json")
        loadSeen()
        loadNotified()
        loadRewritten()
        loadAISport()
        loadPrefs()
        loadCustomSources()
        setupPipelines()
        Task { await refresh() }
        Task { await autoRefreshLoop() }
        startWidgetCommandWatcher()
    }

    // MARK: – Reaktive pipelines (rebuild + auto-save)

    /// Én central pipeline i stedet for savePrefs()-kald spredt ud i UI-koden.
    /// Alle indstillinger gemmes automatisk (debounced), og filterændringer
    /// genberegner visningen uden netværkskald.
    private func setupPipelines() {
        // Genberegn visning når filtre/valg ændres — intet netværk involveret
        let rebuildTriggers: [AnyPublisher<Void, Never>] = [
            $filterSport.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $filterClickbait.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $hideSeen.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $blockedKeywords.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $disabledSourceIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $selectedSourceID.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(rebuildTriggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild() }
            .store(in: &bag)

        // Søgning: let debounce så vi ikke genberegner per tastetryk
        $searchText.dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)

        // Auto-gem alle præferencer — debounced så hurtige klik kun giver én skrivning
        let saveTriggers: [AnyPublisher<Void, Never>] = [
            $filterSport.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $filterClickbait.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $hideSeen.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $blockedKeywords.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $disabledSourceIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $showThumbnails.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $aiRewrite.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $gridMinWidth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $listFontSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $serifHeadlines.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $viewMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $appTheme.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $refreshIntervalMinutes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $breakingNewsEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(saveTriggers)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.savePrefs() }
            .store(in: &bag)

        // API-nøgle → Keychain (aldrig på disk i klartekst)
        $apiKey.dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { key in
                if key.isEmpty { Keychain.delete(account: "anthropic-api-key") }
                else { Keychain.save(key, account: "anthropic-api-key") }
            }
            .store(in: &bag)

        // Interval ændret → flyt næste refresh med det samme (ikke efter gammel ventetid)
        $refreshIntervalMinutes.dropFirst()
            .sink { [weak self] minutes in
                guard let self else { return }
                let base = self.lastUpdated ?? Date()
                self.nextRefreshAt = base.addingTimeInterval(Double(minutes) * 60)
            }
            .store(in: &bag)
    }

    // MARK: – Rebuild (rå → filtreret → synlig → clusters)

    /// Genberegner alle afledte lister. Kaldes ved datahentning og filterændringer
    /// — IKKE ved hver render, som tidligere (clustering er O(n²)).
    private func rebuild() {
        // 1) Filtrér per kilde + markér seen
        var dict: [String: [Article]] = [:]
        for src in sources {
            guard let raw = rawBySource[src.id] else { continue }
            dict[src.id] = raw.compactMap { a in
                if filterSport && (isSport(title: a.title, url: a.id, tags: a.tags)
                                   || aiSportTitles.contains(a.title)) { return nil }
                if filterClickbait && clickbaitScore(title: a.title) >= 5 { return nil }
                if src.filterCommercial && isCommercial(title: a.title) { return nil }
                var copy = a
                copy.seen = seenIDs.contains(a.id)
                return copy
            }
        }
        articlesBySource = dict

        // 2) Synlig flad liste (valgt kilde, søgning, blokerede ord, skjul læste)
        let base: [Article]
        if selectedSourceID == "__all__" {
            base = activeSources
                .flatMap { dict[$0.id] ?? [] }
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        } else {
            base = dict[selectedSourceID] ?? []
        }
        let q = searchText.lowercased()
        let blocked = blockedKeywords.map { $0.lowercased() }
        let visible = base.filter { a in
            if hideSeen && a.seen { return false }
            let lower = a.title.lowercased()
            if !q.isEmpty && !lower.contains(q) { return false }
            if blocked.contains(where: { lower.contains($0) }) { return false }
            return true
        }
        visibleArticles = visible

        // 3) Clusters (kun relevant for grid, men billigt nok at holde ajour)
        feedItems = Self.clusterArticles(visible)
    }

    /// Opdater kun seen-flag uden at genberegne clustering — bruges når en artikel
    /// åbnes og "skjul læste" er slået fra (ingen ændring i hvilke artikler der vises).
    private func applySeenFlagsInPlace() {
        for key in articlesBySource.keys {
            articlesBySource[key] = articlesBySource[key]?.map { a in
                var copy = a; copy.seen = seenIDs.contains(a.id); return copy
            }
        }
        visibleArticles = visibleArticles.map { a in
            var copy = a; copy.seen = seenIDs.contains(a.id); return copy
        }
        feedItems = feedItems.map { item in
            switch item {
            case .single(var a):
                a.seen = seenIDs.contains(a.id)
                return .single(a)
            case .cluster(let c):
                let arts = c.articles.map { a -> Article in
                    var copy = a; copy.seen = seenIDs.contains(a.id); return copy
                }
                return .cluster(StoryCluster(id: c.id, articles: arts))
            }
        }
    }

    // MARK: – Story clustering (ren funktion, testbar)

    nonisolated static let clusterStopwords: Set<String> = [
        "og", "i", "er", "at", "en", "et", "til", "af", "på", "for", "med",
        "den", "det", "de", "som", "the", "a", "an", "in", "is", "of", "to",
        "for", "that", "with", "on", "at", "by", "are", "be",
    ]

    nonisolated static func titleWords(_ title: String) -> Set<String> {
        Set(title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !clusterStopwords.contains($0) })
    }

    nonisolated static func titleSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0 }
        let intersection = Double(a.intersection(b).count)
        let union = Double(a.union(b).count)
        return intersection / union
    }

    nonisolated static func clusterArticles(_ articles: [Article]) -> [FeedItem] {
        guard articles.count > 1 else { return articles.map { .single($0) } }
        let wordSets = articles.map { titleWords($0.title) }
        var assigned = [Bool](repeating: false, count: articles.count)
        var items: [FeedItem] = []

        for i in 0..<articles.count where !assigned[i] {
            assigned[i] = true
            var group = [i]
            for j in (i + 1)..<articles.count where !assigned[j] {
                if titleSimilarity(wordSets[i], wordSets[j]) >= 0.42 {
                    group.append(j)
                    assigned[j] = true
                }
            }
            if group.count == 1 {
                items.append(.single(articles[i]))
            } else {
                let arts = group.map { articles[$0] }
                items.append(.cluster(StoryCluster(
                    id: arts.map(\.id).joined(separator: "|"),
                    articles: arts
                )))
            }
        }
        return items
    }

    // MARK: – Custom sources

    func addCustomSource(_ source: FeedSource) {
        customSources.append(source)
        saveCustomSources()
        Task { await refreshSource(source) }
    }

    func removeCustomSource(id: String) {
        customSources.removeAll { $0.id == id }
        rawBySource.removeValue(forKey: id)
        httpCache.removeValue(forKey: id)
        disabledSourceIDs.remove(id)
        saveCustomSources()
        rebuild()
    }

    private func loadCustomSources() {
        guard let data = try? Data(contentsOf: customSourcesFileURL),
              let arr = try? JSONDecoder().decode([CustomFeedSource].self, from: data)
        else { return }
        customSources = arr.map {
            FeedSource(id: $0.id, name: $0.name, url: $0.url,
                       colorHex: $0.colorHex, feedType: $0.feedType, isCustom: true)
        }
    }

    private func saveCustomSources() {
        let arr = customSources.map {
            CustomFeedSource(id: $0.id, name: $0.name, url: $0.url,
                             colorHex: $0.colorHex, feedType: $0.feedType)
        }
        guard let data = try? JSONEncoder().encode(arr) else { return }
        try? data.write(to: customSourcesFileURL, options: .atomic)
    }

    // Hent én kilde (bruges efter tilføjelse)
    func refreshSource(_ source: FeedSource) async {
        let outcome = await Self.fetchSource(source: source, etag: nil, lastModified: nil)
        apply(outcome: outcome, for: source.id)
        rebuild()
    }

    // Fælles dispatch: scrape, RSS eller kombi (RSS + forside-scrape merged)
    nonisolated static func fetchSource(source: FeedSource,
                                        etag: String?,
                                        lastModified: String?) async -> FetchOutcome {
        if source.feedType == .scrape {
            let arts = await HTMLScraper.scrape(source: source)
            return FetchOutcome(articles: arts,
                                errorText: arts.isEmpty ? "Ingen artikler fundet" : nil)
        }
        guard let pageURL = source.scrapePageURL else {
            return await fetchAllURLs(source: source, etag: etag, lastModified: lastModified)
        }
        // Kombi: RSS og forside-scrape parallelt, dedup på artikel-id.
        // Conditional GET slås fra — et 304 på RSS-delen ville ellers skjule
        // at forsiden har flyttet rundt på artiklerne.
        let scrapeSource = FeedSource(id: source.id, name: source.name, url: pageURL,
                                      colorHex: source.colorHex, feedType: .scrape)
        async let rssTask = fetchAllURLs(source: source, etag: nil, lastModified: nil)
        async let scrapeTask = HTMLScraper.scrape(source: scrapeSource)
        let (rss, scraped) = await (rssTask, scrapeTask)
        var seen = Set<String>()
        let merged = (rss.articles + scraped)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        return FetchOutcome(articles: merged,
                            errorText: merged.isEmpty ? (rss.errorText ?? "Ingen artikler fundet") : nil)
    }

    // MARK: – Refresh

    func unseenCount(for sourceID: String? = nil) -> Int {
        if let id = sourceID {
            return (articlesBySource[id] ?? []).filter { !$0.seen }.count
        }
        return activeSources.flatMap { articlesBySource[$0.id] ?? [] }.filter { !$0.seen }.count
    }

    private func apply(outcome: FetchOutcome, for id: String) {
        if outcome.notModified {
            sourceErrors[id] = nil          // uændret — behold eksisterende artikler
        } else if let err = outcome.errorText {
            sourceErrors[id] = err          // fejl — behold gamle artikler frem for at vise tomt
        } else {
            rawBySource[id] = outcome.articles
            httpCache[id] = (outcome.etag, outcome.lastModified)
            sourceErrors[id] = nil
        }
    }

    func refresh() async {
        isLoading = true
        let cacheSnapshot = httpCache
        await withTaskGroup(of: (String, FetchOutcome).self) { group in
            for source in activeSources {
                let cached = cacheSnapshot[source.id]
                group.addTask {
                    (source.id, await Self.fetchSource(source: source,
                                                       etag: cached?.etag,
                                                       lastModified: cached?.lastModified))
                }
            }
            for await (id, outcome) in group {
                apply(outcome: outcome, for: id)
            }
        }
        isLoading = false
        lastUpdated = Date()
        rebuild()
        if aiRewrite && !apiKey.isEmpty { Task { await rewriteNewTitles() } }
        if breakingNewsEnabled && !apiKey.isEmpty { Task { await checkBreakingNews() } }
        nextRefreshAt = Date().addingTimeInterval(Double(refreshIntervalMinutes) * 60)
        saveWidgetData()
    }

    // MARK: – Actions

    func openArticle(_ article: Article) {
        selectedArticle = article
        webViewModel.load(article.url)
        markSeen(article)
    }

    func markSeen(_ article: Article) {
        guard !seenIDs.contains(article.id) else { return }
        seenIDs.insert(article.id)
        seenOrder.append(article.id)
        saveSeen()
        // Skjules læste, ændrer listen sig → fuld rebuild. Ellers kun flag-opdatering.
        if hideSeen { rebuild() } else { applySeenFlagsInPlace() }
    }

    func markAllSeen() {
        let ids = Set(visibleArticles.map(\.id))
        for id in ids where !seenIDs.contains(id) {
            seenIDs.insert(id)
            seenOrder.append(id)
        }
        saveSeen()
        if hideSeen { rebuild() } else { applySeenFlagsInPlace() }
        // Luk browseren hvis den aktive artikel netop er markeret
        if let current = selectedArticle, ids.contains(current.id) {
            closeBrowser()
        }
    }

    func closeBrowser() {
        selectedArticle = nil
        webViewModel.clear()
    }

    /// Live læst-status — bruges af filmstrimlen der holder sin egen kø
    /// (artikler må ikke forsvinde fra strimlen mens man bladrer, selv med "Skjul læste")
    func isSeen(_ id: String) -> Bool {
        seenIDs.contains(id)
    }

    func toggleSource(_ id: String) {
        if disabledSourceIDs.contains(id) {
            disabledSourceIDs.remove(id)
        } else {
            disabledSourceIDs.insert(id)
            if selectedSourceID == id { selectedSourceID = "__all__" }
        }
    }

    // MARK: – AI omskrivning

    func rewriteNewTitles() async {
        guard !isRewriting else { return }   // undgå dobbeltkørsel ved refresh midt i omskrivning
        let allTitles = activeSources
            .flatMap { articlesBySource[$0.id] ?? [] }
            .map(\.title)
        let uncached = allTitles.filter { rewrittenTitles[$0] == nil }
        guard !uncached.isEmpty else { return }
        isRewriting = true
        let batches = stride(from: 0, to: uncached.count, by: 20).map {
            Array(uncached[$0..<min($0 + 20, uncached.count)])
        }
        for batch in batches {
            if let results = await HeadlineRewriter.rewrite(batch, apiKey: apiKey) {
                var flaggedSport = false
                for (orig, res) in results {
                    rewrittenTitles[orig] = res.rewritten
                    if res.isSport {
                        aiSportTitles.insert(orig)
                        flaggedSport = true
                    }
                }
                // Nyflagget sport skal ud af visningen med det samme
                if flaggedSport && filterSport { rebuild() }
            }
        }
        isRewriting = false
        saveRewritten()
        saveAISport()
    }

    func displayTitle(for article: Article) -> String {
        guard aiRewrite, let r = rewrittenTitles[article.title], !r.isEmpty else { return article.title }
        return r
    }

    // MARK: – Statistik

    struct SourceStat {
        let source: FeedSource
        let total: Int
        let unseen: Int
        let rewritten: Int
    }

    var stats: [SourceStat] {
        sources.map { src in
            let arts = articlesBySource[src.id] ?? []
            return SourceStat(
                source: src,
                total: arts.count,
                unseen: arts.filter { !$0.seen }.count,
                rewritten: arts.filter { rewrittenTitles[$0.title] != nil }.count
            )
        }
    }

    // MARK: – Persistence

    private func loadSeen() {
        guard let data = try? Data(contentsOf: seenFileURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        seenOrder = arr
        seenIDs = Set(arr)
    }
    private func saveSeen() {
        // Beskær til de seneste 5.000 — ældgamle ID'er er ude af alle feeds for længst
        let pruned = Array(seenOrder.suffix(5000))
        seenOrder = pruned
        seenIDs = Set(pruned)
        guard let data = try? JSONEncoder().encode(pruned) else { return }
        try? data.write(to: seenFileURL, options: .atomic)
    }

    private func loadNotified() {
        guard let data = try? Data(contentsOf: notifiedFileURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        notifiedOrder = arr
        notifiedArticleIDs = Set(arr)
    }
    private func saveNotified() {
        let pruned = Array(notifiedOrder.suffix(2000))
        notifiedOrder = pruned
        notifiedArticleIDs = Set(pruned)
        guard let data = try? JSONEncoder().encode(pruned) else { return }
        try? data.write(to: notifiedFileURL, options: .atomic)
    }

    private func loadRewritten() {
        guard let data = try? Data(contentsOf: rewrittenFileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        rewrittenTitles = dict
    }
    private func saveRewritten() {
        guard let data = try? JSONEncoder().encode(rewrittenTitles) else { return }
        try? data.write(to: rewrittenFileURL, options: .atomic)
    }

    private func loadAISport() {
        guard let data = try? Data(contentsOf: aiSportFileURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        aiSportTitles = Set(arr)
    }
    private func saveAISport() {
        guard let data = try? JSONEncoder().encode(Array(aiSportTitles)) else { return }
        try? data.write(to: aiSportFileURL, options: .atomic)
    }

    private struct Prefs: Codable {
        var filterSport: Bool
        var filterClickbait: Bool
        var disabledSourceIDs: [String]
        var showThumbnails: Bool
        var gridMinWidth: Double
        var apiKey: String
        var viewMode: String?
        var refreshIntervalMinutes: Int?
        var breakingNewsEnabled: Bool?
        var blockedKeywords: [String]?
        var appTheme: String?
        var aiRewrite: Bool?
        var hideSeen: Bool?
        var listFontSize: Double?
        var serifHeadlines: Bool?
    }

    private var prefsURL: URL {
        seenFileURL.deletingLastPathComponent().appendingPathComponent("prefs.json")
    }

    private func loadPrefs() {
        // API-nøgle bor i Keychain; prefs.json-feltet er kun migrationssti
        let keychainKey = Keychain.load(account: "anthropic-api-key")

        guard let data = try? Data(contentsOf: prefsURL),
              let p = try? JSONDecoder().decode(Prefs.self, from: data) else {
            apiKey = keychainKey ?? ""
            return
        }
        filterSport = p.filterSport
        filterClickbait = p.filterClickbait
        disabledSourceIDs = Set(p.disabledSourceIDs)
        showThumbnails = p.showThumbnails
        gridMinWidth = p.gridMinWidth
        viewMode = ViewMode(rawValue: p.viewMode ?? "") ?? .grid
        refreshIntervalMinutes = p.refreshIntervalMinutes ?? 15
        breakingNewsEnabled = p.breakingNewsEnabled ?? false
        blockedKeywords = p.blockedKeywords ?? []
        appTheme = AppTheme(rawValue: p.appTheme ?? "") ?? .system
        aiRewrite = p.aiRewrite ?? false
        hideSeen = p.hideSeen ?? false
        listFontSize = p.listFontSize ?? 14
        serifHeadlines = p.serifHeadlines ?? true

        if let keychainKey {
            apiKey = keychainKey
        } else if !p.apiKey.isEmpty {
            // Migrér gammel klartekst-nøgle til Keychain
            apiKey = p.apiKey
            Keychain.save(p.apiKey, account: "anthropic-api-key")
        }
        // Skrub klartekst-nøglen fra disk uanset hvilken kilde der vandt
        if !p.apiKey.isEmpty { savePrefs() }
        // Skriv altid prefs tilbage så nye felter (tilføjet efter første gem) altid er med
        else { savePrefs() }
    }

    func savePrefs() {
        let p = Prefs(filterSport: filterSport, filterClickbait: filterClickbait,
                      disabledSourceIDs: Array(disabledSourceIDs),
                      showThumbnails: showThumbnails, gridMinWidth: gridMinWidth,
                      apiKey: "",   // nøglen bor i Keychain
                      viewMode: viewMode.rawValue,
                      refreshIntervalMinutes: refreshIntervalMinutes,
                      breakingNewsEnabled: breakingNewsEnabled,
                      blockedKeywords: blockedKeywords,
                      appTheme: appTheme.rawValue,
                      aiRewrite: aiRewrite,
                      hideSeen: hideSeen,
                      listFontSize: listFontSize,
                      serifHeadlines: serifHeadlines)
        guard let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: prefsURL, options: .atomic)
    }

    // MARK: – Widget data

    private struct WidgetArticle: Codable {
        let id: String
        let title: String
        let sourceName: String
        let colorHex: String
        let publishedAt: Date?
    }

    private struct WidgetData: Codable {
        let articles: [WidgetArticle]
        let backgroundColorHex: String?
        let accentColorHex: String
        let listFontSize: Double
    }

    private func saveWidgetData() {
        let top = activeSources
            .flatMap { src in
                (articlesBySource[src.id] ?? []).map { (src, $0) }
            }
            .sorted { ($0.1.publishedAt ?? .distantPast) > ($1.1.publishedAt ?? .distantPast) }
            .prefix(10)
            .map { (src, art) in
                WidgetArticle(id: art.id, title: art.title,
                              sourceName: art.sourceName, colorHex: src.colorHex,
                              publishedAt: art.publishedAt)
            }

        let accentHex: String
        switch appTheme {
        case .blackOrange:  accentHex = "#FF7400"
        case .blackBlue:    accentHex = "#3399FF"
        case .blackGreen:   accentHex = "#26DA72"
        case .slatePurple:  accentHex = "#B366FF"
        default:            accentHex = "#007AFF"
        }

        let bgHex: String?
        switch appTheme {
        case .blackOrange, .blackBlue, .blackGreen: bgHex = "#0F0F0F"
        case .slatePurple:                          bgHex = "#1A1721"
        case .dark:                                 bgHex = "#1C1C1E"
        default:                                    bgHex = nil
        }

        let payload = WidgetData(articles: Array(top),
                                 backgroundColorHex: bgHex,
                                 accentColorHex: accentHex,
                                 listFontSize: listFontSize)
        let url = seenFileURL.deletingLastPathComponent().appendingPathComponent("widget_articles.json")
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: – Widget-kommandoer (knapper i widgetten skriver hertil, appen poller)

    private var widgetCmdURL: URL {
        seenFileURL.deletingLastPathComponent().appendingPathComponent("widget_cmd.json")
    }

    private func startWidgetCommandWatcher() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await processWidgetCommand()
            }
        }
    }

    @MainActor
    private func processWidgetCommand() {
        guard let data = try? Data(contentsOf: widgetCmdURL),
              let cmd = try? JSONDecoder().decode([String: String].self, from: data),
              let action = cmd["cmd"] else { return }
        try? FileManager.default.removeItem(at: widgetCmdURL)
        switch action {
        case "markAllRead":  markAllSeen()
        case "increaseFont": listFontSize = min(20, listFontSize + 1)
        case "decreaseFont": listFontSize = max(11, listFontSize - 1)
        default: break
        }
    }

    // MARK: – Auto-refresh

    /// Tikker hvert 30. sekund og refresher når nextRefreshAt passeres.
    /// Interval-ændringer slår dermed igennem med det samme.
    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if let next = nextRefreshAt, Date() >= next, !isLoading {
                await refresh()
            }
        }
    }

    // MARK: – Breaking News

    func checkBreakingNews() async {
        let articles = activeSources.flatMap { articlesBySource[$0.id] ?? [] }
        let fresh = articles.filter { !notifiedArticleIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let checked = Array(fresh.prefix(40))
        let titles = checked.map { "[\($0.sourceName)] \($0.title)" }.joined(separator: "\n")
        let prompt = """
        Du er en nyhedsredaktør. Gennemgå disse overskrifter og identificér eventuelle breaking news / store nyheder der er ekstraordinære eller meget vigtige.
        Returner KUN valid JSON i dette format (ingen andre tegn):
        {"breaking":[{"title":"...","source":"..."}]}
        Returner {"breaking":[]} hvis der ikke er breaking news.
        Overskrifter:
        \(titles)
        """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 512,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Markér som kontrolleret uanset svar — ellers spørger vi om de samme igen
        defer {
            for a in checked where !notifiedArticleIDs.contains(a.id) {
                notifiedArticleIDs.insert(a.id)
                notifiedOrder.append(a.id)
            }
            saveNotified()
        }

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String,
              let jsonData = text.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let breakingArr = result["breaking"] as? [[String: Any]] else { return }

        for item in breakingArr {
            guard let title = item["title"] as? String,
                  let source = item["source"] as? String else { continue }
            await sendBreakingNotification(title: title, source: source)
        }
    }

    private func sendBreakingNotification(title: String, source: String) async {
        let content = UNMutableNotificationContent()
        content.title = "🔴 Breaking: \(source)"
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: – Feed fetch

    struct FetchOutcome: Sendable {
        var articles: [Article] = []
        var etag: String?
        var lastModified: String?
        var notModified = false
        var errorText: String?
    }

    nonisolated static func fetchFeed(source: FeedSource,
                                      etag: String?,
                                      lastModified: String?) async -> FetchOutcome {
        guard let url = URL(string: source.url) else {
            return FetchOutcome(errorText: "Ugyldig URL")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("da-DK,da;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // Conditional GET — server svarer 304 hvis intet er ændret siden sidst
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { req.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            if http?.statusCode == 304 {
                return FetchOutcome(notModified: true)
            }
            if let code = http?.statusCode, !(200..<300).contains(code) {
                return FetchOutcome(errorText: "HTTP \(code)")
            }
            let articles = RSSParser().parse(data: data).prefix(50).compactMap { p -> Article? in
                guard let link = URL(string: p.link) else { return nil }
                // Rens titel: RSS-feeds kan have indbagt \n, \t og ekstra mellemrum
                let cleanTitle = p.title
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return Article(id: normalizedArticleID(p.link), title: cleanTitle, url: link,
                               sourceName: source.name, sourceID: source.id,
                               publishedAt: parseRSSDate(p.pubDate),
                               thumbnailURL: p.imageURL.flatMap { URL(string: $0) },
                               tags: p.tags,
                               seen: false)
            }
            var outcome = FetchOutcome(articles: Array(articles))
            outcome.etag = http?.value(forHTTPHeaderField: "ETag")
            outcome.lastModified = http?.value(forHTTPHeaderField: "Last-Modified")
            if articles.isEmpty { outcome.errorText = "Intet læsbart feed" }
            return outcome
        } catch {
            return FetchOutcome(errorText: "Netværksfejl")
        }
    }

    // Henter én eller flere URLs for en kilde og merger artiklerne (dedupliceret på id).
    // For single-URL sources bruges ETag/Last-Modified caching som normalt.
    // For multi-URL sources hentes alle feeds parallelt uden caching.
    nonisolated static func fetchAllURLs(source: FeedSource,
                                         etag: String?,
                                         lastModified: String?) async -> FetchOutcome {
        guard source.additionalURLs.isEmpty else {
            // Hent alle URLs parallelt og merge
            let outcomes = await withTaskGroup(of: FetchOutcome.self) { group in
                for urlString in source.allURLs {
                    let s = FeedSource(id: source.id, name: source.name, url: urlString,
                                       colorHex: source.colorHex, filterCommercial: source.filterCommercial)
                    group.addTask { await fetchFeed(source: s, etag: nil, lastModified: nil) }
                }
                var results: [FetchOutcome] = []
                for await o in group { results.append(o) }
                return results
            }
            var seen = Set<String>()
            let merged = outcomes
                .flatMap { $0.articles }
                .filter { seen.insert($0.id).inserted }
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            let errors = outcomes.compactMap(\.errorText)
            return FetchOutcome(articles: merged,
                                errorText: merged.isEmpty ? errors.first : nil)
        }
        return await fetchFeed(source: source, etag: etag, lastModified: lastModified)
    }

    nonisolated static func parseRSSDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        let formats = ["EEE, dd MMM yyyy HH:mm:ss Z","EEE, dd MMM yyyy HH:mm:ss zzz",
                       "yyyy-MM-dd'T'HH:mm:ssZ","yyyy-MM-dd'T'HH:mm:ss.SSSZ","yyyy-MM-dd'T'HH:mm:ssXXXXX"]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats { df.dateFormat = fmt; if let d = df.date(from: str) { return d } }
        return nil
    }
}

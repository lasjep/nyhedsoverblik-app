import SwiftUI

// Ét kort i grid'et — clusters repræsenteres af deres nyeste artikel
// med kilde-antal som badge (samme nyhed vises aldrig to gange)
private struct CardItem: Identifiable {
    let article: Article
    let sourceCount: Int
    var id: String { article.id }
}

struct ArticleGridView: View {
    @EnvironmentObject var store: FeedStore
    @Environment(\.isPortraitLayout) private var isPortraitLayout
    @Environment(\.openWindow) private var openWindow

    // Piletasts-navigation i listen — uafhængig af hvilken artikel der er åben i browseren,
    // så piletasterne kan flytte "cursoren" og scrolle listen uden at det tvinger fokus
    // væk fra WKWebView (som ellers stjæler alle piletryk permanent, da den er den
    // eneste NSResponder-accepterende view i vinduet).
    @FocusState private var listFocused: Bool
    @State private var cursorID: String?

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: store.gridMinWidth, maximum: store.gridMinWidth * 1.6), spacing: 10)]
    }

    // To-lags grid: billed-kort i fuld størrelse, tekst-kort samlet i bånd af
    // halv højde — kronologien ofres en anelse inden for hvert bånd, til
    // gengæld brydes rytmen aldrig af enlige tekst-kort
    private enum GridBand: Identifiable {
        case full([CardItem])   // kort med billede
        case half([CardItem])   // kort uden billede, halv højde
        var id: String {
            switch self {
            case .full(let items): return "f|" + (items.first?.id ?? "")
            case .half(let items): return "h|" + (items.first?.id ?? "")
            }
        }
        var items: [CardItem] {
            switch self {
            case .full(let i), .half(let i): return i
            }
        }
    }

    private var gridBands: [GridBand] {
        var bands: [GridBand] = []
        var imgBuf: [CardItem] = []
        var txtBuf: [CardItem] = []

        for item in store.feedItems {
            let card: CardItem
            switch item {
            case .single(let a):  card = CardItem(article: a, sourceCount: 1)
            case .cluster(let c): card = CardItem(article: c.articles[0], sourceCount: c.articles.count)
            }
            if store.showThumbnails && card.article.thumbnailURL != nil {
                imgBuf.append(card)
                if imgBuf.count >= 12 { bands.append(.full(imgBuf)); imgBuf = [] }
            } else {
                txtBuf.append(card)
                if txtBuf.count >= 24 { bands.append(.half(txtBuf)); txtBuf = [] }
            }
        }
        if !imgBuf.isEmpty { bands.append(.full(imgBuf)) }
        if !txtBuf.isEmpty { bands.append(.half(txtBuf)) }
        return bands
    }

    var body: some View {
        // ÉN fælles ScrollViewReader om det hele — proxy'en er så garanteret klar
        // med det samme (ingen afhængighed af .onAppear-timing i tre separate views).
        ScrollViewReader { proxy in
            Group {
                if store.isLoading && store.visibleArticles.isEmpty {
                    // Første hentning efter appstart → flot splash med fremdrift;
                    // senere tomme refreshes → diskret spinner
                    if store.lastUpdated == nil {
                        SplashView()
                    } else {
                        loadingView
                    }
                } else if store.visibleArticles.isEmpty {
                    emptyView
                } else if store.viewMode == .list {
                    articleList
                } else if store.viewMode == .compact {
                    compactList
                } else if store.viewMode == .themes {
                    themesList
                } else {
                    scrollGrid
                }
            }
            .toolbar { toolbarContent }
            #if os(macOS)
            .searchable(text: $store.searchText, placement: .toolbar, prompt: "Søg i overskrifter")
            #else
            .searchable(text: $store.searchText, prompt: "Søg i overskrifter")
            #endif
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .simultaneousGesture(TapGesture().onEnded { listFocused = true })
            .onAppear { listFocused = true }
            .onChange(of: store.viewMode) { _, _ in cursorID = nil }
            .onKeyPress(.downArrow) { moveCursor(by: 1, proxy: proxy); return .handled }
            .onKeyPress(.upArrow)   { moveCursor(by: -1, proxy: proxy); return .handled }
            .onKeyPress(.return)    { openCursorArticle(); return .handled }
        }
    }

    // MARK: – Piletasts-navigation

    private var navigableIDs: [String] {
        switch store.viewMode {
        case .grid:   return gridBands.map(\.id)
        case .themes: return store.themedItems.flatMap { $0.items.map(\.id) }
        default:      return store.feedItems.map(\.id)
        }
    }

    private func moveCursor(by delta: Int, proxy: ScrollViewProxy) {
        let ids = navigableIDs
        guard !ids.isEmpty else { return }
        let currentIndex = cursorID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let newIndex = min(max(currentIndex + delta, 0), ids.count - 1)
        // VIGTIGT: scrollTo skal have en ikke-optional String — Optional("x")
        // hasher anderledes end "x" og matcher aldrig rækkernes .id()
        let newID = ids[newIndex]
        cursorID = newID
        proxy.scrollTo(newID, anchor: .center)
    }

    private func openCursorArticle() {
        guard let id = cursorID else { return }
        switch store.viewMode {
        case .grid:
            if let band = gridBands.first(where: { $0.id == id }),
               let first = band.items.first {
                store.openArticle(first.article)
            }
        case .themes:
            for group in store.themedItems {
                guard let item = group.items.first(where: { $0.id == id }) else { continue }
                switch item {
                case .single(let a):  store.openArticle(a)
                case .cluster(let c): store.openArticle(c.articles[0])
                }
                return
            }
        default:
            guard let item = store.feedItems.first(where: { $0.id == id }) else { return }
            switch item {
            case .single(let a):  store.openArticle(a)
            case .cluster(let c): store.openArticle(c.articles[0])
            }
        }
    }

    private func isCursor(_ id: String) -> Bool { cursorID == id }

    // Rækkeluft der glider kontinuerligt med skriftstørrelsen — ingen tærskel-spring

    // MARK: – Indholds-views

    private var scrollGrid: some View {
        // GeometryReader ØVERST — giver stabil bredde til alle grid-grupper
        GeometryReader { geo in
            let availW = geo.size.width - 24   // minus horisontal padding
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(gridBands) { band in
                        NonLazyVGrid(items: band.items,
                                     containerWidth: availW,
                                     minColWidth: store.gridMinWidth,
                                     spacing: 10,
                                     halfHeight: {
                                         if case .half = band { return true }
                                         return false
                                     }(),
                                     store: store)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isCursor(band.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                        .id(band.id)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }


    // Udpak et FeedItem til (repræsentativ artikel, antal kilder)
    private func unpack(_ item: FeedItem) -> (article: Article, count: Int) {
        switch item {
        case .single(let a):  return (a, 1)
        case .cluster(let c): return (c.articles[0], c.articles.count)
        }
    }

    // Liste: 2-linjet med lille thumbnail på ALLE rækker (billede eller placeholder)
    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feedItems) { item in
                    let u = unpack(item)
                    ArticleListRow(article: u.article, showThumbnail: true, sourceCount: u.count)
                        .background(isCursor(item.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                        .id(item.id)
                    Divider().padding(.leading, 14)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // Kompakt: ren tekst, 1 linje, ingen billeder — maksimal tæthed
    private var compactList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feedItems) { item in
                    let u = unpack(item)
                    CompactArticleRow(article: u.article, sourceCount: u.count)
                        .padding(.horizontal, 12)
                        .background(isCursor(item.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                        .id(item.id)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Temaer (kolonner side om side — alle temaer synlige på én gang)

    private var themesList: some View {
        // Faste tema-kolonner i kanonisk rækkefølge; tomme temaer udelades.
        // I portrait (iPad) stables de lodret, ellers side om side.
        let groups = store.themedItems
        return Group {
            if isPortraitLayout {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(groups) { themeColumn($0, fixedHeight: false) }
                    }
                    .padding(10)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(groups) { themeColumn($0, fixedHeight: true) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func themeColumn(_ group: ThemedGroup, fixedHeight: Bool) -> some View {
        let unseen = group.articles.filter { !$0.seen }.count
        return VStack(spacing: 0) {
            // Farvet header
            HStack(spacing: 7) {
                Image(systemName: group.theme.icon)
                    .font(.system(size: 13, weight: .bold))
                Text(group.theme.displayName)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                Spacer()
                Text("\(unseen)")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.white.opacity(0.25), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(group.theme.tint)

            // Artikler
            let rows = ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(group.items) { item in
                        let u = unpack(item)
                        CompactArticleRow(article: u.article, sourceCount: u.count)
                            .padding(.horizontal, 10)
                            .background(isCursor(item.id) ? Color.accentColor.opacity(0.14) : Color.clear)
                            .id(item.id)
                        Divider().padding(.leading, 18)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(group.theme.tint.opacity(0.06))

            if fixedHeight { rows } else { rows.frame(height: 320) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(group.theme.tint.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Henter nyheder…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Ingen nyheder", systemImage: "newspaper")
        } description: {
            Text(store.searchText.isEmpty
                 ? "Tryk ⌘R for at opdatere"
                 : "Ingen artikler matcher \"\(store.searchText)\"")
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button {
                openWindow(id: "mini-widget")
            } label: {
                Image(systemName: "rectangle.stack")
            }
            .help("Åbn mini-widget")
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            modeButtons
            Divider()
            thumbnailButton
            aiButton
            fontButton
            Divider()
            gridSizeButtons
        }
        #else
        // iPadOS gemmer .secondaryAction væk i "…"-menuen — vis kontrollerne direkte.
        // I portrait overtager det flydende glas-bånd visningsvalget.
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isPortraitLayout {
                Picker("Visning", selection: $store.viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet.rectangle").tag(ViewMode.list)
                    Image(systemName: "list.dash").tag(ViewMode.compact)
                    Image(systemName: "rectangle.3.group").tag(ViewMode.themes)
                }
                .pickerStyle(.segmented)
            }

            Menu {
                Toggle(isOn: $store.showThumbnails) {
                    Label("Vis billeder", systemImage: "photo")
                }
                Toggle(isOn: $store.aiRewrite) {
                    Label("AI-overskrifter", systemImage: "sparkles")
                }
                Toggle(isOn: $store.serifHeadlines) {
                    Label("Avis-skrifttype (serif)", systemImage: "textformat")
                }
                Section("Størrelse") {
                    Button {
                        if store.viewMode == .grid { store.gridMinWidth = min(380, store.gridMinWidth + 30) }
                        else { store.listFontSize = min(20, store.listFontSize + 1) }
                    } label: { Label("Større", systemImage: "plus.magnifyingglass") }
                    Button {
                        if store.viewMode == .grid { store.gridMinWidth = max(140, store.gridMinWidth - 30) }
                        else { store.listFontSize = max(11, store.listFontSize - 1) }
                    } label: { Label("Mindre", systemImage: "minus.magnifyingglass") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        #endif

        #if os(macOS)
        ToolbarItem(placement: .status) {
            // Opdateres pr. minut — ikke pr. sekund
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(spacing: 6) {
                    if let updated = store.lastUpdated {
                        Text(updated.timeIntervalSinceNow > -90
                             ? "Opdateret lige nu"
                             : "Opdateret for \(relativeTime(updated)) siden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let next = store.nextRefreshAt, next > Date() {
                        Text("· næste om \(max(1, Int(next.timeIntervalSinceNow / 60))) min.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        #endif

        ToolbarItem {
            Button("Marker alle set") { store.markAllSeen() }
                .disabled(store.unseenCount() == 0)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Opdater", systemImage: "arrow.clockwise")
                }
            }
            .disabled(store.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // De tre tilstande som et segmenteret sæt knapper
    private var modeButtons: some View {
        HStack(spacing: 0) {
            modeBtn(mode: .grid,    icon: "square.grid.2x2",   help: "Tiles")
            Divider().frame(height: 18)
            modeBtn(mode: .list,    icon: "list.bullet.rectangle", help: "Liste")
            Divider().frame(height: 18)
            modeBtn(mode: .compact, icon: "list.dash",         help: "Kompakt")
            Divider().frame(height: 18)
            modeBtn(mode: .themes,  icon: "rectangle.3.group", help: "Temaer")
        }
        .buttonStyle(.borderless)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.platformSeparator, lineWidth: 1))
    }

    private func modeBtn(mode: ViewMode, icon: String, help: String) -> some View {
        let active = store.viewMode == mode
        return Button {
            store.viewMode = mode
            store.savePrefs()
        } label: {
            Image(systemName: icon)
                .frame(width: 28, height: 22)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
        }
        .help(help)
    }

    private var thumbnailButton: some View {
        let active = store.showThumbnails && store.viewMode == .grid
        return Button {
            store.showThumbnails.toggle()
            store.savePrefs()
        } label: {
            Image(systemName: "photo")
                .frame(width: 28, height: 22)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.borderless)
        .disabled(store.viewMode != .grid)
        .help("Billeder til/fra")
    }

    private var aiButton: some View {
        let active = store.aiRewrite
        return Button {
            store.aiRewrite.toggle()
            if store.aiRewrite && !store.apiKey.isEmpty {
                Task { await store.rewriteNewTitles() }
            }
        } label: {
            Image(systemName: store.isRewriting ? "sparkles" : "sparkles")
                .symbolEffect(.pulse, isActive: store.isRewriting)
                .frame(width: 28, height: 22)
                .background(active ? Color.purple.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? Color.purple : Color.primary)
        }
        .buttonStyle(.borderless)
        .help(store.apiKey.isEmpty ? "AI-omskrivning (kræver API-nøgle)" : "AI-overskrifter til/fra")
    }

    // Skift mellem avis- (serif) og moderne (sans) skrifttype
    private var fontButton: some View {
        Button {
            store.serifHeadlines.toggle()
        } label: {
            Text(store.serifHeadlines ? "A" : "A")
                .font(.system(size: 14, weight: .semibold,
                              design: store.serifHeadlines ? .serif : .default))
                .frame(width: 28, height: 22)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .help(store.serifHeadlines ? "Skrifttype: Avis (serif) — klik for Moderne"
                                   : "Skrifttype: Moderne (sans) — klik for Avis")
    }

    private var gridSizeButtons: some View {
        HStack(spacing: 0) {
            Button {
                if store.viewMode == .grid {
                    store.gridMinWidth = max(140, store.gridMinWidth - 30)
                } else {
                    store.listFontSize = max(11, store.listFontSize - 1)
                }
                store.savePrefs()
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 22)
            }
            .disabled(store.viewMode == .grid ? store.gridMinWidth <= 140
                                              : store.listFontSize <= 11)

            Divider().frame(height: 18)

            Button {
                if store.viewMode == .grid {
                    store.gridMinWidth = min(380, store.gridMinWidth + 30)
                } else {
                    store.listFontSize = min(20, store.listFontSize + 1)
                }
                store.savePrefs()
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 22)
            }
            .disabled(store.viewMode == .grid ? store.gridMinWidth >= 380
                                              : store.listFontSize >= 20)
        }
        .buttonStyle(.borderless)
        .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.platformSeparator, lineWidth: 1))
    }
}

// MARK: – Grid med fast beregnet højde (ingen GeometryReader = ingen overlap)

private struct NonLazyVGrid: View {
    let items: [CardItem]
    let containerWidth: CGFloat   // målt én gang i parent
    let minColWidth: CGFloat
    let spacing: CGFloat
    var halfHeight = false        // tekst-kort-bånd: halv korthøjde
    let store: FeedStore

    private var colCount: Int  { max(1, Int(containerWidth / minColWidth)) }
    private var colWidth: CGFloat { (containerWidth - spacing * CGFloat(colCount - 1)) / CGFloat(colCount) }
    private var fullHeight: CGFloat { colWidth * (9.0 / 16.0) + 100 }
    private var cardHeight: CGFloat { halfHeight ? (fullHeight - spacing) / 2 : fullHeight }
    private var rowCount: Int { (items.count + colCount - 1) / colCount }
    private var totalHeight: CGFloat {
        CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * spacing
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<colCount, id: \.self) { col in
                        let idx = row * colCount + col
                        if idx < items.count {
                            ArticleCard(article: items[idx].article,
                                        sourceCount: items[idx].sourceCount)
                                .environmentObject(store)
                                .frame(width: colWidth, height: cardHeight)
                        } else {
                            Color.clear
                                .frame(width: colWidth, height: cardHeight)
                        }
                    }
                }
            }
        }
        .frame(width: containerWidth, height: totalHeight)
    }
}

import SwiftUI

// Segment til blandet grid/liste-layout
private struct FeedSegment: Identifiable {
    enum Kind {
        case imageGroup([Article])   // artikler med thumbnail → vises som grid
        case textRow(Article)        // artikler uden thumbnail → vises som listelinjer
        case cluster(StoryCluster)   // flere artikler om samme nyhed → grupperet
    }
    let id: String
    let kind: Kind
}

struct ArticleGridView: View {
    @EnvironmentObject var store: FeedStore
    @Environment(\.isPortraitLayout) private var isPortraitLayout
    @Environment(\.openWindow) private var openWindow
    @State private var expandedClusters: Set<String> = []

    // Piletasts-navigation i listen — uafhængig af hvilken artikel der er åben i browseren,
    // så piletasterne kan flytte "cursoren" og scrolle listen uden at det tvinger fokus
    // væk fra WKWebView (som ellers stjæler alle piletryk permanent, da den er den
    // eneste NSResponder-accepterende view i vinduet).
    @FocusState private var listFocused: Bool
    @State private var cursorID: String?

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: store.gridMinWidth, maximum: store.gridMinWidth * 1.6), spacing: 10)]
    }

    // Opdel i segmenter — clustering er allerede beregnet og cachet i FeedStore.
    // Her grupperes kun billede-artikler i buffere så grid-rækkerne fyldes op (billig, lineær).
    private var smartSegments: [FeedSegment] {
        var segments: [FeedSegment] = []
        var imageBuffer: [Article] = []   // samler billede-artikler til at fylde rækker

        func flushImages() {
            guard !imageBuffer.isEmpty else { return }
            let id = imageBuffer.prefix(3).map(\.id).joined(separator: "|")
            segments.append(FeedSegment(id: "img|\(id)", kind: .imageGroup(imageBuffer)))
            imageBuffer = []
        }

        for item in store.feedItems {
            switch item {
            case .single(let article):
                if article.thumbnailURL != nil {
                    imageBuffer.append(article)
                    // Skyl gruppen hvis den er stor nok til at fylde mange rækker
                    if imageBuffer.count >= 12 { flushImages() }
                } else {
                    // Tekst-artikel: læg billederne ud hvis der er nok til mindst én fuld række,
                    // ellers hold dem og lad dem akkumulere (fylder rækken bedre)
                    if imageBuffer.count >= 3 { flushImages() }
                    segments.append(FeedSegment(id: article.id, kind: .textRow(article)))
                }
            case .cluster(let cluster):
                // Skyl billedebufferen før en cluster
                flushImages()
                segments.append(FeedSegment(id: cluster.id, kind: .cluster(cluster)))
            }
        }
        flushImages()
        return segments
    }

    var body: some View {
        // ÉN fælles ScrollViewReader om det hele — proxy'en er så garanteret klar
        // med det samme (ingen afhængighed af .onAppear-timing i tre separate views).
        ScrollViewReader { proxy in
            Group {
                if store.isLoading && store.visibleArticles.isEmpty {
                    loadingView
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
        case .grid:   return smartSegments.map(\.id)
        case .themes: return themedGroups.flatMap { $0.articles.map(\.id) }
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
            guard let seg = smartSegments.first(where: { $0.id == id }) else { return }
            switch seg.kind {
            case .imageGroup(let arts): if let first = arts.first { store.openArticle(first) }
            case .textRow(let a):       store.openArticle(a)
            case .cluster(let c):       store.openArticle(c.articles[0])
            }
        case .themes:
            if let a = store.visibleArticles.first(where: { $0.id == id }) { store.openArticle(a) }
        default:
            guard let item = store.feedItems.first(where: { $0.id == id }) else { return }
            switch item {
            case .single(let a):  store.openArticle(a)
            case .cluster(let c): store.openArticle(c.articles[0])
            }
        }
    }

    private func isCursor(_ id: String) -> Bool { cursorID == id }

    // MARK: – Indholds-views

    private var scrollGrid: some View {
        // GeometryReader ØVERST — giver stabil bredde til alle grid-grupper
        GeometryReader { geo in
            let availW = geo.size.width - 24   // minus horisontal padding
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(smartSegments) { segment in
                        switch segment.kind {
                        case .imageGroup(let articles):
                            NonLazyVGrid(articles: articles,
                                         containerWidth: availW,
                                         minColWidth: store.gridMinWidth,
                                         spacing: 10,
                                         store: store)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isCursor(segment.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .id(segment.id)

                        case .textRow(let article):
                            ArticleListRow(article: article)
                                .environmentObject(store)
                                .background(isCursor(article.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                                .id(segment.id)
                            Divider().padding(.leading, 43)

                        case .cluster(let cluster):
                            clusterRow(cluster)
                                .background(isCursor(cluster.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                                .id(segment.id)
                            Divider().padding(.leading, 43)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    // En cluster af relaterede historier
    private func clusterRow(_ cluster: StoryCluster) -> some View {
        let expanded = expandedClusters.contains(cluster.id)
        return VStack(spacing: 0) {
            // Hoved-række
            Button {
                store.openArticle(cluster.articles[0])
            } label: {
                HStack(alignment: .center, spacing: 0) {
                    // Farve-bar
                    let barColor = cluster.articles.first.flatMap { a in
                        store.sources.first(where: { $0.id == a.sourceID })?.color
                    } ?? Color.secondary
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: 3, height: 32)
                        .padding(.trailing, 12)

                    // Thumbnail hvis tilgængeligt
                    if let thumb = cluster.thumbnailURL {
                        AsyncImage(url: thumb) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(.trailing, 10)
                            } else { EmptyView() }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.displayTitle(for: cluster.articles[0]))
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .lineLimit(2)
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            let a0 = cluster.articles[0]
                            let src = store.sources.first(where: { $0.id == a0.sourceID })
                            Circle().fill(src?.color ?? .secondary).frame(width: 5, height: 5)
                            Text(a0.sourceName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let d = a0.publishedAt {
                                Text("· \(relativeTime(d))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    // Badge: antal kilder
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if expanded { expandedClusters.remove(cluster.id) }
                            else { expandedClusters.insert(cluster.id) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(cluster.articles.count) kilder")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Udvidede under-artikler
            if expanded {
                VStack(spacing: 0) {
                    ForEach(cluster.articles.dropFirst()) { article in
                        Divider().padding(.leading, 43)
                        ArticleListRow(article: article)
                            .environmentObject(store)
                            .padding(.leading, 20)  // indrykket for at vise hierarki
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feedItems) { item in
                    switch item {
                    case .single(let article):
                        ArticleListRow(article: article)
                            .background(isCursor(article.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .id(item.id)
                        Divider().padding(.leading, 43)
                    case .cluster(let cluster):
                        clusterRow(cluster)
                            .background(isCursor(cluster.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .id(item.id)
                        Divider().padding(.leading, 43)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var compactList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feedItems) { item in
                    switch item {
                    case .single(let article):
                        CompactArticleRow(article: article)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .background(isCursor(article.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .id(item.id)
                        Divider().padding(.leading, 28)
                    case .cluster(let cluster):
                        clusterRow(cluster)
                            .background(isCursor(cluster.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            .id(item.id)
                        Divider().padding(.leading, 43)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: – Temaer

    private var themedGroups: [(theme: NewsTheme, articles: [Article])] {
        let grouped = Dictionary(grouping: store.visibleArticles) {
            classifyTheme(url: $0.id, sourceID: $0.sourceID, tags: $0.tags)
        }
        return NewsTheme.allCases.compactMap { theme in
            guard let arts = grouped[theme], !arts.isEmpty else { return nil }
            return (theme, arts)
        }
    }

    private var themesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(themedGroups, id: \.theme) { group in
                    Section {
                        ForEach(group.articles) { article in
                            ArticleListRow(article: article)
                                .background(isCursor(article.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                            Divider().padding(.leading, 43)
                        }
                    } header: {
                        themeHeader(group.theme,
                                    total: group.articles.count,
                                    unseen: group.articles.filter { !$0.seen }.count)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func themeHeader(_ theme: NewsTheme, total: Int, unseen: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: theme.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(theme.displayName)
                .font(.system(size: 15, weight: .bold, design: .serif))
            Text(unseen > 0 ? "\(unseen) ulæste af \(total)" : "\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
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
    let articles: [Article]
    let containerWidth: CGFloat   // målt én gang i parent
    let minColWidth: CGFloat
    let spacing: CGFloat
    let store: FeedStore

    private var colCount: Int  { max(1, Int(containerWidth / minColWidth)) }
    private var colWidth: CGFloat { (containerWidth - spacing * CGFloat(colCount - 1)) / CGFloat(colCount) }
    private var cardHeight: CGFloat { colWidth * (9.0 / 16.0) + 100 }
    private var rowCount: Int { (articles.count + colCount - 1) / colCount }
    private var totalHeight: CGFloat {
        CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * spacing
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<colCount, id: \.self) { col in
                        let idx = row * colCount + col
                        if idx < articles.count {
                            ArticleCard(article: articles[idx])
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

import SwiftUI

// MARK: – Rod-view der vælger layout efter orientering
// (size classes er .regular/.regular i BEGGE orienteringer på iPad, så vi måler selv)

struct IOSRootView: View {
    @EnvironmentObject var store: FeedStore

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > geo.size.width {
                PortraitRootView()
            } else {
                ContentView()   // landscape: samme tre-kolonne layout som macOS
            }
        }
    }
}

// MARK: – Portrait: fuldskærms-feed eller læser-tilstand med filmstrimmel

struct PortraitRootView: View {
    @EnvironmentObject var store: FeedStore
    @State private var showSources = false
    @State private var stripExpanded = false

    // Stabil læsekø: snapshot af listen når læseren åbnes.
    // Uden den forsvinder artikler fra strimlen under bladring,
    // når "Skjul læste" er slået til (læste ryger ud af visibleArticles).
    @State private var readingQueue: [Article] = []

    private var queueArticles: [Article] {
        readingQueue.isEmpty ? store.visibleArticles : readingQueue
    }

    var body: some View {
        NavigationStack {
            if store.selectedArticle != nil {
                readerLayout
            } else {
                feedLayout
            }
        }
        .onChange(of: store.selectedArticle?.id) { old, new in
            if old == nil && new != nil {
                // Læser åbnet fra feedet → frys køen
                readingQueue = store.visibleArticles
            } else if new == nil {
                readingQueue = []
                stripExpanded = false
            }
        }
    }

    // Feed: grid/liste i fuld bredde + flydende glas-bånd til visningsvalg
    private var feedLayout: some View {
        ArticleGridView()
            .environment(\.isPortraitLayout, true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSources = true
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
            .sheet(isPresented: $showSources) {
                SidebarView()
                    .presentationDetents([.medium, .large])
            }
            .overlay(alignment: .bottom) {
                ViewModeBand()
                    .padding(.bottom, 16)
            }
    }

    // Læser: browser i fuld bredde, læseliste som strimmel i bunden
    private var readerLayout: some View {
        VStack(spacing: 0) {
            BrowserPanel(model: store.webViewModel)
                .toolbar(.hidden, for: .navigationBar)

            filmstrip
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Filmstrimmel

    private var filmstrip: some View {
        VStack(spacing: 0) {
            handle
            if stripExpanded {
                expandedPanel
            } else {
                horizontalStrip
            }
        }
        // Eksplicit baggrund til mørke temaer (blackOrange m.fl.) — glassEffect
        // er translucent og ser lysere ud end resten af appen uden denne.
        .background(
            (store.appTheme.backgroundColor ?? Color.clear)
                .opacity(0.96),
            in: .rect(topLeadingRadius: 28, topTrailingRadius: 28)
        )
        .glassEffect(.regular, in: .rect(topLeadingRadius: 28, topTrailingRadius: 28))
    }

    // Håndtag — tryk eller lodret træk. Gestussen sidder KUN her,
    // så vandret scroll i strimlen aldrig kan udløse expand/collapse.
    private var handle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                stripExpanded.toggle()
            }
        } label: {
            VStack(spacing: 3) {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 40, height: 5)
                Image(systemName: stripExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { v in
                    // Kun lodret-dominerende træk tæller
                    guard abs(v.translation.height) > abs(v.translation.width) else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        stripExpanded = v.translation.height < 0
                    }
                }
        )
    }

    // Én række kort — LazyHStack så kun synlige kort renderes (ProMotion-glat)
    private var horizontalStrip: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(queueArticles) { article in
                            stripCard(article)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                }
                .onChange(of: store.selectedArticle?.id) { _, id in
                    if let id {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .onAppear {
                    if let id = store.selectedArticle?.id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            // Marker-alle knap i trailing edge af den kollapsede strimmel
            markAllStripButton
                .padding(.trailing, 12)
        }
        .frame(height: 118)
    }

    // Udvidet panel: 2-rækkers galleri / liste / kompakt + visningsskift
    private var expandedPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                miniModeSwitcher
                Spacer(minLength: 4)
                stripSizeButtons
                markAllStripButton
            }
            .padding(.horizontal, 12)

            switch store.viewMode {
            case .grid:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(82), spacing: 10),
                                     GridItem(.fixed(82))],
                              spacing: 10) {
                        ForEach(queueArticles) { article in
                            stripCard(article)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .frame(height: 192)

            case .list:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queueArticles) { article in
                            ArticleListRow(article: article)
                            Divider().padding(.leading, 43)
                        }
                    }
                    .padding(.bottom, 14)
                }
                .frame(height: 400)

            case .compact:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queueArticles) { article in
                            CompactArticleRow(article: article)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 3)
                            Divider().padding(.leading, 32)
                        }
                    }
                    .padding(.bottom, 14)
                }
                .frame(height: 400)

            case .themes:
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(themedQueue, id: \.theme) { group in
                            Section {
                                ForEach(group.articles) { article in
                                    ArticleListRow(article: article)
                                    Divider().padding(.leading, 43)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: group.theme.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(group.theme.displayName)
                                        .font(.system(size: 13, weight: .bold, design: .serif))
                                    Text("\(group.articles.count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(.bar)
                            }
                        }
                    }
                    .padding(.bottom, 14)
                }
                .frame(height: 400)
            }
        }
    }

    // Artikler i køen grupperet efter tema (fast rækkefølge, tomme temaer udelades)
    private var themedQueue: [(theme: NewsTheme, articles: [Article])] {
        let grouped = Dictionary(grouping: queueArticles) {
            classifyTheme(url: $0.id, sourceID: $0.sourceID, tags: $0.tags)
        }
        return NewsTheme.allCases.compactMap { theme in
            guard let arts = grouped[theme], !arts.isEmpty else { return nil }
            return (theme, arts)
        }
    }

    private func stripCard(_ article: Article) -> some View {
        FilmstripCard(article: article,
                      isActive: article.id == store.selectedArticle?.id,
                      isSeen: store.isSeen(article.id))
            .id(article.id)
            .onTapGesture { store.openArticle(article) }
    }

    // +/- tekststørrelse (gælder liste + kompakt; i galleri skalerer kortene fast)
    private var stripSizeButtons: some View {
        HStack(spacing: 0) {
            Button {
                store.listFontSize = max(11, store.listFontSize - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 28)
            }
            .disabled(store.listFontSize <= 11 || store.viewMode == .grid)

            Divider().frame(height: 16)

            Button {
                store.listFontSize = min(20, store.listFontSize + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 28)
            }
            .disabled(store.listFontSize >= 20 || store.viewMode == .grid)
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
    }

    // "Marker alle læst" — lille knap til brug i strimlen
    private var markAllStripButton: some View {
        Button {
            store.markAllSeen()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 28)
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
        .disabled(store.unseenCount() == 0)
    }

    // Lille visningsskifter inde i det udvidede panel
    private var miniModeSwitcher: some View {
        HStack(spacing: 2) {
            miniModeButton(.grid, "square.grid.2x2")
            miniModeButton(.list, "list.bullet.rectangle")
            miniModeButton(.compact, "list.dash")
            miniModeButton(.themes, "rectangle.3.group")
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
    }

    private func miniModeButton(_ mode: ViewMode, _ icon: String) -> some View {
        let selected = store.viewMode == mode
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                store.viewMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 38, height: 28)
                .background {
                    if selected {
                        Capsule().fill(Color.accentColor.opacity(0.18))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Kort i filmstrimlen
// Bevidst IKKE glassEffect per kort — mange glas-flader i scrollende indhold
// koster for meget GPU og hakker. Materiale-baggrund er nær-identisk og flydende.

struct FilmstripCard: View {
    let article: Article
    let isActive: Bool
    let isSeen: Bool
    @EnvironmentObject var store: FeedStore

    private var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    var body: some View {
        HStack(spacing: 10) {
            if let thumb = article.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.platformSeparator.opacity(0.25)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayTitle(for: article))
                    .font(.system(size: 12, weight: .semibold, design: store.headlineFontDesign))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(isSeen && !isActive ? .secondary : .primary)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Circle().fill(sourceColor).frame(width: 5, height: 5)
                    Text(article.sourceName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let d = article.publishedAt {
                        Text(relativeTime(d))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 235, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.20))
                               : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.accentColor.opacity(0.6)
                                 : Color.platformSeparator.opacity(0.5),
                        lineWidth: isActive ? 1.5 : 0.5)
        )
        .opacity(isSeen && !isActive ? 0.6 : 1)
    }
}

// MARK: – Glas-bånd med slider til visningsvalg (galleri / liste / kompakt)

struct ViewModeBand: View {
    @EnvironmentObject var store: FeedStore
    @Namespace private var ns
    @State private var bandWidth: CGFloat = 1

    private let modes: [(mode: ViewMode, icon: String, label: String)] = [
        (.grid,    "square.grid.2x2",       "Galleri"),
        (.list,    "list.bullet.rectangle", "Liste"),
        (.compact, "list.dash",             "Kompakt"),
        (.themes,  "rectangle.3.group",     "Temaer"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.mode) { item in
                let selected = store.viewMode == item.mode
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .medium))
                    if selected {
                        Text(item.label)
                            .font(.system(size: 14, weight: .semibold))
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
                .padding(.horizontal, selected ? 16 : 14)
                .frame(height: 42)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.22))
                            .matchedGeometryEffect(id: "vmThumb", in: ns)
                    }
                }
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            bandWidth = width
        }
        // Slider-gestus: tryk ELLER træk på tværs af båndet for at skifte visning
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let idx = min(modes.count - 1,
                                  max(0, Int(v.location.x / (bandWidth / CGFloat(modes.count)))))
                    let mode = modes[idx].mode
                    if store.viewMode != mode {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            store.viewMode = mode
                        }
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: store.viewMode)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

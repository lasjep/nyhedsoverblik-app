import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var apiKeyInput = ""
    @State private var showKey = false
    @State private var newKeyword = ""

    // Tilføj kilde
    @State private var addSourceURL = ""
    @State private var addSourceName = ""
    @State private var addSourceColor = ""
    @State private var addSourceType: FeedType = .rss
    @State private var addSourceState: AddSourceState = .idle
    @State private var discoveredFeedURL: URL? = nil
    @State private var discoveredSamples: [Article] = []

    enum AddSourceState: Equatable {
        case idle
        case searching
        case found(String)   // feed URL som string
        case notFound(String) // fejlbesked
        case added
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Indstillinger")
                    .font(.system(.title2, design: .serif).weight(.bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Generelt").tag(0)
                Text("Kilder").tag(1)
                Text("AI").tag(2)
                Text("Statistik").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            // Indhold
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: generalTab
                    case 1: sourcesTab
                    case 2: aiTab
                    default: statsTab
                    }
                }
                .padding(24)
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 520)
        #endif
        .onAppear { apiKeyInput = store.apiKey }
    }

    // MARK: – Generelt

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Gem + genberegning sker automatisk via FeedStore-pipelines
            settingsGroup(title: "Indhold") {
                VStack(spacing: 0) {
                    settingsToggle("Skjul sportshistorier", icon: "sportscourt", binding: $store.filterSport)
                    Divider().padding(.leading, 40)
                    settingsToggle("Skjul clickbait", icon: "hand.raised", binding: $store.filterClickbait)
                    Divider().padding(.leading, 40)
                    settingsToggle("Skjul læste artikler", icon: "eye.slash", binding: $store.hideSeen)
                }
            }

            settingsGroup(title: "Blokerede ord") {
                VStack(alignment: .leading, spacing: 0) {
                    // Eksisterende keywords
                    if store.blockedKeywords.isEmpty {
                        HStack {
                            Image(systemName: "xmark.circle").frame(width: 24).foregroundStyle(.secondary)
                            Text("Ingen blokerede ord endnu")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        ForEach(Array(store.blockedKeywords.enumerated()), id: \.offset) { idx, kw in
                            if idx > 0 { Divider().padding(.leading, 40) }
                            HStack {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.8))
                                    .frame(width: 24)
                                    .onTapGesture {
                                        store.blockedKeywords.remove(at: idx)
                                    }
                                Text(kw)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        Divider()
                    }
                    // Tilføj nyt keyword
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green.opacity(0.8))
                            .frame(width: 24)
                        TextField("Tilføj ord eller sætning…", text: $newKeyword)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { addKeyword() }
                        Button("Tilføj") { addKeyword() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            settingsGroup(title: "Opdatering") {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "clock.arrow.2.circlepath").frame(width: 24).foregroundStyle(.secondary)
                        Text("Opdater automatisk hvert")
                        Spacer()
                        Picker("", selection: $store.refreshIntervalMinutes) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("60 min").tag(60)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            settingsGroup(title: "Tema") {
                VStack(spacing: 0) {
                    themeRows
                }
            }

            settingsGroup(title: "Visning") {
                VStack(spacing: 0) {
                    settingsToggle("Vis thumbnails som standard", icon: "photo", binding: $store.showThumbnails)
                    Divider().padding(.leading, 40)
                    HStack {
                        Image(systemName: "textformat").frame(width: 24).foregroundStyle(.secondary)
                        Text("Overskrift-skrifttype")
                        Spacer()
                        Picker("", selection: $store.serifHeadlines) {
                            Text("Avis (serif)").tag(true)
                            Text("Moderne (sans)").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider().padding(.leading, 40)
                    HStack {
                        Image(systemName: "square.grid.2x2").frame(width: 24).foregroundStyle(.secondary)
                        Text("Standard gitterstørrelse")
                        Spacer()
                        HStack(spacing: 6) {
                            Button { store.gridMinWidth = max(140, store.gridMinWidth - 30) } label: {
                                Image(systemName: "minus").frame(width: 20, height: 20)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Text("\(Int(store.gridMinWidth)) px")
                                .font(.caption.monospacedDigit())
                                .frame(width: 60, alignment: .center)
                            Button { store.gridMinWidth = min(380, store.gridMinWidth + 30) } label: {
                                Image(systemName: "plus").frame(width: 20, height: 20)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: – Kilder

    private var sourcesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fjern markeringen for at deaktivere en kilde. Højreklik på en kilde i sidebaren for hurtigt at slå den til/fra.")
                .font(.caption)
                .foregroundStyle(.secondary)

            settingsGroup(title: "Indbyggede feeds") {
                VStack(spacing: 0) {
                    ForEach(Array(defaultFeeds.enumerated()), id: \.element.id) { idx, src in
                        if idx > 0 { Divider().padding(.leading, 40) }
                        sourceRow(src, canDelete: false)
                    }
                }
            }

            if !store.customSources.isEmpty {
                settingsGroup(title: "Egne kilder") {
                    VStack(spacing: 0) {
                        ForEach(Array(store.customSources.enumerated()), id: \.element.id) { idx, src in
                            if idx > 0 { Divider().padding(.leading, 40) }
                            sourceRow(src, canDelete: true)
                        }
                    }
                }
            }

            settingsGroup(title: "Tilføj kilde") {
                VStack(alignment: .leading, spacing: 0) {
                    // URL-felt + Find RSS-knap
                    HStack(spacing: 8) {
                        Image(systemName: "link").frame(width: 24).foregroundStyle(.secondary)
                        TextField("https://eksempel.dk", text: $addSourceURL)
                            .textFieldStyle(.plain)
                            .onSubmit { discoverSource() }
                        Button {
                            discoverSource()
                        } label: {
                            if addSourceState == .searching {
                                ProgressView().controlSize(.small).frame(width: 50)
                            } else {
                                Text("Find RSS")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(addSourceURL.trimmingCharacters(in: .whitespaces).isEmpty
                                  || addSourceState == .searching)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    // Resultat
                    switch addSourceState {
                    case .found(let feedURL):
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            // Feed-type vælger
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .frame(width: 24)
                                Text(feedURL)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            // Eksempel-artikler
                            if !discoveredSamples.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(discoveredSamples.prefix(3)) { art in
                                        HStack {
                                            Circle().fill(.secondary.opacity(0.4)).frame(width: 4, height: 4)
                                            Text(art.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }

                            // Navn-felt
                            HStack(spacing: 8) {
                                Image(systemName: "tag").frame(width: 24).foregroundStyle(.secondary)
                                TextField("Navn på kilden", text: $addSourceName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            // Tilføj-knap
                            HStack {
                                Spacer()
                                Button("Tilføj kilde") {
                                    confirmAddSource(feedURL: feedURL, feedType: .rss)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(addSourceName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    case .notFound(let msg):
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // Tilbyd at tilføje som scrape-kilde
                            HStack(spacing: 8) {
                                Image(systemName: "tag").frame(width: 24).foregroundStyle(.secondary)
                                TextField("Navn på kilden", text: $addSourceName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Spacer()
                                Button("Tilføj som scrape-kilde ⚡") {
                                    confirmAddSource(feedURL: addSourceURL, feedType: .scrape)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(addSourceName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    case .added:
                        Divider()
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 24)
                            Text("Kilde tilføjet!").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func sourceRow(_ src: FeedSource, canDelete: Bool) -> some View {
        HStack {
            Circle().fill(src.color).frame(width: 8, height: 8)
                .padding(.leading, 12).padding(.trailing, 4)
            Text(src.name)
            if src.feedType == .scrape {
                Text("⚡").font(.caption2)
                    .help("Scrape-kilde (ingen RSS)")
            }
            if let err = store.sourceErrors[src.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(err)
            }
            Spacer()
            let count = store.articlesBySource[src.id]?.count ?? 0
            if count > 0 {
                Text("\(count) artikler").font(.caption).foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            Toggle("", isOn: Binding(
                get: { !store.disabledSourceIDs.contains(src.id) },
                set: { _ in store.toggleSource(src.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.trailing, canDelete ? 4 : 12)
            if canDelete {
                Button {
                    store.removeCustomSource(id: src.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help("Fjern kilde")
            }
        }
        .padding(.vertical, 7)
    }

    private func discoverSource() {
        let raw = addSourceURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        addSourceState = .searching
        discoveredSamples = []
        discoveredFeedURL = nil
        Task {
            let result = await RSSDiscovery.discover(urlString: raw)
            switch result {
            case .success(let feed):
                discoveredFeedURL = feed.feedURL
                discoveredSamples = feed.sampleArticles
                // Foreslå navn fra domain
                if addSourceName.isEmpty {
                    addSourceName = feed.title.isEmpty
                        ? (feed.feedURL.host?.replacingOccurrences(of: "www.", with: "") ?? "")
                        : feed.title
                }
                addSourceState = .found(feed.feedURL.absoluteString)
            case .failure(let err):
                addSourceState = .notFound(err.message)
            }
        }
    }

    private func confirmAddSource(feedURL: String, feedType: FeedType) {
        let name = addSourceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let url = URL(string: feedURL.trimmingCharacters(in: .whitespaces)) else { return }
        let idx = store.customSources.count
        let color = customSourceColors[idx % customSourceColors.count]
        // Hash af hele URL'en — to feeds fra samme domæne må ikke kollidere
        let id = "custom_\(stableHash(url.absoluteString))"
        let src = FeedSource(id: id, name: name, url: url.absoluteString,
                             colorHex: color, feedType: feedType, isCustom: true)
        store.addCustomSource(src)
        // Nulstil form
        addSourceURL = ""
        addSourceName = ""
        addSourceState = .added
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.addSourceState = .idle
        }
    }

    // MARK: – AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup(title: "Claude API-nøgle") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "key").frame(width: 24).foregroundStyle(.secondary)
                        if showKey {
                            TextField("sk-ant-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    HStack {
                        Spacer()
                        Button("Gem nøgle") {
                            store.apiKey = apiKeyInput
                            store.savePrefs()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput == store.apiKey)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }
            }

            settingsGroup(title: "Breaking News-overvågning") {
                VStack(spacing: 0) {
                    settingsToggle("Notificer om breaking news", icon: "bell.badge",
                                   binding: $store.breakingNewsEnabled)
                        .onChange(of: store.breakingNewsEnabled) { _, _ in store.savePrefs() }
                    Divider().padding(.leading, 40)
                    HStack {
                        Image(systemName: "info.circle").frame(width: 24).foregroundStyle(.secondary)
                        Text("AI analyserer overskrifter efter hvert refresh og sender en macOS-notifikation ved store nyheder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            settingsGroup(title: "Omskrivning") {
                VStack(spacing: 0) {
                    settingsToggle("Omskriv sensationelle overskrifter", icon: "sparkles",
                                   binding: $store.aiRewrite)
                        .onChange(of: store.aiRewrite) { _, new in
                            if new && !store.apiKey.isEmpty {
                                Task { await store.rewriteNewTitles() }
                            }
                        }
                    Divider().padding(.leading, 40)
                    HStack {
                        Image(systemName: "doc.text").frame(width: 24).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cache")
                            Text("\(store.rewrittenTitles.count) overskrifter omskrevet")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Ryd cache") {
                            store.rewrittenTitles = [:]
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.rewrittenTitles.isEmpty)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }

            if store.apiKey.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Ingen API-nøgle gemt. AI-omskrivning kræver en Anthropic API-nøgle fra console.anthropic.com")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            if store.isRewriting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Omskriver overskrifter…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: – Statistik

    private var statsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Totaler
            HStack(spacing: 12) {
                statCard(value: "\(store.stats.map(\.total).reduce(0, +))",
                         label: "Artikler i alt", icon: "newspaper", color: .accentColor)
                statCard(value: "\(store.stats.map(\.unseen).reduce(0, +))",
                         label: "Ulæste", icon: "envelope.badge", color: .orange)
                statCard(value: "\(store.stats.map(\.rewritten).reduce(0, +))",
                         label: "AI-omskrevet", icon: "sparkles", color: .purple)
            }

            // Per kilde
            settingsGroup(title: "Per kilde") {
                VStack(spacing: 0) {
                    ForEach(Array(store.stats.sorted { $0.total > $1.total }.enumerated()),
                            id: \.element.source.id) { idx, stat in
                        if idx > 0 { Divider().padding(.leading, 12) }
                        HStack(spacing: 10) {
                            Circle().fill(stat.source.color).frame(width: 8, height: 8)
                                .padding(.leading, 12)
                            Text(stat.source.name)
                            Spacer()
                            // Mini bar
                            let maxTotal = store.stats.map(\.total).max() ?? 1
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.platformSeparator)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(stat.source.color)
                                        .frame(width: geo.size.width * CGFloat(stat.total) / CGFloat(maxTotal),
                                               height: 6)
                                }
                            }
                            .frame(width: 80, height: 6)
                            Text("\(stat.unseen)/\(stat.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 55, alignment: .trailing)
                                .padding(.trailing, 12)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    // MARK: – Hjælpekomponenter

    @ViewBuilder
    private var themeRows: some View {
        ForEach(Array(AppTheme.allCases.enumerated()), id: \.element.rawValue) { idx, theme in
            Group {
                if idx > 0 { Divider().padding(.leading, 40) }
                themeRow(theme)
            }
        }
    }

    private func themeRow(_ theme: AppTheme) -> some View {
        Button {
            store.appTheme = theme
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.backgroundColor
                              ?? (theme.colorScheme == .light
                                  ? Color.white
                                  : Color.platformWindowBackground))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.platformSeparator, lineWidth: 1))
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 10, height: 10)
                }
                .padding(.leading, 12)
                Text(theme.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if store.appTheme == theme {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 12)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !kw.isEmpty, !store.blockedKeywords.contains(kw) else { return }
        store.blockedKeywords.append(kw)
        newKeyword = ""
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .background(Color.platformControlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.platformSeparator, lineWidth: 1))
        }
    }

    private func settingsToggle(_ label: String, icon: String, binding: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Toggle("", isOn: binding).toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value).font(.system(.title2, design: .rounded).bold())
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

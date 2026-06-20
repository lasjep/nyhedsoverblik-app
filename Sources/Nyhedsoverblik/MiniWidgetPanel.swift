#if os(macOS)
import SwiftUI

struct MiniWidgetPanel: View {
    @EnvironmentObject var store: FeedStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            articleList
        }
        .frame(width: 380, height: 520)
        .background(Color.platformWindowBackground)
        // Når en artikel åbnes fra mini-panelet: bring hoved-vinduet frem
        // (det kan være minimeret i Dock og ville ellers ikke vise artiklen)
        .onReceive(store.$selectedArticle) { article in
            guard article != nil else { return }
            for window in NSApp.windows where window.title == "Nyhedsoverblik" {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("N")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(store.appTheme.accentColor, in: RoundedRectangle(cornerRadius: 5))

            Text("Nyhedsoverblik")
                .font(.headline)

            Spacer()

            // Tekststørrelse
            HStack(spacing: 0) {
                Button {
                    store.listFontSize = max(11, store.listFontSize - 1)
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }
                .disabled(store.listFontSize <= 11)

                Divider().frame(height: 14)

                Button {
                    store.listFontSize = min(20, store.listFontSize + 1)
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 22)
                }
                .disabled(store.listFontSize >= 20)
            }
            .buttonStyle(.borderless)
            .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.platformSeparator, lineWidth: 1))

            Button {
                store.markAllSeen()
            } label: {
                Label("Marker alle læst", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(store.unseenCount() == 0)
            .help("Marker alle læst")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feedItems.prefix(20)) { item in
                    switch item {
                    case .single(let article):
                        CompactArticleRow(article: article)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                        Divider().padding(.leading, 28)
                    case .cluster(let cluster):
                        miniClusterRow(cluster)
                        Divider().padding(.leading, 28)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func miniClusterRow(_ cluster: StoryCluster) -> some View {
        let a = cluster.articles[0]
        let src = store.sources.first(where: { $0.id == a.sourceID })
        return Button { store.openArticle(a) } label: {
            HStack(spacing: 10) {
                Circle().fill(src?.color ?? .secondary).frame(width: 7, height: 7).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayTitle(for: a))
                        .font(.system(size: store.listFontSize, weight: .semibold, design: .serif))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text("\(cluster.articles.count) kilder · \(cluster.articles.map(\.sourceName).joined(separator: ", "))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("\(cluster.articles.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    if let d = a.publishedAt {
                        Text(relativeTime(d))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(a.seen ? 0.6 : 1)
    }
}
#endif

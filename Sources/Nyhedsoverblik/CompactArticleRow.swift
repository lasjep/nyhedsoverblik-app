import SwiftUI

struct CompactArticleRow: View {
    let article: Article
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    var displayTitle: String { store.displayTitle(for: article) }

    var body: some View {
        Button {
            store.openArticle(article)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(sourceColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(size: store.listFontSize, weight: article.seen ? .regular : .medium,
                                      design: store.headlineFontDesign))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        if store.aiRewrite && displayTitle != article.title {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple.opacity(0.8))
                                .help("AI-omskrevet overskrift")
                        }
                        Text(article.sourceName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let date = article.publishedAt {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            Text(relativeTime(date))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.vertical, max(0.5, (store.listFontSize - 10) * 0.5))  // skalerer med fontstørrelse
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(article.seen ? 0.6 : 1.0)
        .background(isHovered ? Color.platformControlBackground : Color.clear)
        .onHover { isHovered = $0 }
    }
}

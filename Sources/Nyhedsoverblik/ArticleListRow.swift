import SwiftUI

struct ArticleListRow: View {
    let article: Article
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    var displayTitle: String { store.displayTitle(for: article) }

    private var fontSize: Double { store.listFontSize }

    // Luften skalerer med skriftstørrelsen — ved små fonte pakkes rækkerne tæt
    // (11pt → ~2pt luft, 14pt → ~6pt, 20pt → ~14pt)
    private var vPad: Double { max(2, (fontSize - 11) * 1.3 + 2) }
    private var barHeight: Double { fontSize * 2.2 }
    // Under 13pt: kilde og tid på ÉN linje så rækkehøjden styres af overskriften
    private var compactMeta: Bool { fontSize < 13 }

    var body: some View {
        Button {
            store.openArticle(article)
        } label: {
            HStack(alignment: .center, spacing: 0) {

                // Farve-bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(sourceColor.opacity(article.seen ? 0.25 : 1.0))
                    .frame(width: 3, height: barHeight)
                    .padding(.trailing, 12)

                // Overskrift — høj layoutPriority så den vinder pladsen
                Text(displayTitle)
                    .font(.system(size: store.listFontSize, weight: article.seen ? .regular : .semibold,
                                  design: store.headlineFontDesign))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                    .layoutPriority(1)          // ← giver teksten al tilgængelig bredde

                Spacer(minLength: 16)

                // Kilde + tid — én linje ved små fonte, ellers to
                metaView
                    .fixedSize(horizontal: true, vertical: false)  // højre kolonne: brug sin naturlige bredde
            }
            .padding(.vertical, vPad)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.platformControlBackground : Color.clear)
            .opacity(article.seen ? 0.6 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var metaView: some View {
        if compactMeta {
            HStack(spacing: 4) {
                Circle().fill(sourceColor).frame(width: 5, height: 5)
                Text(article.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let date = article.publishedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("· \(relativeTime(date))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(sourceColor).frame(width: 6, height: 6)
                    Text(article.sourceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    }
}

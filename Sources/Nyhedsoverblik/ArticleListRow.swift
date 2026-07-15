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

    // Luften skalerer KONTINUERLIGT med skriftstørrelsen — ingen tærskel-spring
    // (11pt → 1pt luft, 14pt → 2.5pt, 20pt → 5.5pt)
    private var vPad: Double { max(1, (fontSize - 11) * 0.5 + 1) }
    // Baren må ALDRIG være højere end én tekstlinje — ellers låser den rækkehøjden
    private var barHeight: Double { fontSize * 1.3 }

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

                // Kilde + tid på én linje
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

    // Altid ÉN linje — to caption-linjer (~26pt) ville låse rækkehøjden
    // uanset hvor lille overskriften er
    private var metaView: some View {
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
    }
}

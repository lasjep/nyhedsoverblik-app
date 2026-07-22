import SwiftUI

struct ArticleListRow: View {
    let article: Article
    var showThumbnail = false   // Liste-visning: lille billede/placeholder foran
    var sourceCount: Int = 1    // >1: "N kilder"-badge (cluster repræsenteret som række)
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    var displayTitle: String { store.displayTitle(for: article) }

    private var fontSize: Double { store.listFontSize }

    // Luften skalerer KONTINUERLIGT med skriftstørrelsen — ingen tærskel-spring
    private var vPad: Double { max(1, (fontSize - 11) * 0.5 + 1) }
    // Baren må ALDRIG være højere end én tekstlinje — ellers låser den rækkehøjden
    private var barHeight: Double { fontSize * 1.3 }
    private var thumbHeight: Double { fontSize * 3.0 }

    var body: some View {
        Button {
            store.openArticle(article)
        } label: {
            HStack(alignment: .center, spacing: 0) {

                // Farve-bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(sourceColor.opacity(article.seen ? 0.25 : 1.0))
                    .frame(width: 3, height: barHeight)
                    .padding(.trailing, showThumbnail ? 10 : 12)

                // Thumbnail (kun liste-visning) — billede eller ensartet placeholder,
                // så ALLE rækker har samme layout uanset om artiklen har et billede
                if showThumbnail {
                    thumbnail
                        .frame(width: thumbHeight * (16.0/9.0), height: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 11)
                }

                // Overskrift — høj layoutPriority så den vinder pladsen
                Text(displayTitle)
                    .font(.system(size: fontSize, weight: article.seen ? .regular : .semibold,
                                  design: store.headlineFontDesign))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                if sourceCount > 1 {
                    Text("\(sourceCount) kilder")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .padding(.trailing, 8)
                }

                // Kilde + tid på én linje
                metaView
                    .fixedSize(horizontal: true, vertical: false)
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
    private var thumbnail: some View {
        if let url = article.thumbnailURL {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    thumbPlaceholder
                }
            }
        } else {
            thumbPlaceholder
        }
    }

    private var thumbPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [sourceColor.opacity(0.30), sourceColor.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "newspaper")
                .font(.system(size: fontSize * 0.9))
                .foregroundStyle(sourceColor.opacity(0.45))
        }
    }

    // Altid ÉN linje — to caption-linjer ville låse rækkehøjden
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

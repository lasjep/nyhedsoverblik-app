import SwiftUI

struct CompactArticleRow: View {
    let article: Article
    var sourceCount: Int = 1
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    var displayTitle: String { store.displayTitle(for: article) }

    var body: some View {
        // STRENGT én linje: prik · overskrift · kilde · tid — alt vandret,
        // titel afkortes, ingen billeder. Maksimal informationstæthed og
        // tydeligt forskellig fra liste-visningen (som er 2-linjet med billede)
        Button {
            store.openArticle(article)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(sourceColor.opacity(article.seen ? 0.3 : 1))
                    .frame(width: 6, height: 6)

                Text(displayTitle)
                    .font(.system(size: store.listFontSize, weight: article.seen ? .regular : .medium,
                                  design: store.headlineFontDesign))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                    .layoutPriority(1)

                if store.aiRewrite && displayTitle != article.title {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple.opacity(0.7))
                }

                Spacer(minLength: 8)

                if sourceCount > 1 {
                    Text("\(sourceCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Text(article.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if let date = article.publishedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("· \(relativeTime(date))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
            }
            .padding(.vertical, max(1, (store.listFontSize - 11) * 0.35 + 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(article.seen ? 0.6 : 1.0)
        .background(isHovered ? Color.platformControlBackground : Color.clear)
        .onHover { isHovered = $0 }
    }
}

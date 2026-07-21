import SwiftUI

struct ArticleCard: View {
    let article: Article
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    // Fast kortstørrelse baseret på tile-bredde
    private var imageHeight: CGFloat { store.gridMinWidth * (9.0 / 16.0) }
    private var hasThumb: Bool { store.showThumbnails && article.thumbnailURL != nil }

    var body: some View {
        Button {
            store.openArticle(article)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // Kortet fylder ALTID hele sit slot i grid'et (NonLazyVGrid bestemmer
    // størrelsen) — billedområdet viser billede eller gradient, aldrig et hul
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasThumb {
                thumbnailArea
                bodySection
            } else {
                heroTextSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(article.seen
            ? Color.platformWindowBackground
            : Color.platformControlBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.platformSeparator, lineWidth: 1)
        )
        .opacity(article.seen ? 0.6 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.14 : 0.05),
                radius: isHovered ? 8 : 3, y: isHovered ? 3 : 1)
        .zIndex(isHovered ? 1 : 0)
    }

    // Diskret flade i kildens farve — vises mens billedet henter, hvis
    // hentningen fejler, og som baggrund for tekst-kort
    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [sourceColor.opacity(0.28), sourceColor.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "newspaper")
                .font(.system(size: 26))
                .foregroundStyle(sourceColor.opacity(0.35))
        }
    }

    private var thumbnailArea: some View {
        AsyncImage(url: article.thumbnailURL) { phase in
            if case .success(let img) = phase {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                gradientPlaceholder
            }
        }
        .frame(height: imageHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // Kort uden billede: stor rubrik på gradient — fylder hele kortet,
    // så grid-rytmen holdes og tekst-artikler får magasin-look
    private var heroTextSection: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [sourceColor.opacity(0.22), sourceColor.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.displayTitle(for: article))
                    .font(.system(size: 15, weight: .semibold, design: store.headlineFontDesign))
                    .lineLimit(7)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(article.seen ? .secondary : .primary)
                Spacer(minLength: 0)
                metaRow
            }
            .padding(10)
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.displayTitle(for: article))
                .font(.system(size: 13, weight: .semibold, design: store.headlineFontDesign))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .foregroundStyle(article.seen ? .secondary : .primary)

            Spacer(minLength: 0)

            metaRow
        }
        .padding(9)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            let displayed = store.displayTitle(for: article)
            Circle()
                .fill(sourceColor)
                .frame(width: 6, height: 6)
            Text(article.sourceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if store.aiRewrite && displayed != article.title {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple.opacity(0.8))
                    .help("AI-omskrevet overskrift")
            } else if store.aiRewrite && store.isRewriting {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 4)
            if let date = article.publishedAt {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(relativeTime(date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

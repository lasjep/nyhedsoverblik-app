import SwiftUI

// Magasin-kort: billedet fylder HELE kortet, titel + meta ligger altid
// nederst på en mørk scrim. Kort uden billede: samme tekstplacering på en
// diskret gradient i kildens farve — ingen placeholder-ikoner, ingen huller.
struct ArticleCard: View {
    let article: Article
    var sourceCount: Int = 1   // >1: artiklen dækker et cluster ("N kilder"-badge)
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false
    @State private var imageLoaded = false

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

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

    private var cardContent: some View {
        Group {
            if hasThumb {
                // Billed-kort: fuld-blødende billede, tekst på scrim nederst
                ZStack(alignment: .bottomLeading) {
                    background
                    textBlock
                }
            } else {
                // Tekst-kort (halv højde i grid'et): titel i top, meta i bund
                ZStack {
                    softGradient
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayTitle(for: article))
                            .font(.system(size: 13, weight: .semibold, design: store.headlineFontDesign))
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                        Spacer(minLength: 0)
                        metaRow
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(article.seen ? Color.platformWindowBackground : Color.platformControlBackground)
        .overlay(alignment: .topTrailing) {
            if sourceCount > 1 {
                Text("\(sourceCount) kilder")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
        }
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

    // Fuld-blødende billede — stille gradient mens det henter / hvis det fejler
    private var background: some View {
        GeometryReader { geo in
            AsyncImage(url: article.thumbnailURL) { phase in
                if case .success(let img) = phase {
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .onAppear { imageLoaded = true }
                } else {
                    softGradient
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var softGradient: some View {
        LinearGradient(colors: [sourceColor.opacity(0.18), sourceColor.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Titel + meta — ALTID nederst, samme placering på alle kort
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.displayTitle(for: article))
                .font(.system(size: 13, weight: .semibold, design: store.headlineFontDesign))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .foregroundStyle(titleColor)

            metaRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Scrim så hvid tekst kan læses ovenpå billeder — kun når et
            // billede faktisk er indlæst
            if imageLoaded {
                LinearGradient(colors: [.black.opacity(0.82), .black.opacity(0.45), .clear],
                               startPoint: .bottom, endPoint: .top)
                    .padding(.top, -24)   // blød overgang lidt op over teksten
            }
        }
    }

    private var titleColor: Color {
        if imageLoaded { return article.seen ? Color.white.opacity(0.65) : .white }
        return article.seen ? Color.secondary : Color.primary
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            let displayed = store.displayTitle(for: article)
            Circle()
                .fill(sourceColor)
                .frame(width: 6, height: 6)
            Text(article.sourceName)
                .font(.caption2)
                .foregroundStyle(imageLoaded ? Color.white.opacity(0.75) : Color.secondary)
                .lineLimit(1)
            if store.aiRewrite && displayed != article.title {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(imageLoaded ? Color.white.opacity(0.7) : Color.purple.opacity(0.8))
                    .help("AI-omskrevet overskrift")
            } else if store.aiRewrite && store.isRewriting {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 4)
            if let date = article.publishedAt {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(relativeTime(date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(imageLoaded ? Color.white.opacity(0.6) : Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

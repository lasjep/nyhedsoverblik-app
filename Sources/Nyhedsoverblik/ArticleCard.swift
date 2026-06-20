import SwiftUI

struct ArticleCard: View {
    let article: Article
    @EnvironmentObject var store: FeedStore
    @State private var isHovered = false
    @State private var imageState: ImageState = .loading

    enum ImageState { case loading, loaded, failed }

    var sourceColor: Color {
        store.sources.first(where: { $0.id == article.sourceID })?.color ?? .gray
    }

    // Fast kortstørrelse baseret på tile-bredde
    private var imageHeight: CGFloat { store.gridMinWidth * (9.0 / 16.0) }
    // Billedområde vises KUN når billedet rent faktisk er hentet —
    // loading-state vises ikke (undgår permanente grå firkanter).
    private var showsImageArea: Bool {
        store.showThumbnails && imageState == .loaded
    }
    private var hasImage: Bool { showsImageArea }

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
        VStack(alignment: .leading, spacing: 0) {
            if store.showThumbnails && article.thumbnailURL != nil {
                thumbnailArea
            }
            bodySection
        }
        .frame(height: showsImageArea ? imageHeight + 100 : 110,
               alignment: .top)
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

    @ViewBuilder
    private var thumbnailArea: some View {
        if store.showThumbnails, let thumbURL = article.thumbnailURL {
            AsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: imageHeight)
                        .clipped()
                        .onAppear { imageState = .loaded }
                case .failure:
                    Color.clear.frame(height: 0)
                        .onAppear { imageState = .failed }
                default:
                    Color.clear.frame(height: 0)
                }
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            let displayed = store.displayTitle(for: article)
            Text(displayed)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .lineLimit(hasImage ? 3 : 5)
                .multilineTextAlignment(.leading)
                .foregroundStyle(article.seen ? .secondary : .primary)

            if store.aiRewrite && displayed != article.title {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles").font(.system(size: 9))
                    Text("AI-omskrevet").font(.system(size: 10))
                }
                .foregroundStyle(.purple.opacity(0.7))
            } else if store.aiRewrite && store.isRewriting {
                HStack(spacing: 3) {
                    ProgressView().controlSize(.mini)
                    Text("Omskriver…").font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(sourceColor)
                    .frame(width: 6, height: 6)
                Text(article.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .padding(9)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

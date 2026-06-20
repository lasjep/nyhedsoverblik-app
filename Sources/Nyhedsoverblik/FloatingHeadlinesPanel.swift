#if os(macOS)
import SwiftUI
import AppKit

// MARK: – NSPanel subclass der flyder over alle andre vinduer

final class HeadlinesPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Nyhedsoverblik"
        level = .floating                       // altid over andre vinduer
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Placer øverst til højre
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 336
            let y = screen.visibleFrame.maxY - 504
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: – SwiftUI view inde i panelet

struct FloatingHeadlinesView: View {
    @EnvironmentObject var store: FeedStore
    @State private var hoveredID: String? = nil

    private var articles: [Article] {
        store.visibleArticles.prefix(20).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(articles) { article in
                        row(article)
                        Divider().opacity(0.4).padding(.leading, 28)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("N")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black, in: RoundedRectangle(cornerRadius: 4))
            Text("Nyhedsoverblik")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.8)
            }
            if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(relativeTime(updated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ article: Article) -> some View {
        let src = store.sources.first(where: { $0.id == article.sourceID })
        let color = src?.color ?? .gray

        return Button {
            store.openArticle(article)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        } label: {
            HStack(alignment: .center, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(article.seen ? 0.3 : 1.0))
                    .frame(width: 3, height: 28)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)

                Text(store.displayTitle(for: article))
                    .font(.system(size: 12, weight: article.seen ? .regular : .medium, design: .serif))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(article.seen ? Color.secondary : Color.primary)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if let date = article.publishedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(relativeTime(date))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .padding(.trailing, 8)
                    }
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hoveredID == article.id
                        ? Color.platformControlBackground.opacity(0.6)
                        : Color.clear)
        }
        .buttonStyle(.plain)
        .opacity(article.seen ? 0.55 : 1.0)
        .onHover { hoveredID = $0 ? article.id : nil }
    }
}

// MARK: – Controller der åbner/lukker panelet

@MainActor
final class FloatingPanelController: ObservableObject {
    private var panel: HeadlinesPanel?
    private var hostingView: NSHostingView<AnyView>?
    @Published var isVisible = false

    func toggle(store: FeedStore) {
        if isVisible {
            panel?.orderOut(nil)
            isVisible = false
        } else {
            show(store: store)
        }
    }

    func show(store: FeedStore) {
        if panel == nil {
            let p = HeadlinesPanel()
            let view = FloatingHeadlinesView()
                .environmentObject(store)
                .frame(minWidth: 280, minHeight: 300)
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = p.contentView!.bounds
            hosting.autoresizingMask = [.width, .height]
            p.contentView = hosting
            self.panel = p
            self.hostingView = hosting
        }
        panel?.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }
}
#endif  // os(macOS)

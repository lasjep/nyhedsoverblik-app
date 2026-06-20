import WidgetKit
import SwiftUI
import AppIntents

// MARK: – Shared data model

struct WidgetArticle: Codable, Identifiable {
    let id: String
    let title: String
    let sourceName: String
    let colorHex: String
    let publishedAt: Date?
}

struct WidgetData: Codable {
    let articles: [WidgetArticle]
    let backgroundColorHex: String?
    let accentColorHex: String
    let listFontSize: Double
}

// MARK: – Delt data-fil

private var sharedDataURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("nyhedsoverblik/widget_articles.json")
}

// MARK: – Timeline Entry

struct NyhedsEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let backgroundColorHex: String?
    let accentColorHex: String
    let listFontSize: Double
}

// MARK: – Provider

struct NyhedsProvider: TimelineProvider {
    private let placeholder = NyhedsEntry(
        date: Date(),
        articles: [
            WidgetArticle(id: "1", title: "Ny rekord: 50.000 danskere tilmeldt…", sourceName: "DR",        colorHex: "#E02020", publishedAt: Date()),
            WidgetArticle(id: "2", title: "Regeringen præsenterer ny klimaplan",   sourceName: "Politiken", colorHex: "#0066CC", publishedAt: Date()),
            WidgetArticle(id: "3", title: "Forsker: AI ændrer arbejdsmarkedet",    sourceName: "Berlingske",colorHex: "#003366", publishedAt: Date()),
        ],
        backgroundColorHex: nil,
        accentColorHex: "#007AFF",
        listFontSize: 13
    )

    func placeholder(in context: Context) -> NyhedsEntry { placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NyhedsEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NyhedsEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> NyhedsEntry {
        if let data = try? Data(contentsOf: sharedDataURL),
           let payload = try? JSONDecoder().decode(WidgetData.self, from: data) {
            return NyhedsEntry(date: Date(),
                               articles: payload.articles,
                               backgroundColorHex: payload.backgroundColorHex,
                               accentColorHex: payload.accentColorHex,
                               listFontSize: payload.listFontSize)
        }
        // Ældre format (kun array) — bagudkompatibilitet
        if let data = try? Data(contentsOf: sharedDataURL),
           let articles = try? JSONDecoder().decode([WidgetArticle].self, from: data) {
            return NyhedsEntry(date: Date(), articles: articles,
                               backgroundColorHex: nil, accentColorHex: "#007AFF", listFontSize: 13)
        }
        return NyhedsEntry(date: Date(), articles: [],
                           backgroundColorHex: nil, accentColorHex: "#007AFF", listFontSize: 13)
    }
}

// MARK: – Artikel-række

private struct ArticleRow: View {
    let article: WidgetArticle
    let fontSize: Double
    let lineLimit: Int

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: article.colorHex))
                .frame(width: 3, height: lineLimit == 1 ? 22 : 30)
            Text(article.title)
                .font(.system(size: fontSize, weight: .semibold, design: .serif))
                .lineLimit(lineLimit)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: – Kontrol-knapper via AppIntents

private struct WidgetControls: View {
    let accentHex: String

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: MarkAllReadIntent()) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text("RYD")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(hex: accentHex))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(hex: accentHex).opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Button(intent: DecreaseFontIntent()) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 16)
                }
                .buttonStyle(.plain)
                Button(intent: IncreaseFontIntent()) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
    }
}

// MARK: – Small Widget View (3 artikler)

struct SmallWidgetView: View {
    let entry: NyhedsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            ForEach(Array(entry.articles.prefix(3))) { article in
                ArticleRow(article: article, fontSize: max(10, entry.listFontSize - 2), lineLimit: 2)
                    .padding(.bottom, 4)
            }
            Spacer(minLength: 0)
            WidgetControls(accentHex: entry.accentColorHex)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            if let hex = entry.backgroundColorHex {
                Color(hex: hex)
            } else {
                Color.clear
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("N")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(hex: entry.accentColorHex), in: RoundedRectangle(cornerRadius: 4))
            Text("Nyheder")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: – Medium Widget View (5 artikler)

struct MediumWidgetView: View {
    let entry: NyhedsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text("N")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color(hex: entry.accentColorHex), in: RoundedRectangle(cornerRadius: 4))
                Text("Nyhedsoverblik")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let d = entry.articles.first?.publishedAt {
                    Text(d, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 6)

            ForEach(Array(entry.articles.prefix(5))) { article in
                ArticleRow(article: article, fontSize: entry.listFontSize, lineLimit: 1)
                    .padding(.bottom, 4)
            }

            Spacer(minLength: 0)
            WidgetControls(accentHex: entry.accentColorHex)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            if let hex = entry.backgroundColorHex {
                Color(hex: hex)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: – Entry View

struct NyhedsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: NyhedsProvider.Entry

    var body: some View {
        if entry.articles.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "newspaper").font(.title2).foregroundStyle(.secondary)
                Text("Åbn Nyhedsoverblik\nfor at se nyheder")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .containerBackground(.regularMaterial, for: .widget)
        } else if family == .systemSmall {
            SmallWidgetView(entry: entry)
        } else {
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: – Widget definition

@main
struct NyhedsoverblikWidget: Widget {
    let kind = "dk.nyhedsoverblik.app.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NyhedsProvider()) { entry in
            NyhedsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nyhedsoverblik")
        .description("De seneste danske nyheder fra dine valgte kilder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: – Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)         / 255
        self.init(red: r, green: g, blue: b)
    }
}

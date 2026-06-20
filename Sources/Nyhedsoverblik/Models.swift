import SwiftUI
import Foundation

enum FeedType: String, Codable, Sendable {
    case rss      // Standard RSS/Atom feed
    case scrape   // HTML scraping (fx MediaWatch)
}

struct FeedSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: String
    var additionalURLs: [String] = []   // ekstra feeds — hentes parallelt og merges
    let colorHex: String
    var filterCommercial: Bool = false
    var feedType: FeedType = .rss
    var isCustom: Bool = false    // brugertilføjet kilde

    var allURLs: [String] { [url] + additionalURLs }
    var color: Color { Color(hex: colorHex) ?? .gray }
}

// Bruges til JSON-persistering af custom kilder
struct CustomFeedSource: Codable, Identifiable {
    let id: String
    let name: String
    let url: String
    let colorHex: String
    var feedType: FeedType
}

struct Article: Identifiable, Hashable, Sendable {
    let id: String          // URL – bruges som unik nøgle
    let title: String
    let url: URL
    let sourceName: String
    let sourceID: String
    let publishedAt: Date?
    let thumbnailURL: URL?
    var tags: [String] = []   // article:tag / RSS <category> — bruges af filtre
    var seen: Bool
}

// MARK: – Feed-elementer (enkelt artikel eller cluster af samme historie)

struct StoryCluster: Identifiable, Hashable {
    let id: String
    let articles: [Article]          // sorteret nyeste først
    var thumbnailURL: URL? { articles.first(where: { $0.thumbnailURL != nil })?.thumbnailURL }
}

enum FeedItem: Identifiable, Hashable {
    case single(Article)
    case cluster(StoryCluster)

    var id: String {
        switch self {
        case .single(let a):  return a.id
        case .cluster(let c): return c.id
        }
    }
}

// MARK: – Layout-environment (iPad portrait bruger eget visningsbånd)

private struct PortraitLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isPortraitLayout: Bool {
        get { self[PortraitLayoutKey.self] }
        set { self[PortraitLayoutKey.self] = newValue }
    }
}

// MARK: – Delte hjælpere

/// Grov relativ tid — opdateres pr. minut, viser aldrig sekunder
func relativeTime(_ date: Date) -> String {
    let s = -date.timeIntervalSinceNow
    if s < 90        { return "Lige nu" }
    if s < 3600      { return "\(Int(s / 60)) min." }
    if s < 86400     { return "\(Int(s / 3600)) t." }
    return "\(Int(s / 86400)) d."
}

/// Fjerner tracking-parametre (utm_*, fbclid, …) så samme artikel ikke optræder
/// som to forskellige, når feedet skifter kampagne-tags på URL'en.
func normalizedArticleID(_ link: String) -> String {
    guard var comps = URLComponents(string: link) else { return link }
    comps.fragment = nil
    let banned: Set<String> = ["fbclid", "gclid", "ref", "cmpid", "ns_campaign", "ns_mchannel", "icid",
                               "fp-exp", "fp-alg"]   // fp-*: JP's forside-eksperiment-params
    if let items = comps.queryItems {
        let kept = items.filter {
            let n = $0.name.lowercased()
            return !n.hasPrefix("utm_") && !banned.contains(n)
        }
        comps.queryItems = kept.isEmpty ? nil : kept
    }
    return comps.string ?? link
}

/// Stabil hash (djb2) — Swifts hashValue er randomiseret per kørsel og kan ikke
/// bruges til persistente ID'er.
func stableHash(_ s: String) -> String {
    var h: UInt64 = 5381
    for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
    return String(h, radix: 36)
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

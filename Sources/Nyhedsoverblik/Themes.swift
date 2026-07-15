import SwiftUI

// MARK: – Temaer (læsekoncept: artikler grupperet efter emne)

enum NewsTheme: String, CaseIterable, Identifiable {
    case indland
    case udland
    case politik
    case tech
    case andet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indland: return "Indland"
        case .udland:  return "Udland"
        case .politik: return "Politik"
        case .tech:    return "Tech"
        case .andet:   return "Andet"
        }
    }

    var icon: String {
        switch self {
        case .indland: return "house"
        case .udland:  return "globe.europe.africa"
        case .politik: return "building.columns"
        case .tech:    return "cpu"
        case .andet:   return "tray"
        }
    }
}

// Kilder hvor hele kilden entydigt hører til ét tema
private let sourceThemes: [String: NewsTheme] = [
    "engadget":     .tech,
    "macrumors":    .tech,
    "9to5mac":      .tech,
    "verge":        .tech,
    "ars":          .tech,
    "techcrunch":   .tech,
    "ing":          .tech,
    "flatpanels":   .tech,
    "recordere":    .tech,
    "digitaltv":    .tech,
    "tvtechnology": .tech,
    "nyt":          .udland,   // path-tjek fanger /technology/ m.m. først
]

// URL-sti-segmenter per tema — mest specifikke signal, tjekkes først
private let pathThemes: [(NewsTheme, [String])] = [
    (.politik, ["/politik"]),
    (.tech,    ["/tech", "/teknologi", "/technology", "/personaltech", "/digital", "/gadget"]),
    (.udland,  ["/udland", "/international", "/verden", "/world", "/europe", "/usa",
                "/us-news", "/global", "/africa", "/asia", "/middleeast", "/americas",
                "/ukraine", "/mellemoesten"]),
    (.indland, ["/indland", "/danmark", "/samfund", "/krimi", "/112", "/lokal",
                "/koebenhavn", "/aarhus", "/odense", "/aalborg"]),
]

// Tag-nøgleord per tema (article:tag / RSS <category>)
private let tagThemes: [(NewsTheme, [String])] = [
    (.politik, ["politik", "folketinget", "regeringen", "valg"]),
    (.tech,    ["tech", "teknologi", "technology", "it", "software", "hardware", "ai"]),
    (.udland,  ["udland", "international", "verden", "world", "usa", "europa", "ukraine", "mellemøsten"]),
    (.indland, ["indland", "danmark", "krimi", "samfund"]),
]

/// Klassificerer en artikel: URL-sti → tags → kildestandard → andet.
func classifyTheme(url: String, sourceID: String, tags: [String] = []) -> NewsTheme {
    // 1. URL-sti — sektionen er redaktionens egen kategorisering
    if let path = URL(string: url)?.path.lowercased() {
        for (theme, segments) in pathThemes {
            if segments.contains(where: { path.contains($0) }) { return theme }
        }
    }
    // 2. Tags — match på hele ord så "it" ikke rammer "italien"
    if !tags.isEmpty {
        for (theme, words) in tagThemes {
            for tag in tags {
                let tagWords = tag.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                if tagWords.contains(where: { words.contains($0) }) { return theme }
            }
        }
    }
    // 3. Kildestandard (rene tech-/udlandskilder)
    if let theme = sourceThemes[sourceID] { return theme }
    return .andet
}

import SwiftUI

// MARK: – Temaer (læsekoncept: artikler grupperet efter emne)

enum NewsTheme: String, CaseIterable, Identifiable {
    case indland
    case udland
    case politik
    case tech

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indland: return "Indland"
        case .udland:  return "Udland"
        case .politik: return "Politik"
        case .tech:    return "Tech"
        }
    }

    var icon: String {
        switch self {
        case .indland: return "house"
        case .udland:  return "globe.europe.africa"
        case .politik: return "building.columns"
        case .tech:    return "cpu"
        }
    }

    // Karakterfarve pr. tema — bruges til headers og svag baggrundstone
    var tint: Color {
        switch self {
        case .indland: return Color(red: 0.20, green: 0.55, blue: 0.90)  // blå
        case .udland:  return Color(red: 0.15, green: 0.65, blue: 0.55)  // teal
        case .politik: return Color(red: 0.78, green: 0.35, blue: 0.30)  // teglrød
        case .tech:    return Color(red: 0.55, green: 0.40, blue: 0.85)  // lilla
        }
    }
}

/// Ét temas indhold: den flade artikelliste (til optælling) og den
/// clustrede udgave (til visning — samme historie på tværs af kilder samles)
struct ThemedGroup: Identifiable {
    let theme: NewsTheme
    let articles: [Article]
    let items: [FeedItem]
    var id: NewsTheme { theme }
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

/// Klassificerer en artikel: AI-tema → URL-sti → tags → kildestandard → indland.
/// `aiTheme` er modellens vurdering af selve overskriften og går forud for alt,
/// fordi den fanger tilfælde hvor URL/tags er intetsigende (fx EB's flade stier).
/// Der findes kun fire temaer; uden andet signal antages dansk almenstof (indland).
func classifyTheme(url: String, sourceID: String, tags: [String] = [], aiTheme: NewsTheme? = nil) -> NewsTheme {
    // 0. AI-tema — læser overskriftens faktiske indhold
    if let aiTheme { return aiTheme }
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
    // 4. Intet signal → dansk almenstof
    return .indland
}

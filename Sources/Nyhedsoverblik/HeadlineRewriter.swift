import Foundation

enum HeadlineRewriter {
    struct Result: Sendable {
        let rewritten: String
        let isSport: Bool
    }

    /// Kalder Claude API og returnerer en dict original → (omskrevet, sport-flag).
    /// Returnerer nil ved netværksfejl eller ugyldig nøgle.
    static func rewrite(_ titles: [String], apiKey: String) async -> [String: Result]? {
        guard !titles.isEmpty, !apiKey.isEmpty else { return nil }

        let list = titles.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let systemPrompt = """
        Du er en redaktør der omskriver sensationelle og clickbait-agtige nyhedsoverskrifter \
        til neutrale, informative sætninger. Bevar fakta og kildeangivelser. \
        Fjern overdrivelser, udråbstegn, STORE BOGSTAVER og manipulative formuleringer. \
        VIGTIGT: Bevar hver overskrifts originale sprog — danske overskrifter forbliver på dansk, \
        engelske på engelsk. Oversæt ALDRIG. Listen kan indeholde blandede sprog; \
        vurder sproget for hver enkelt overskrift, ikke for listen som helhed. \
        Du markerer desuden sportsnyheder: sæt "s":true hvis overskriften handler om sport \
        (fodbold, cykling, håndbold, tennis, motorsport, atletik, OL, kampe, resultater, \
        transfers, trænere eller navngivne sportsudøvere som fx Pogacar eller Mbappé) — \
        ellers "s":false. Erhvervs-/tech-nyheder OM sportsbranchen (tv-rettigheder, \
        streamingtjenester, sponsorater) er IKKE sport. \
        Svar KUN med JSON-objektet, ingen forklaringer.
        """

        let userPrompt = """
        Omskriv disse overskrifter. Svar med JSON:
        {"rewrites":[{"i":1,"r":"omskrevet overskrift","s":false},{"i":2,"r":"...","s":true},...]}

        Overskrifter:
        \(list)
        """

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt]]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = bodyData

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        // Parse Claude response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else { return nil }

        // Udtræk JSON fra svaret (kan have ```json ... ``` wrapper)
        let clean = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rewriteData = clean.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: rewriteData) as? [String: Any],
              let rewrites = parsed["rewrites"] as? [[String: Any]] else { return nil }

        var result: [String: Result] = [:]
        for entry in rewrites {
            guard let idx = entry["i"] as? Int,
                  let rewritten = entry["r"] as? String,
                  idx >= 1, idx <= titles.count else { continue }
            result[titles[idx - 1]] = Result(rewritten: rewritten,
                                             isSport: entry["s"] as? Bool ?? false)
        }
        return result
    }
}

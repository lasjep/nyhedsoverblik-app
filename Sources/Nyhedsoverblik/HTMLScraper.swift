import Foundation

// MARK: – HTML Scraper til sider uden RSS

enum HTMLScraper {

    // Scraper en side og returnerer articles ved at:
    // 1. Finde artikel-links via kendte URL-mønstre
    // 2. Hente de 12 nyeste artiklers <title>/<og:title> parallelt
    static func scrape(source: FeedSource) async -> [Article] {
        guard let pageURL = URL(string: source.url) else { return [] }
        let baseURL = "\(pageURL.scheme ?? "https")://\(pageURL.host ?? "")"

        // Hent listesiden
        var req = URLRequest(url: pageURL, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return [] }

        // Find unikke artikel-links
        let links = extractArticleLinks(from: html, baseURL: baseURL, sourceURL: source.url)
        guard !links.isEmpty else { return [] }

        // Hent titler parallelt — forsider som jp.dk har 70+ artikler; kun ~8KB
        // hentes pr. artikel, og URLSession begrænser selv samtidige forbindelser
        let topLinks = Array(links.prefix(80))
        let articles = await withTaskGroup(of: Article?.self) { group in
            for link in topLinks {
                group.addTask {
                    await fetchArticleMetadata(url: link, source: source)
                }
            }
            var result: [Article] = []
            for await art in group {
                if let a = art { result.append(a) }
            }
            return result
        }

        // Alders-værn: service-/arkivsider der slipper gennem link-mønstrene har
        // også og:-metadata og ligner artikler — men er typisk måneder/år gamle.
        // Forsiden er til aktuelt stof; behold kun det seneste (udateret = behold,
        // datoen kan bare mangle i de første 8KB)
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        return articles
            .filter { ($0.publishedAt ?? Date()) > cutoff }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    // MARK: – Link-ekstraktion

    private static func extractArticleLinks(from html: String, baseURL: String, sourceURL: String) -> [URL] {
        // Mønstre der typisk identificerer artikel-links (ikke nav/footer/etc.)
        let articlePatterns = [
            #"href="(/[^"]*?/ECE\d+[^"]*?)""#,               // Escenic-style (JP, Politiken m.fl.)
            #"href="(/[^"]*?/article\d+[^"]*?)""#,           // MediaWatch m.fl.
            #"href="(/[^"]*?-\d{6,}[^"]*?)""#,               // slug med ID
            #"href="(/(?:artikel|article|nyheder|news)/[^"]+?)""#, // /artikel/ /news/ paths
            #"href="(https?://[^"]*?/\d{4}-\d{2}-\d{2}-[^"]+?)""#, // dato-slug (TV2 m.fl.)
            // /sektion/lang-slug uden ID (Berlingske m.fl.) — kræver 4+ ord i
            // slug'en så nav-/sektionslinks ikke fanges; sidste udvej, prøves
            // kun hvis ID-mønstrene ovenfor ikke gav nok
            #"href="(/[a-zæøå-]+/(?:[a-zæøå0-9]+-){3,}[a-zæøå0-9]+/?)""#,
            // /artNNNNN/ (Politiken efter Escenic-exit)
            #"href="((?:https?://[^"]*)?/(?:[^"]*/)?art\d+/[^"]*?)""#,
            // /slug/1234567 — numerisk ID til sidst (Ekstra Bladet)
            #"href="((?:https?://[^"]*)?/[^"]+/\d{7,}/?)""#,
        ]

        var seen = Set<String>()
        var urls: [URL] = []

        for pattern in articlePatterns {
            let matches = html.matches(pattern: pattern, group: 1)
            for path in matches {
                // Skær query/fragment væk — forside-links har ofte tracking-params
                // (JP: ?fp-exp=...&fp-alg=...) der skifter ved hver visning
                let cleanPath = path.components(separatedBy: "?")[0]
                    .components(separatedBy: "#")[0]
                let full = cleanPath.hasPrefix("http") ? cleanPath : baseURL + cleanPath
                // Filtrer navigation, tags, kategorier og service-sider fra
                // (/om/ og /velkommen/: JP's kontakt-/pressesider bruger også ECE-URL'er)
                guard !full.contains("/tag/"), !full.contains("/kategori/"),
                      !full.contains("/search"), !full.contains("/forfatter"),
                      !full.contains("/om/"), !full.contains("/velkommen/"),
                      !full.contains("/om_"),       // Politikens servicesider (/om_politiken/)
                      !full.contains("/services/"), // EB's tip-/kundeservicesider
                      !full.contains("/reel/"),     // TV2's lodrette video-shorts — ikke artikler
                      !seen.contains(full) else { continue }
                // Absolutte links skal blive på kildens eget domæne — forsider
                // krydslinker til søstermedier (Politiken ↔ EB i JP/Politikens Hus),
                // og de artikler ville ellers få forkert kilde-etiket.
                // Sammenlign registrerbart domæne (tv2.dk ≠ nyheder.tv2.dk er OK).
                if full.hasPrefix("http"),
                   let linkHost = URL(string: full)?.host,
                   let sourceHost = URL(string: sourceURL)?.host,
                   rootDomain(linkHost) != rootDomain(sourceHost) { continue }
                seen.insert(full)
                if let url = URL(string: full) { urls.append(url) }
            }
            if urls.count >= 80 { break }
        }
        return urls
    }

    /// "nyheder.tv2.dk" → "tv2.dk" — registrerbart domæne (sidste to labels)
    private static func rootDomain(_ host: String) -> String {
        host.components(separatedBy: ".").suffix(2).joined(separator: ".")
    }

    // MARK: – Metadata-hentning per artikel

    private static func fetchArticleMetadata(url: URL, source: FeedSource) async -> Article? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        // Vi behøver kun head + første ~8KB for at finde title/og:title
        req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        // Prioritér: og:title > <title>
        let og = html.firstMatch(pattern: #"og:title[^>]*content="([^"]{5,200})""#, group: 1)
            ?? html.firstMatch(pattern: #"content="([^"]{5,200})"[^>]*og:title"#, group: 1)
        let titleTag = html.firstMatch(pattern: #"<title>([^<]{5,300})</title>"#, group: 1)

        let title: String
        switch (og, titleTag) {
        case let (o?, t?):
            // Nogle CMS'er (Politiken) afkorter og:title til 60 tegn midt i et ord.
            // Er <title> længere og deler prefix med og:title, er den den fulde titel.
            if t.count > o.count, t.commonPrefix(with: o).count >= o.count - 2 {
                title = t
            } else {
                title = o
            }
        case let (o?, nil): title = o
        case let (nil, t?): title = t
        default: return nil
        }

        var cleanTitle = title
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
            .htmlDecoded()

        // <title>-fallback indeholder ofte " - Sitenavn" til sidst (når og:title
        // ligger uden for det hentede byte-range, fx TV2's ~180KB <head>).
        // Skær det fra hvis det matcher kildens navn.
        for separator in [" - ", " | ", " — ", " – "] {
            if cleanTitle.lowercased().hasSuffix("\(separator)\(source.name)".lowercased()) {
                cleanTitle = String(cleanTitle.dropLast(separator.count + source.name.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Kig efter publiceringsdato — falder tilbage til dato i URL'en
        // (TV2's <head> er ~180KB, så og:-metadata ligger uden for byte-range;
        // uden dato ville artiklerne sortere som ældst og klumpe i bunden)
        let pubDate = extractDate(from: html) ?? dateFromURL(url)

        // Thumbnail
        let thumbURL: URL? = html
            .firstMatch(pattern: #"og:image[^>]*content="([^"]+)""#, group: 1)
            .flatMap { URL(string: $0) }

        // Emne-tags (article:tag) — bruges af sportsfilteret
        let tags = html.matches(pattern: #"article:tag"[^>]*content="([^"]{1,80})""#, group: 1)
            .map { $0.htmlDecoded() }

        return Article(
            id: normalizedArticleID(url.absoluteString),
            title: cleanTitle,
            url: url,
            sourceName: source.name,
            sourceID: source.id,
            publishedAt: pubDate,
            thumbnailURL: thumbURL,
            tags: tags,
            seen: false
        )
    }

    /// Dato-slug i URL-stien (fx tv2.dk/nyheder/2026-07-14-overskrift) → kl. 12
    /// lokal tid, så dags-niveau-sortering virker selvom klokkeslæt er ukendt
    private static func dateFromURL(_ url: URL) -> Date? {
        guard let m = url.path.firstMatch(pattern: #"/(\d{4}-\d{2}-\d{2})-"#, group: 1) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        guard let day = df.date(from: m) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: day)
    }

    private static func extractDate(from html: String) -> Date? {
        let patterns = [
            #"article:published_time"[^>]*content="([^"]+)""#,   // OpenGraph (JP m.fl.)
            #""datePublished"\s*:\s*"([^"]+)""#,
            #"publishedAt[^"]*"([^"]+T[^"]+)""#,
            #"<time[^>]*datetime="([^"]+)""#,
        ]
        let formats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                       "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd"]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")

        for pattern in patterns {
            if let str = html.firstMatch(pattern: pattern, group: 1) {
                for fmt in formats {
                    df.dateFormat = fmt
                    if let d = df.date(from: str) { return d }
                }
            }
        }
        return nil
    }
}

// MARK: – Auto-discover RSS fra en hjemmeside

enum RSSDiscovery {
    struct DiscoveredFeed {
        let feedURL: URL
        let title: String
        let sampleArticles: [Article]
    }

    struct DiscoveryError: Error { let message: String }

    // Givet en URL (RSS direkte eller hjemmeside): returner en FeedSource-preview
    static func discover(urlString: String) async -> Result<DiscoveredFeed, DiscoveryError> {
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.hasPrefix("http") { cleanURL = "https://" + cleanURL }
        guard let url = URL(string: cleanURL) else { return .failure(DiscoveryError(message: "Ugyldig URL")) }

        // 1. Prøv direkte som RSS
        if let feed = await tryRSS(url: url) { return .success(feed) }

        // 2. Hent HTML og kig efter autodiscovery
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return .failure(DiscoveryError(message: "Kunne ikke hente siden")) }

        // Find <link rel="alternate" type="application/rss+xml" href="...">
        let base = "\(url.scheme ?? "https")://\(url.host ?? "")"
        let rssLinks = extractRSSLinks(from: html, baseURL: base)

        for rssURL in rssLinks {
            if let feed = await tryRSS(url: rssURL) { return .success(feed) }
        }

        // 3. Prøv kendte RSS-URL-mønstre baseret på domænet
        let guesses = rssGuesses(for: url)
        for guess in guesses {
            if let feed = await tryRSS(url: guess) { return .success(feed) }
        }

        // 4. Ingen RSS fundet → foreslå scraping
        return .failure(DiscoveryError(message: "Ingen RSS-feed fundet. Siden kan tilføjes som scrape-kilde (langsommere)."))
    }

    private static func tryRSS(url: URL) async -> DiscoveredFeed? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }

        // Tjek at det ligner XML
        let ct = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "content-type") ?? ""
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
        guard ct.contains("xml") || ct.contains("rss") || ct.contains("atom")
                || preview.contains("<rss") || preview.contains("<feed")
                || preview.contains("<?xml") else { return nil }

        // Parse feed
        let articles = RSSParser().parse(data: data)
        guard !articles.isEmpty else { return nil }

        let title = articles.first.map { _ in
            // Prøv at finde feed title fra XML
            preview.firstMatch(pattern: #"<title>([^<]{2,80})</title>"#, group: 1) ?? url.host ?? url.absoluteString
        } ?? url.host ?? ""

        let sampleArticles = articles.prefix(3).compactMap { p -> Article? in
            guard let link = URL(string: p.link) else { return nil }
            return Article(id: p.link, title: p.title, url: link,
                           sourceName: title, sourceID: "preview",
                           publishedAt: nil, thumbnailURL: nil, seen: false)
        }
        return DiscoveredFeed(feedURL: url, title: title, sampleArticles: sampleArticles)
    }

    private static func extractRSSLinks(from html: String, baseURL: String) -> [URL] {
        // <link rel="alternate" type="application/rss+xml" href="...">
        let pattern = #"<link[^>]+(?:rss\+xml|atom\+xml)[^>]+href="([^"]+)""#
        let pattern2 = #"<link[^>]+href="([^"]+)"[^>]+(?:rss\+xml|atom\+xml)"#
        var urls: [URL] = []
        for p in [pattern, pattern2] {
            for href in html.matches(pattern: p, group: 1) {
                let full = href.hasPrefix("http") ? href : baseURL + href
                if let u = URL(string: full) { urls.append(u) }
            }
        }
        return urls
    }

    private static func rssGuesses(for url: URL) -> [URL] {
        let base = "\(url.scheme ?? "https")://\(url.host ?? "")"
        let paths = ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml",
                     "/feed/rss", "/rss/feed", "/news/feed", "/blog/feed"]
        return paths.compactMap { URL(string: base + $0) }
    }
}

// MARK: – String helpers

private extension String {
    func matches(pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > group else { return nil }
            let r = match.range(at: group)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }

    func firstMatch(pattern: String, group: Int) -> String? {
        matches(pattern: pattern, group: group).first
    }

    func htmlDecoded() -> String {
        var s = self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&aelig;", with: "æ")
            .replacingOccurrences(of: "&oslash;", with: "ø")
            .replacingOccurrences(of: "&aring;", with: "å")
            .replacingOccurrences(of: "&AElig;", with: "Æ")
            .replacingOccurrences(of: "&Oslash;", with: "Ø")
            .replacingOccurrences(of: "&Aring;", with: "Å")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Numeriske HTML-entities &#NNN;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = s as NSString
            for match in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                let numStr = ns.substring(with: match.range(at: 1))
                if let code = UInt32(numStr), let scalar = Unicode.Scalar(code) {
                    let replacement = String(Character(scalar))
                    if let r = Range(match.range, in: s) {
                        s.replaceSubrange(r, with: replacement)
                    }
                }
            }
        }
        return s
    }
}

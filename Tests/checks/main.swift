import Foundation

// Letvægts test-runner — kompileres sammen med app-kilderne via run_checks.sh
// (Command Line Tools mangler XCTest/Testing; dette kræver kun Foundation)

var passed = 0
var failed = 0

func check(_ condition: Bool, _ name: String,
           file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  ✓ \(name)")
    } else {
        failed += 1
        print("  ✗ FEJL: \(name)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func suite(_ name: String) { print("\n— \(name)") }

func testArticle(_ id: String, _ title: String) -> Article {
    Article(id: id, title: title, url: URL(string: "https://x.dk/\(id)")!,
            sourceName: "Test", sourceID: "test", publishedAt: nil,
            thumbnailURL: nil, seen: false)
}

// MARK: – Filtre

suite("Sportsfilter: ordgrænser (regression)")
check(!isSport(title: "Apple improves recycling program for old iPhones",
               url: "https://example.com/tech/apple"),
      "'recycling' må ikke matche 'cykling'")
check(!isSport(title: "New data transfer speeds in USB4",
               url: "https://example.com/tech/usb"),
      "'data transfer' må ikke matche som sport")
check(!isSport(title: "Transportminister vil have flere elbiler",
               url: "https://example.com/politik/x"),
      "'Transportminister' må ikke matche")

suite("Sportsfilter: fanger stadig sport")
check(isSport(title: "Superliga: FCK vinder over Brøndby", url: "https://example.com/n/x"),
      "Superliga fanges")
check(isSport(title: "Dansk cykling får ny landstræner", url: "https://example.com/n/y"),
      "cykling som selvstændigt ord fanges")
check(isSport(title: "VM i håndbold starter i dag", url: "https://example.com/n/z"),
      "'VM i' fanges")
check(isSport(title: "Stor sejr til landsholdet", url: "https://example.com/n/w"),
      "landsholdet fanges")
check(isSport(title: "Helt almindelig overskrift", url: "https://eb.dk/sport/fodbold/a123"),
      "URL-sti /sport/ fanges")

suite("Sportsfilter: tags (regression — JP-podcasts)")
check(isSport(title: "Farvel, Paddy, bye bye, Beijmo!",
              url: "https://jp.dk/podcast/hvidroeg/ECE19352249/farvel-paddy-bye-bye-beijmo/",
              tags: ["Superligaen", "AGF"]),
      "'Superligaen'-tag fanges (prefix-match)")
check(isSport(title: "»Stop med at blande jer i Eriksens karriere!«",
              url: "https://jp.dk/podcast/hvisduvilvidemere/ECE19374719/x/",
              tags: ["Fodbold", "Herrelandsholdet i fodbold"]),
      "'Fodbold'-tag fanges")
check(!isSport(title: "Ny regering på vej",
               url: "https://jp.dk/politik/ECE123/x/",
               tags: ["Politik", "Christiansborg"]),
      "politik-tags fanges ikke")
check(!isSport(title: "Genbrug i fokus",
               url: "https://x.dk/n/1",
               tags: ["Recycling", "Transport"]),
      "'Recycling'/'Transport'-tags fanges ikke (ordgrænser)")

suite("RSS-kategorier som tags")
let rssCat = """
<?xml version="1.0"?>
<rss version="2.0"><channel><item>
<title>Stor kamp i aften</title>
<link>https://x.dk/a9</link>
<category>Sport</category>
<category>Fodbold</category>
</item></channel></rss>
"""
let parsedCat = RSSParser().parse(data: Data(rssCat.utf8))
check(parsedCat.first?.tags == ["Sport", "Fodbold"], "RSS <category> samles op")

suite("Clickbait & kommercielt")
check(clickbaitScore(title: "CHOK: Du vil ikke tro hvad der skete!!") >= 5,
      "tydelig clickbait scorer >= 5")
check(clickbaitScore(title: "Regeringen fremlægger ny finanslov") < 5,
      "neutral overskrift scorer < 5")
check(isCommercial(title: "Best deals on MacBooks this Prime Day"),
      "deal-overskrift fanges")
check(!isCommercial(title: "Apple announces new MacBook Pro"),
      "produktnyhed fanges ikke")

// MARK: – Hjælpere

suite("URL-normalisering")
check(normalizedArticleID("https://x.dk/artikel?utm_source=rss&utm_medium=feed") == "https://x.dk/artikel",
      "utm_* fjernes")
check(normalizedArticleID("https://x.dk/artikel?id=42&utm_source=rss") == "https://x.dk/artikel?id=42",
      "rigtige parametre bevares")
check(normalizedArticleID("https://x.dk/artikel?fbclid=abc123") == "https://x.dk/artikel",
      "fbclid fjernes")

suite("stableHash")
check(stableHash("https://mediawatch.dk/latest") == stableHash("https://mediawatch.dk/latest"),
      "samme input → samme hash")
check(stableHash("https://a.dk/feed1") != stableHash("https://a.dk/feed2"),
      "forskelligt input → forskellig hash")

suite("relativeTime")
check(relativeTime(Date()) == "Lige nu", "nu → 'Lige nu'")
check(relativeTime(Date(timeIntervalSinceNow: -300)) == "5 min.", "5 minutter")
check(relativeTime(Date(timeIntervalSinceNow: -7200)) == "2 t.", "2 timer")
check(relativeTime(Date(timeIntervalSinceNow: -172800)) == "2 d.", "2 dage")

// MARK: – RSS-parsing

suite("RSS 2.0-parsing")
let rss2 = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>Test Feed</title>
    <item>
      <title>Første artikel</title>
      <link>https://x.dk/a1</link>
      <pubDate>Tue, 10 Jun 2026 08:00:00 +0200</pubDate>
      <media:thumbnail url="https://x.dk/img1.jpg"/>
    </item>
    <item>
      <title>Anden artikel</title>
      <link>https://x.dk/a2</link>
    </item>
  </channel>
</rss>
"""
let parsedRSS = RSSParser().parse(data: Data(rss2.utf8))
check(parsedRSS.count == 2, "to items parses")
check(parsedRSS.first?.title == "Første artikel", "titel korrekt")
check(parsedRSS.first?.link == "https://x.dk/a1", "link korrekt")
check(parsedRSS.first?.imageURL == "https://x.dk/img1.jpg", "media:thumbnail fundet")
check(parsedRSS.first?.pubDate != nil, "pubDate fundet")

suite("Atom-parsing")
let atom = """
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <entry>
    <title>Atom-artikel</title>
    <link href="https://x.dk/atom1"/>
    <updated>2026-06-10T08:00:00Z</updated>
  </entry>
</feed>
"""
let parsedAtom = RSSParser().parse(data: Data(atom.utf8))
check(parsedAtom.count == 1, "én entry parses")
check(parsedAtom.first?.link == "https://x.dk/atom1", "Atom link href fundet")

suite("Datoparsing")
check(FeedStore.parseRSSDate("Tue, 10 Jun 2026 08:00:00 +0200") != nil, "RFC822-format")
check(FeedStore.parseRSSDate("2026-06-10T08:00:00Z") != nil, "ISO8601-format")
check(FeedStore.parseRSSDate("ikke en dato") == nil, "ugyldig dato → nil")
check(FeedStore.parseRSSDate(nil) == nil, "nil → nil")

// MARK: – Story clustering

suite("Story clustering")
let clusterInput = [
    testArticle("1", "Trump siger Iran nedskød amerikansk militærhelikopter"),
    testArticle("2", "Trump: Iran skød amerikansk militærhelikopter ned"),
    testArticle("3", "Ny MacBook Pro lanceret med M5-chip"),
]
let clustered = FeedStore.clusterArticles(clusterInput)
let clusters = clustered.compactMap { item -> StoryCluster? in
    if case .cluster(let c) = item { return c }
    return nil
}
check(clusters.count == 1, "samme historie clustres")
check(clusters.first?.articles.count == 2, "cluster indeholder begge versioner")

let unrelated = FeedStore.clusterArticles([
    testArticle("1", "Regeringen fremlægger finanslov for 2027"),
    testArticle("2", "Ny MacBook Pro lanceret med M5-chip"),
    testArticle("3", "Vejret bliver solrigt i weekenden"),
])
check(unrelated.count == 3, "urelaterede forbliver enkeltartikler")
check(!unrelated.contains(where: { if case .cluster = $0 { return true }; return false }),
      "ingen falske clusters")

let wa = FeedStore.titleWords("Trump siger Iran nedskød amerikansk helikopter")
let wb = FeedStore.titleWords("Trump: Iran nedskød amerikansk helikopter i nat")
let wc = FeedStore.titleWords("Ny MacBook Pro med M5-chip")
check(FeedStore.titleSimilarity(wa, wb) >= 0.42, "ens overskrifter over tærskel")
check(FeedStore.titleSimilarity(wa, wc) < 0.42, "forskellige under tærskel")

// MARK: – Tema-klassificering

print("\n— Tema-klassificering")
check(classifyTheme(url: "https://www.dr.dk/nyheder/indland/ny-bro-aabner", sourceID: "dr") == .indland,
      "DR /indland/ → indland")
check(classifyTheme(url: "https://www.dr.dk/nyheder/udland/valg-i-frankrig", sourceID: "dr") == .udland,
      "DR /udland/ → udland")
check(classifyTheme(url: "https://jp.dk/politik/ECE123/finanslov", sourceID: "jp") == .politik,
      "JP /politik/ → politik")
check(classifyTheme(url: "https://www.berlingske.dk/danmark/nyt-sygehus", sourceID: "berlingske") == .indland,
      "Berlingske /danmark/ → indland")
check(classifyTheme(url: "https://www.berlingske.dk/internationalt/topmoede", sourceID: "berlingske") == .udland,
      "Berlingske /internationalt/ → udland")
check(classifyTheme(url: "https://www.macrumors.com/2026/07/15/some-apple-story/", sourceID: "macrumors") == .tech,
      "MacRumors → tech (kildestandard)")
check(classifyTheme(url: "https://www.nytimes.com/2026/07/14/world/europe/nato.html", sourceID: "nyt") == .udland,
      "NYT world → udland")
check(classifyTheme(url: "https://www.nytimes.com/2026/07/14/technology/ai-chips.html", sourceID: "nyt") == .tech,
      "NYT technology → tech (sti før kildestandard)")
check(classifyTheme(url: "https://ekstrabladet.dk/nyheder/samfundet/opdateret-sag", sourceID: "eb") == .indland,
      "EB /samfund → indland")
check(classifyTheme(url: "https://borsen.dk/nyheder/virksomheder/stort-opkoeb", sourceID: "borsen") == .andet,
      "Børsen virksomheder → andet")
check(classifyTheme(url: "https://www.dr.dk/nyheder/seneste/kort-nyt", sourceID: "dr",
                    tags: ["Politik"]) == .politik,
      "tag 'Politik' → politik")
check(classifyTheme(url: "https://example.dk/artikel/x", sourceID: "custom1",
                    tags: ["Italien"]) == .andet,
      "tag 'Italien' rammer ikke 'it'-ordet")

// MARK: – Resultat

print("\n══════════════════════════════")
print("  \(passed) bestået, \(failed) fejlet")
print("══════════════════════════════")
exit(failed == 0 ? 0 : 1)

import Foundation

struct ParsedArticle {
    var title: String
    var link: String
    var pubDate: String?
    var imageURL: String?
    var tags: [String] = []
}

final class RSSParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var articles: [ParsedArticle] = []
    private var current: [String: String] = [:]
    private var currentElement = ""
    private var inItem = false
    private var mediaURL: String?
    private var currentText = ""
    private var currentTags: [String] = []

    func parse(data: Data) -> [ParsedArticle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return articles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attrs: [String: String]) {
        let local = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        currentElement = local
        currentText = ""

        if local == "item" || local == "entry" {
            inItem = true
            current = [:]
            mediaURL = nil
            currentTags = []
            return
        }
        guard inItem else { return }

        // media:thumbnail, media:content, enclosure
        if (local == "thumbnail" || local == "content"), let url = attrs["url"], mediaURL == nil {
            mediaURL = url
        }
        if local == "enclosure", let url = attrs["url"],
           let type = attrs["type"], type.hasPrefix("image/"), mediaURL == nil {
            mediaURL = url
        }
        // Atom <link href="...">
        if local == "link", let href = attrs["href"], current["link"] == nil {
            current["link"] = href
        }
        // Atom <category term="...">
        if local == "category", let term = attrs["term"], !term.isEmpty {
            currentTags.append(term)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()

        if inItem {
            let txt = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local {
            case "title":
                // Kun det u-prefixede <title> — media:title er billedtekst
                // (fx TV Technology: "ViewNexa logo") og må ikke overskrive
                // artiklens titel; prefixet er strippet i `local`, så tjek
                // det fulde elementnavn
                if elementName.lowercased() == "title" { current["title"] = txt }
            case "link":    if current["link"] == nil { current["link"] = txt }
            case "id":      if current["link"] == nil { current["link"] = txt }
            case "pubdate", "published", "updated", "date":
                if current["pubdate"] == nil { current["pubdate"] = txt }
            case "description", "summary":
                if mediaURL == nil { mediaURL = extractImage(from: txt) }
            case "category":
                // RSS 2.0 <category>tekst</category>
                if !txt.isEmpty { currentTags.append(txt) }
            default: break
            }
        }

        if local == "item" || local == "entry" {
            let title = current["title"] ?? ""
            let link  = current["link"]  ?? ""
            if !title.isEmpty && !link.isEmpty {
                articles.append(ParsedArticle(
                    title: title, link: link,
                    pubDate: current["pubdate"],
                    imageURL: mediaURL,
                    tags: currentTags
                ))
            }
            inItem = false
        }
    }

    private func extractImage(from html: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: #"<img[^>]+src=["']([^"']+)["']"#,
                                               options: .caseInsensitive),
              let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(m.range(at: 1), in: html)
        else { return nil }
        return String(html[range])
    }
}

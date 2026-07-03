import Foundation

let defaultFeeds: [FeedSource] = [
    FeedSource(id: "dr",            name: "DR",             url: "https://www.dr.dk/nyheder/service/feeds/allenyheder",        colorHex: "#e2231a"),
    FeedSource(id: "tv2",           name: "TV 2",           url: "https://nyheder.tv2.dk/",                                     colorHex: "#0a4f9e", feedType: .scrape),
    FeedSource(id: "eb",            name: "Ekstra Bladet",  url: "https://ekstrabladet.dk/rssfeed/nyheder/",                    colorHex: "#f5a623"),
    FeedSource(id: "berlingske",    name: "Berlingske",     url: "https://www.berlingske.dk/content/rss",                       colorHex: "#1f6f6f"),
    FeedSource(id: "politiken",     name: "Politiken",      url: "https://politiken.dk/rss/senestenyt.rss",                     colorHex: "#c0392b"),
    FeedSource(id: "jp",            name: "Jyllands-Posten", url: "https://jp.dk",                                              colorHex: "#12355b", feedType: .scrape),
    FeedSource(id: "borsen",        name: "Børsen",         url: "https://borsen.dk/rss",                                       colorHex: "#c8a400"),
    FeedSource(id: "ing",           name: "Ingeniøren",     url: "https://ing.dk/rss/nyheder",                                  colorHex: "#1b6ec2"),
    FeedSource(id: "engadget",      name: "Engadget",       url: "https://www.engadget.com/rss.xml",                            colorHex: "#00b4c5", filterCommercial: true),
    FeedSource(id: "macrumors",     name: "MacRumors",      url: "https://feeds.macrumors.com/MacRumors-All",                   colorHex: "#2c3e50", filterCommercial: true),
    FeedSource(id: "9to5mac",       name: "9to5Mac",        url: "https://9to5mac.com/feed/",                                   colorHex: "#e84d1c", filterCommercial: true),
    FeedSource(id: "flatpanels",    name: "Flatpanels",     url: "https://www.flatpanels.dk/rss/nyhed.xml",                     colorHex: "#5b2d8e"),
    FeedSource(id: "recordere",     name: "Recordere",      url: "https://www.recordere.dk/feed/",                              colorHex: "#1a6b3a"),
    FeedSource(id: "digitaltv",     name: "Digitalt TV",    url: "https://digitalt.tv/feed/",                                   colorHex: "#c0392b"),
    FeedSource(id: "verge",         name: "The Verge",      url: "https://www.theverge.com/rss/index.xml",                      colorHex: "#e5343a", filterCommercial: true),
    FeedSource(id: "ars",           name: "Ars Technica",   url: "https://feeds.arstechnica.com/arstechnica/index",             colorHex: "#f67a1a", filterCommercial: true),
    FeedSource(id: "techcrunch",    name: "TechCrunch",     url: "https://techcrunch.com/feed/",                                colorHex: "#0a7d5c", filterCommercial: true),
    FeedSource(id: "mediebranchen", name: "Mediebranchen",  url: "https://mediebranchen.dk/feed/",                              colorHex: "#5b4ea0"),
    FeedSource(id: "mediawatch",    name: "MediaWatch",     url: "https://mediawatch.dk/latest",                                colorHex: "#005b8e", feedType: .scrape),
    FeedSource(id: "tvtechnology",  name: "TV Technology",  url: "https://www.tvtechnology.com/feeds.xml",                      colorHex: "#7d3c98", filterCommercial: true),
    FeedSource(id: "nyt",           name: "NY Times",
               url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml",
               additionalURLs: [
                   "https://rss.nytimes.com/services/xml/rss/nyt/Europe.xml",
                   "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml",
                   "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml",
                   "https://rss.nytimes.com/services/xml/rss/nyt/PersonalTech.xml",
                   "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml",
               ],
               colorHex: "#000000", filterCommercial: true),
]

// Farvepalette til auto-tildeling af nye custom kilder
let customSourceColors: [String] = [
    "#e74c3c", "#9b59b6", "#2ecc71", "#f39c12", "#1abc9c",
    "#3498db", "#e67e22", "#16a085", "#8e44ad", "#d35400",
]

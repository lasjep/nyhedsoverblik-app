import Foundation

// Matches på ordgrænser — "cykling" må ikke ramme "recycling",
// og "transfer" ramte tidligere "data transfer" i tech-nyheder.
private let sportWords: Set<String> = [
    "sport", "fodbold", "håndbold", "superliga", "champions league",
    "landsholdet", "ishockey", "badminton", "cykling", "tour de france",
    "formel 1", "f1", "motorsport", "wozniacki", "transfervindue",
    "pokalen", "ligaen", "vm i", "em i",
]

private let clickbaitPrefixes = [
    "derfor", "sådan", "se her", "se:", "live:", "afslører",
    "chok", "rasende", "du skal", "her er grunden", "advarsel:", "pas på", "nu sker det",
]

private let clickbaitWords = [
    "chokerer", "rasende", "raser", "vanvittig", "vild video",
    "du vil ikke tro", "alle taler om", "går viralt", "eksperter advarer",
]

private let commercialWords = [
    "giveaway", "sweepstakes", "win a ", "win an ", "% off",
    "deal:", "deals:", "sale:", "best deals", "discount", "coupon",
    "promo code", "sponsored", "price drop", "save $", "save up to",
    "prime day", "black friday", "cyber monday", "affiliate",
]

// Normalisér til " ord ord ord " så der kan matches på hele ord/fraser
private func paddedWords(_ s: String) -> String {
    " " + s.lowercased()
        .map { $0.isLetter || $0.isNumber ? $0 : " " }
        .reduce(into: "") { $0.append($1) }
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: " ") + " "
}

func isSport(title: String, url: String, tags: [String] = []) -> Bool {
    let path = URL(string: url)?.path.lowercased() ?? ""
    if ["/sport", "/fodbold", "/haandbold"].contains(where: { path.contains($0) }) { return true }
    let padded = paddedWords(title)
    if sportWords.contains(where: { padded.contains(" \($0) ") }) { return true }
    // Tags (article:tag / RSS-kategorier) — fanger fx sportspodcasts hvor
    // hverken titel eller URL afslører emnet. Prefix-match så
    // "Superligaen" rammer "superliga".
    for tag in tags {
        let t = paddedWords(tag)
        if sportWords.contains(where: { t.contains(" \($0) ") }) { return true }
        let tokens = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.contains(where: { tok in sportWords.contains(where: { tok.hasPrefix($0) }) }) {
            return true
        }
    }
    return false
}

func clickbaitScore(title: String) -> Int {
    let low = title.lowercased()
    var score = clickbaitPrefixes.contains(where: { low.hasPrefix($0) }) ? 2 : 0
    score += clickbaitWords.filter { low.contains($0) }.count
    if title.contains("?!") || title.contains("!!") { score += 2 }
    score += title.filter { $0 == "!" }.count
    let capsWords = title.components(separatedBy: .whitespaces)
        .filter { $0.count >= 3 && $0 == $0.uppercased() && !["USA","EU","DSB","DR","FN","NATO","SF","DF"].contains($0) }
    if capsWords.count >= 2 { score += 2 }
    return score
}

func isCommercial(title: String) -> Bool {
    let low = title.lowercased()
    return commercialWords.contains(where: { low.contains($0) })
}

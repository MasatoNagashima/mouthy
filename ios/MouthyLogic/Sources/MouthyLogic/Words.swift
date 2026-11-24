import Foundation

public enum SpokenWords {
    public static let fillers = [
        "um", "uh", "uhh", "erm", "er", "hmm", "hm", "ah", "eh", "mm", "mhm",
        "えーと", "えーっと", "えっと", "あのー", "あの", "そのー", "その", "うーん", "えー",
    ]

    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(Int(scalar.value)) || (0x4E00...0x9FAF).contains(Int(scalar.value))
        }
    }

    public static func questionCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "?" || $1 == "？" ? 1 : 0) }
    }

    public static func count(_ text: String, fillers: [String] = SpokenWords.fillers) -> Int {
        let cleaned = removeFillers(text, fillers: fillers)
        return tokens(cleaned).filter { !isFiller($0, fillers: fillers) }.count
    }

    public static func containsBannedJudgement(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned = ["score", "grade", "points", "incorrect", "wrong", "mistake", "評価", "点数", "減点", "間違い"]
        return banned.contains { lower.contains($0) }
    }

    private static func tokens(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func isFiller(_ token: String, fillers: [String]) -> Bool {
        let lower = token.lowercased()
        return fillers.contains { $0.caseInsensitiveCompare(lower) == .orderedSame }
    }

    private static func removeFillers(_ text: String, fillers: [String]) -> String {
        var cleaned = text
        let ordered = fillers.sorted { $0.count > $1.count }
        for filler in ordered {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            let pattern = filler.rangeOfCharacter(from: .letters) == nil || filler.unicodeScalars.contains { $0.value > 127 }
                ? escaped
                : "\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        return cleaned
    }
}

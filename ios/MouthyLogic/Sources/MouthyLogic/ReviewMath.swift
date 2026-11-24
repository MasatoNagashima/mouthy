import Foundation

public struct ReviewCorrection: Equatable, Identifiable, Sendable {
    public var id: String
    public var tag: String
    public var original: String
    public var better: String
    public var reasonJa: String

    public init(id: String, tag: String, original: String, better: String, reasonJa: String) {
        self.id = id
        self.tag = tag
        self.original = original
        self.better = better
        self.reasonJa = reasonJa
    }
}

public struct StuckPhrase: Equatable, Identifiable, Sendable {
    public var id: String
    public var phrase: String
    public var meaningJa: String
    public var reason: String

    public init(id: String, phrase: String, meaningJa: String, reason: String) {
        self.id = id
        self.phrase = phrase
        self.meaningJa = meaningJa
        self.reason = reason
    }
}

public struct LocalReview: Equatable, Sendable {
    public var score: ScoreFormula.Result
    public var delta: Int?
    public var strength: String
    public var nextSteps: [String]
    public var corrections: [ReviewCorrection]
    public var speakingWpm: Int?

    public init(score: ScoreFormula.Result, delta: Int?, strength: String, nextSteps: [String], corrections: [ReviewCorrection], speakingWpm: Int?) {
        self.score = score
        self.delta = delta
        self.strength = strength
        self.nextSteps = nextSteps
        self.corrections = corrections
        self.speakingWpm = speakingWpm
    }
}

public enum ReviewMath {
    public static func corrections(for learnerTexts: [String]) -> [ReviewCorrection] {
        var found: [ReviewCorrection] = []
        for raw in learnerTexts {
            let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if text.isEmpty || found.count >= 2 { continue }
            let lower = text.lowercased()
            if lower.contains("last year") && (lower.contains("join") || lower.contains(" go ") || lower.hasPrefix("go ") || lower.contains("start") || lower.contains(" am ") || lower.contains(" is ")) {
                var better = text
                better = replacing(better, "join", "joined")
                better = replacing(better, "go", "went")
                better = replacing(better, "start", "started")
                better = replacing(better, "am", "was")
                better = replacing(better, "is", "was")
                found.append(ReviewCorrection(
                    id: "tense-\(found.count)",
                    tag: "時制",
                    original: text,
                    better: better,
                    reasonJa: "去年のことなので過去形にします。今も続けているなら、現在完了も使えます。"
                ))
                continue
            }
            if lower.contains("shy person") {
                found.append(ReviewCorrection(
                    id: "literal-\(found.count)",
                    tag: "直訳",
                    original: text,
                    better: "One thing I'm working on is speaking up in groups.",
                    reasonJa: "shy person は否定的に響きやすいので、改善中の行動として言うと伝わりやすいです。"
                ))
            }
        }
        return found
    }

    public static func build(
        levels: [ScoreFormula.Level],
        learnerAskedOrExpanded: Bool,
        learnerTexts: [String],
        checkpointsDone: Int,
        checkpointsTotal: Int,
        speakingWpm: Double?,
        reactionMedianMs: Double?,
        averageWordsPerTurn: Double?,
        wordCount: Int,
        previousTotal: Int?
    ) -> LocalReview {
        let fixes = corrections(for: learnerTexts)
        let score = ScoreFormula.compute(
            levels: levels,
            checkpointsDone: checkpointsDone,
            checkpointsTotal: checkpointsTotal,
            learnerAskedOrExpanded: learnerAskedOrExpanded,
            speakingWpm: speakingWpm,
            reactionMedianMs: reactionMedianMs,
            averageWordsPerTurn: averageWordsPerTurn,
            wordCount: wordCount,
            majorErrors: fixes.count,
            minorErrors: 0
        )
        let quoted = learnerTexts
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { SpokenWords.count($0) >= 4 }
        let strength = quoted.map { "「\($0)」と、自分の言葉で答えられていました。" } ?? narrativeStrength(levels: levels, asked: learnerAskedOrExpanded)
        let delta = previousTotal.map { score.total - $0 }
        return LocalReview(
            score: score,
            delta: delta,
            strength: strength,
            nextSteps: nextSteps(levels: levels, asked: learnerAskedOrExpanded),
            corrections: fixes,
            speakingWpm: speakingWpm.map { Int($0.rounded()) }
        )
    }

    public static func speakingWPM(wordCount: Int, speakingMs: Int) -> Double? {
        guard speakingMs > 0 else { return nil }
        return Double(wordCount) / (Double(speakingMs) / 60_000)
    }

    private static func narrativeStrength(levels: [ScoreFormula.Level], asked: Bool) -> String {
        if levels.isEmpty { return "質問と答えの組は、今回は見つかりませんでした。会話そのものには参加しています。" }
        let answers = levels.filter { $0 == .answers }.count
        if answers * 2 >= levels.count { return "質問に対して、意味が通る答えが半分以上ありました。" }
        if asked { return "自分から質問するか、答えに一文以上を足していました。" }
        return "最後まで、相手の質問に向きあっていました。"
    }

    private static func nextSteps(levels: [ScoreFormula.Level], asked: Bool) -> [String] {
        var steps: [String] = []
        if levels.contains(.noAnswer) || levels.contains(.offTopic) {
            steps.append("答えきれていない質問がありました。次は、質問の中の語を一つ使ってから話し始めると、話題が合いやすくなります。")
        }
        if levels.contains(.partial) {
            steps.append("途中までしか答えていない箇所がありました。一言だけ足すと、相手が次の質問をしやすくなります。")
        }
        if !asked {
            steps.append("自分からの質問や、話の広げはまだありません。答えたあとに、一文だけ自分の話を足してみてください。")
        }
        if steps.isEmpty {
            steps.append("次も、答えたあとに一文だけ足すと、会話が続きやすくなります。")
        }
        return Array(steps.prefix(2))
    }

    private static func replacing(_ text: String, _ word: String, _ replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(word)\\b", options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}

public struct SessionSnapshot: Equatable, Identifiable, Sendable {
    public var id: String
    public var sceneId: String
    public var startedAt: Date
    public var total: Int
    public var communication: Int
    public var fluency: Int
    public var accuracy: Int
    public var speakingWpm: Int?
    public var talkRatio: Double?
    public var reactionSec: Double?
    public var averageWords: Double?

    public init(
        id: String,
        sceneId: String,
        startedAt: Date,
        total: Int,
        communication: Int,
        fluency: Int,
        accuracy: Int,
        speakingWpm: Int?,
        talkRatio: Double?,
        reactionSec: Double?,
        averageWords: Double?
    ) {
        self.id = id
        self.sceneId = sceneId
        self.startedAt = startedAt
        self.total = total
        self.communication = communication
        self.fluency = fluency
        self.accuracy = accuracy
        self.speakingWpm = speakingWpm
        self.talkRatio = talkRatio
        self.reactionSec = reactionSec
        self.averageWords = averageWords
    }
}

public enum TrendRange: String, CaseIterable, Sendable {
    case week
    case fourWeeks
    case all

    public var title: String {
        switch self {
        case .week: return "週"
        case .fourWeeks: return "4週間"
        case .all: return "全期間"
        }
    }
}

public struct TrendPoint: Equatable, Identifiable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var total: Double
    public var communication: Double
    public var fluency: Double
    public var accuracy: Double
    public var wpm: Double?
}

public enum ProgressMath {
    public static func medianLast(_ values: [Int], limit: Int) -> Int? {
        let slice = Array(values.suffix(limit)).sorted()
        guard !slice.isEmpty else { return nil }
        let mid = slice.count / 2
        if slice.count.isMultiple(of: 2) {
            return Int((Double(slice[mid - 1] + slice[mid]) / 2).rounded())
        }
        return slice[mid]
    }

    public static func series(_ sessions: [SessionSnapshot], range: TrendRange, today: Date, calendar: Calendar = StudyCalendar.tokyo()) -> [TrendPoint] {
        let start: Date?
        switch range {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: today)
        case .fourWeeks:
            start = calendar.date(byAdding: .day, value: -27, to: today)
        case .all:
            start = nil
        }
        let filtered = sessions.filter { session in
            guard let start else { return true }
            return session.startedAt >= calendar.startOfDay(for: start)
        }.sorted { $0.startedAt < $1.startedAt }
        var grouped: [String: [SessionSnapshot]] = [:]
        for session in filtered {
            grouped[StudyCalendar.dayKey(session.startedAt, calendar: calendar), default: []].append(session)
        }
        return grouped.keys.sorted().map { key in
            let items = grouped[key] ?? []
            func avg(_ values: [Int]) -> Double {
                guard !values.isEmpty else { return 0 }
                return Double(values.reduce(0, +)) / Double(values.count)
            }
            let wpms = items.compactMap(\.speakingWpm)
            return TrendPoint(
                dayKey: key,
                total: avg(items.map(\.total)),
                communication: avg(items.map(\.communication)),
                fluency: avg(items.map(\.fluency)),
                accuracy: avg(items.map(\.accuracy)),
                wpm: wpms.isEmpty ? nil : Double(wpms.reduce(0, +)) / Double(wpms.count)
            )
        }
    }

    public static func talkTimeLabel(seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        if hours > 0 { return "\(hours)時間\(minutes)分" }
        return "\(minutes)分"
    }

    public struct StartPoint: Equatable, Sendable {
        public var cefr: String
        public var level: Int
        public var message: String
    }

    public static func startPoint(total: Int) -> StartPoint {
        if total < 60 {
            return StartPoint(cefr: "A2+", level: 1, message: "Lv1シーンから始めましょう")
        }
        if total < 75 {
            return StartPoint(cefr: "B1", level: 2, message: "Lv2シーンにも挑戦できます")
        }
        return StartPoint(cefr: "B1+", level: 3, message: "Lv3シーンにも挑戦できます")
    }
}

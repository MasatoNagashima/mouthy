import Foundation

public enum ScoreFormula {
    public static let version = "2026-11-23"
    public static let communicationWeight = 0.50
    public static let fluencyWeight = 0.35
    public static let accuracyWeight = 0.15
    public static let targetWPM = 110.0
    public static let reactionBestMs = 2_000.0
    public static let reactionWorstMs = 10_000.0
    public static let targetWordsPerTurn = 12.0

    public enum Level: String, Sendable {
        case answers, partial, offTopic, noAnswer
    }

    public struct Result: Equatable, Sendable {
        public var version: String
        public var total: Int
        public var communication: Int
        public var fluency: Int
        public var accuracy: Int

        public init(version: String, total: Int, communication: Int, fluency: Int, accuracy: Int) {
            self.version = version
            self.total = total
            self.communication = communication
            self.fluency = fluency
            self.accuracy = accuracy
        }
    }

    public static func reactionPoints(_ medianMs: Double?) -> Double {
        guard let medianMs, medianMs.isFinite else { return 0 }
        if medianMs <= reactionBestMs { return 100 }
        if medianMs >= reactionWorstMs { return 0 }
        return 100 * (reactionWorstMs - medianMs) / (reactionWorstMs - reactionBestMs)
    }

    public static func speedPoints(_ speakingWpm: Double?) -> Double {
        guard let speakingWpm, speakingWpm.isFinite, speakingWpm > 0 else { return 0 }
        return min(100, (speakingWpm / targetWPM) * 100)
    }

    public static func lengthPoints(_ averageWords: Double?) -> Double {
        guard let averageWords, averageWords.isFinite, averageWords > 0 else { return 0 }
        return min(100, (averageWords / targetWordsPerTurn) * 100)
    }

    /// 各軸を整数にしてから、同じ重みで総合点を四捨五入する。TypeScript の computeScore と同じ。
    public static func compute(
        levels: [Level],
        checkpointsDone: Int,
        checkpointsTotal: Int,
        learnerAskedOrExpanded: Bool,
        speakingWpm: Double?,
        reactionMedianMs: Double?,
        averageWordsPerTurn: Double?,
        wordCount: Int,
        majorErrors: Int,
        minorErrors: Int
    ) -> Result {
        let established: Double
        if levels.isEmpty {
            established = 0
        } else {
            let sum = levels.reduce(0.0) { partial, level in
                switch level {
                case .answers: return partial + 1
                case .partial: return partial + 0.5
                case .offTopic, .noAnswer: return partial
                }
            }
            established = sum / Double(levels.count)
        }
        let goalRate = checkpointsTotal > 0
            ? Double(min(max(checkpointsDone, 0), checkpointsTotal)) / Double(checkpointsTotal)
            : 0
        let initiative = learnerAskedOrExpanded ? 1.0 : 0
        let communication = roundScore(100 * (0.5 * established + 0.35 * goalRate + 0.15 * initiative))
        let fluency = roundScore(
            0.6 * speedPoints(speakingWpm)
                + 0.2 * reactionPoints(reactionMedianMs)
                + 0.2 * lengthPoints(averageWordsPerTurn)
        )
        let accuracy: Int
        if wordCount <= 0 {
            accuracy = 0
        } else {
            let words = Double(wordCount)
            let raw = 100
                - 15 * (Double(max(0, majorErrors)) / words * 100)
                - 3 * (Double(max(0, minorErrors)) / words * 100)
            accuracy = roundScore(max(0, raw))
        }
        let total = roundScore(
            communicationWeight * Double(communication)
                + fluencyWeight * Double(fluency)
                + accuracyWeight * Double(accuracy)
        )
        return Result(version: version, total: total, communication: communication, fluency: fluency, accuracy: accuracy)
    }

    private static func roundScore(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return min(100, max(0, Int(value.rounded())))
    }
}

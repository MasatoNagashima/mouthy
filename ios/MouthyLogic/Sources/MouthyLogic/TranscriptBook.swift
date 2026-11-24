import Foundation

public enum Speaker: String, Codable, Sendable {
    case ai
    case learner
}

public enum BubbleState: String, Codable, Sendable {
    case streaming
    case partial
    case final
    case pending
    case failed
}

public struct Utterance: Equatable, Identifiable, Sendable {
    public var id: String
    public var speaker: Speaker
    public var text: String
    public var state: BubbleState
    public var startedAtMs: Int
    public var isHint: Bool
    public var pendingSinceMs: Int?

    public init(id: String, speaker: Speaker, text: String, state: BubbleState, startedAtMs: Int, isHint: Bool, pendingSinceMs: Int?) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.state = state
        self.startedAtMs = startedAtMs
        self.isHint = isHint
        self.pendingSinceMs = pendingSinceMs
    }
}

public struct TranscriptBook: Equatable, Sendable {
    public static let pendingText = "文字起こし中…"
    public static let failedText = "うまく文字にできませんでした"
    public static let transcriptTimeoutMs = 6_000

    public private(set) var utterances: [Utterance] = []

    /// 届いた順ではなく、発話が始まった時刻で並べる。相づちは入れない。
    public var ordered: [Utterance] {
        utterances.sorted { lhs, rhs in
            if lhs.startedAtMs == rhs.startedAtMs { return lhs.id < rhs.id }
            return lhs.startedAtMs < rhs.startedAtMs
        }
    }

    public mutating func beginAI(id: String, startedAtMs: Int, isHint: Bool) {
        guard utterances.contains(where: { $0.id == id }) == false else { return }
        utterances.append(Utterance(
            id: id, speaker: .ai, text: "", state: .streaming,
            startedAtMs: startedAtMs, isHint: isHint, pendingSinceMs: nil
        ))
    }

    public mutating func appendAI(id: String, delta: String) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[index].text += delta
        utterances[index].state = .streaming
    }

    public mutating func finishAI(id: String) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[index].text = utterances[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        utterances[index].state = .final
    }

    public mutating func beginLearner(id: String, startedAtMs: Int) {
        guard utterances.contains(where: { $0.id == id }) == false else { return }
        utterances.append(Utterance(
            id: id, speaker: .learner, text: "", state: .partial,
            startedAtMs: startedAtMs, isHint: false, pendingSinceMs: nil
        ))
    }

    public mutating func appendLearnerPartial(id: String, text: String) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[index].text = text
        if utterances[index].state != .final {
            utterances[index].state = .partial
        }
    }

    public mutating func markLearnerPending(id: String, atMs: Int) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        guard utterances[index].state != .final && utterances[index].state != .failed else { return }
        utterances[index].state = .pending
        utterances[index].pendingSinceMs = atMs
        if utterances[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            utterances[index].text = Self.pendingText
        }
    }

    public mutating func resolveLearner(id: String, text: String) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        utterances[index].text = trimmed.isEmpty ? Self.failedText : trimmed
        utterances[index].state = trimmed.isEmpty ? .failed : .final
        utterances[index].pendingSinceMs = nil
    }

    public mutating func failOverdue(nowMs: Int, timeoutMs: Int = transcriptTimeoutMs) {
        for index in utterances.indices {
            guard utterances[index].speaker == .learner, utterances[index].state == .pending,
                  let since = utterances[index].pendingSinceMs, nowMs - since >= timeoutMs
            else { continue }
            utterances[index].text = Self.failedText
            utterances[index].state = .failed
            utterances[index].pendingSinceMs = nil
        }
    }
}

public enum HintSchedule {
    /// 沈黙が delayMs ごとに次の段階。話しているあいだは出さない。最大 maxHints。
    public static func stage(silenceMs: Int, hintsAlreadyGiven: Int, delayMs: Int, maxHints: Int, speaking: Bool) -> Int? {
        if speaking || delayMs <= 0 || hintsAlreadyGiven >= maxHints { return nil }
        let next = hintsAlreadyGiven + 1
        if silenceMs >= next * delayMs { return next }
        return nil
    }
}

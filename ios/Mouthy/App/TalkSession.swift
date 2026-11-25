import AVFoundation
import Foundation
import Observation
import MouthyLogic

enum TalkPhase: Equatable {
    case connecting
    case aiSpeaking
    case listening
    case waiting
    case reconnecting
    case paused
    case ended
}

struct HintPresentation: Equatable {
    var stage: Int
    var title: String
    var prompt: String
    var choices: [String]
    var starter: String?
}

@MainActor
@Observable
final class TalkSession {
    var phase: TalkPhase = .connecting
    var book = TranscriptBook()
    var captionsOn: Bool
    var hintsRemaining = 3
    var hint: HintPresentation?
    var remainingSec: Int
    var usingScript = false
    var audioLevel: Double = 0
    var notice: String?
    /// 音声の状態（STG の検証用）。マイク送信量・AI 音声の受信量・エンジンの状態を1秒ごとに出す。
    var audioDebug: String?
    private let launch: TalkLaunch
    private let settings: AppSettings
    private let previous: PracticeSession?
    private let api: APIClient
    private var player: Task<Void, Never>?
    private var live: RealtimeRTC?
    private var ended = false
    private let started = Date()

    init(launch: TalkLaunch, settings: AppSettings, previous: PracticeSession?, api: APIClient) {
        self.launch = launch
        self.settings = settings
        self.previous = previous
        self.api = api
        self.captionsOn = settings.captionsOn
        self.remainingSec = (launch.diagnostic ? 3 : launch.minutes) * 60
    }

    var statusText: String {
        switch phase {
        case .connecting: return "つないでいます"
        case .aiSpeaking: return "パクが話しています"
        case .listening: return "聞いています"
        case .waiting: return hint == nil ? "考えている間は待ちます" : "考えている間は待ちます"
        case .reconnecting: return "つなぎ直しています"
        case .paused: return "一時停止中"
        case .ended: return "会話が終わりました"
        }
    }

    var orbSpeaker: OrbSpeaker {
        switch phase {
        case .aiSpeaking: return .ai
        case .listening: return .learner
        case .waiting, .paused: return .thinking
        default: return .idle
        }
    }

    func start() {
        player = Task { await run() }
    }

    func toggleCaptions() { captionsOn.toggle() }

    func togglePause() {
        if phase == .paused {
            phase = .waiting
            live?.setMicEnabled(true)
        } else if phase == .aiSpeaking || phase == .listening || phase == .waiting {
            phase = .paused
            hint = nil
            live?.setMicEnabled(false)
        }
    }

    func requestHint() {
        guard hintsRemaining > 0, phase != .paused, phase != .connecting else { return }
        showHint(stage: min(4 - hintsRemaining, 3))
    }

    func finish() async -> PracticeSession {
        ended = true
        live?.close()
        player?.cancel()
        phase = .ended
        return await makeSession()
    }

    private func run() async {
        phase = .connecting
        let config = try? await api.config()
        if config?.voiceReady == true {
            // 診断も含め、本物の音声でつなぐ。台本（学習者の発話を自動で入れるデモ）には切り替えない。
            usingScript = false
            notice = nil
            await runLive()
        } else {
            usingScript = false
            notice = config == nil
                ? "サーバーに接続できませんでした。通信を確認して、もう一度お試しください。"
                : "音声サーバーの準備ができていません。しばらくしてからお試しください。"
            phase = .ended
        }
    }

    private func runScript() async {
        let script = TalkScript.script(for: launch.scene)
        var clock = 0
        phase = .aiSpeaking
        while clock <= script.durationMs, !ended, !Task.isCancelled {
            if phase != .paused {
                for line in script.lines where line.atMs == clock {
                    append(line)
                }
                if let hint = script.hint, hint.atMs == clock {
                    showHint(stage: hint.stage, preset: hint)
                }
                if clock % 1000 == 0, remainingSec > 0 { remainingSec -= 1 }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if phase != .paused { clock += 200 }
        }
        if !ended { phase = .waiting }
    }

    private func append(_ line: ScriptedLine) {
        let id = UUID().uuidString
        switch line.who {
        case .ai:
            phase = .aiSpeaking
            hint = nil
            book.beginAI(id: id, startedAtMs: line.atMs, isHint: false)
            book.appendAI(id: id, delta: line.text)
            book.finishAI(id: id)
            phase = .waiting
        case .learner:
            phase = .listening
            book.beginLearner(id: id, startedAtMs: line.atMs)
            book.appendLearnerPartial(id: id, text: line.text)
            book.resolveLearner(id: id, text: line.text)
            phase = .waiting
        }
    }

    private func showHint(stage: Int, preset: ScriptedHint? = nil) {
        guard hintsRemaining > 0 else { return }
        hintsRemaining -= 1
        phase = .waiting
        if stage <= 1 {
            hint = nil
            let id = UUID().uuidString
            book.beginAI(id: id, startedAtMs: Int(Date().timeIntervalSince(started) * 1000), isHint: true)
            book.appendAI(id: id, delta: "Let me ask that in a shorter way.")
            book.finishAI(id: id)
            return
        }
        if let preset {
            hint = HintPresentation(stage: preset.stage, title: preset.stage == 3 ? "ヒント 3 · 書き出し" : "ヒント 2 · 選択肢", prompt: preset.prompt, choices: preset.choices, starter: preset.starter)
            return
        }
        if stage >= 3 {
            hint = HintPresentation(stage: 3, title: "ヒント 3 · 書き出し", prompt: "こう言いはじめてみましょう", choices: [], starter: "In my club, I")
        } else {
            hint = HintPresentation(stage: 2, title: "ヒント 2 · 選択肢", prompt: "Was that in a club, or a part-time job?", choices: ["In a club", "At my part-time job"], starter: nil)
        }
    }

    private func runLive() async {
        var ticker: Task<Void, Never>?
        defer {
            ticker?.cancel()
            live?.close()
            live = nil
        }
        do {
            // マイクの許可を先に確かめる。許可がないと声が届かない。
            var micAllowed = AVAudioApplication.shared.recordPermission == .granted
            if AVAudioApplication.shared.recordPermission == .undetermined {
                micAllowed = await AVAudioApplication.requestRecordPermission()
            }
            if !micAllowed {
                notice = "マイクがオフになっています。iPhoneの「設定」>「Mouthy STG」でマイクをオンにしてください。"
            }
            guard !ended, !Task.isCancelled else { return }
            let minted = try await api.mint(scene: launch.scene, settings: settings, phrases: [])
            guard !ended, !Task.isCancelled else { return }
            let rtc = RealtimeRTC(token: minted.token)
            live = rtc
            try await rtc.connect()
            audioDebug = rtc.status().line
            phase = .aiSpeaking
            let deadline = Date().addingTimeInterval(TimeInterval(remainingSec))
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self else { return }
                    self.audioDebug = rtc.status().line
                    self.remainingSec = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                    if self.remainingSec == 0 || self.ended {
                        rtc.close()
                        return
                    }
                }
            }
            while !ended, !Task.isCancelled {
                if phase == .paused {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                guard let event = await rtc.nextEvent() else { break }
                apply(event)
            }
            rtc.close()
            if !ended { phase = .ended }
        } catch {
            live?.close()
            if let live { audioDebug = live.status().line }
            notice = "音声に繋げませんでした。\(error.localizedDescription)"
            phase = .ended
        }
    }

    private func apply(_ event: RealtimeEvent) {
        switch event {
        case .aiDelta(let id, let text, let at):
            phase = .aiSpeaking
            hint = nil
            if book.utterances.contains(where: { $0.id == id }) {
                book.appendAI(id: id, delta: text)
            } else {
                book.beginAI(id: id, startedAtMs: at, isHint: false)
                book.appendAI(id: id, delta: text)
            }
        case .aiDone(let id):
            book.finishAI(id: id)
            phase = .waiting
        case .learnerStarted(let id, let at):
            phase = .listening
            audioLevel = 0.6
            book.beginLearner(id: id, startedAtMs: at)
        case .learnerPartial(let id, let text):
            book.appendLearnerPartial(id: id, text: text)
        case .learnerFinal(let id, let text, let at):
            if !book.utterances.contains(where: { $0.id == id }) {
                book.beginLearner(id: id, startedAtMs: at)
            }
            book.resolveLearner(id: id, text: text)
            phase = .waiting
        case .learnerStopped(let id, let at):
            audioLevel = 0
            book.markLearnerPending(id: id, atMs: at)
        case .aiAudioStarted:
            if phase != .listening { phase = .aiSpeaking }
        case .aiAudioStopped:
            if phase == .aiSpeaking { phase = .waiting }
        case .failure(let message):
            notice = message
        case .disconnected:
            if !ended, remainingSec > 0 { notice = "音声の接続が切れました。もう一度はじめてください。" }
        }
    }

    private func makeSession() async -> PracticeSession {
        let finals = book.ordered.filter { (utterance: Utterance) in
            utterance.state == BubbleState.final && !utterance.text.isEmpty && utterance.text != TranscriptBook.pendingText
        }
        let learner = finals.compactMap { (utterance: Utterance) -> String? in
            utterance.speaker == Speaker.learner ? utterance.text : nil
        }
        let words = learner.reduce(0) { $0 + SpokenWords.count($1) }
        let asked = learner.contains { SpokenWords.questionCount($0) > 0 || SpokenWords.count($0) >= 12 }
        let levels: [ScoreFormula.Level] = learner.isEmpty ? [] : Array(repeating: .answers, count: learner.count)
        let local = ReviewMath.build(
            levels: levels,
            learnerAskedOrExpanded: asked,
            learnerTexts: learner,
            checkpointsDone: min(learner.count, launch.scene.checkpoints.count),
            checkpointsTotal: max(launch.scene.checkpoints.count, 1),
            speakingWpm: nil,
            reactionMedianMs: nil,
            averageWordsPerTurn: learner.isEmpty ? nil : Double(words) / Double(learner.count),
            wordCount: words,
            previousTotal: previous?.total
        )
        var review = local
        let storedTurns = finals.map { StoredTurn(id: $0.id, speaker: $0.speaker, text: $0.text) }
        if let server = try? await api.review(
            turns: storedTurns,
            speakingWpm: usingScript ? nil : local.speakingWpm.map(Double.init),
            reactionMedianMs: nil,
            checkpointsDone: min(learner.count, launch.scene.checkpoints.count),
            checkpointsTotal: max(launch.scene.checkpoints.count, 1),
            previousTotal: previous?.total
        ) {
            review = LocalReview(
                score: ScoreFormula.Result(version: server.formulaVersion, total: server.score.total, communication: server.score.communication, fluency: server.score.fluency, accuracy: server.score.accuracy),
                delta: server.delta,
                strength: server.strength,
                nextSteps: server.nextSteps,
                corrections: server.corrections.enumerated().map { index, item in
                    ReviewCorrection(id: "server-\(index)", tag: item.tag, original: item.original, better: item.better, reasonJa: item.reasonJa)
                },
                speakingWpm: server.speakingWpm.map { Int($0.rounded()) }
            )
        }
        let script = TalkScript.script(for: launch.scene)
        let previousAxes = previous
        return PracticeSession(
            id: UUID().uuidString,
            sceneId: launch.diagnostic ? "diagnosis" : launch.scene.id,
            sceneTitle: launch.diagnostic ? "3分レベル診断" : launch.scene.title,
            category: launch.scene.category.rawValue,
            level: launch.scene.level,
            startedAt: started,
            durationSec: max(1, Int(Date().timeIntervalSince(started))),
            total: review.score.total,
            delta: review.delta,
            communication: review.score.communication,
            fluency: review.score.fluency,
            accuracy: review.score.accuracy,
            communicationDelta: previousAxes.map { review.score.communication - $0.communication },
            fluencyDelta: previousAxes.map { review.score.fluency - $0.fluency },
            accuracyDelta: previousAxes.map { review.score.accuracy - $0.accuracy },
            speakingWpm: review.speakingWpm,
            talkRatio: learner.isEmpty ? nil : Double(learner.count) / Double(max(finals.count, 1)),
            reactionSec: nil,
            averageWords: learner.isEmpty ? nil : Double(words) / Double(learner.count),
            hintCount: 3 - hintsRemaining,
            strength: review.strength,
            nextSteps: review.nextSteps,
            corrections: review.corrections,
            stuck: usingScript ? script.stuck : [],
            turns: storedTurns,
            isDiagnostic: launch.diagnostic,
            formulaVersion: review.score.version
        )
    }
}

enum OrbSpeaker { case ai, learner, idle, thinking }

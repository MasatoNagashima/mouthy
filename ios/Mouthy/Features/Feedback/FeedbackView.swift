import AVFoundation
import SwiftUI
import MouthyLogic

struct FeedbackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 76
    @State private var synthesizer = AVSpeechSynthesizer()
    var session: PracticeSession
    var showsDone: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.xl) {
                    Text("\(session.sceneTitle) · \(max(1, session.durationSec / 60))分 · \(when)")
                        .font(.footnote)
                        .foregroundStyle(MColor.inkSecondary)
                    Text("おつかれさまでした").font(.title3.bold())
                    TotalScoreHero(total: session.total, delta: session.delta, size: scoreSize, reduceMotion: reduceMotion)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { tiles }
                        VStack(spacing: 8) { tiles }
                    }
                    Text(metricsLine).font(.footnote).foregroundStyle(MColor.inkSecondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("よかったところ").font(.headline)
                        Text(session.strength).font(.body)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("次の一手").font(.headline)
                        Text("伝わりにくかったところだけ、2つに絞りました。")
                            .font(.footnote)
                            .foregroundStyle(MColor.inkSecondary)
                        if session.corrections.isEmpty {
                            ForEach(Array(session.nextSteps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)").font(.callout)
                            }
                        } else {
                            ForEach(Array(session.corrections.enumerated()), id: \.element.id) { index, item in
                                correction(index + 1, item)
                            }
                        }
                    }
                    if !session.stuck.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("詰まった表現").font(.headline)
                            ForEach(session.stuck) { phrase in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(phrase.phrase).font(.body)
                                        Text("\(phrase.meaningJa) · \(phrase.reason)").font(.caption).foregroundStyle(MColor.inkSecondary)
                                    }
                                    Spacer()
                                    Button { speak(phrase.phrase) } label: {
                                        Image(systemName: "speaker.wave.2.fill").frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("\(phrase.phrase)を聞く")
                                }
                            }
                        }
                    }
                    if !session.turns.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("会話の記録").font(.headline)
                            ForEach(session.turns) { turn in
                                TranscriptBubble(utterance: Utterance(
                                    id: turn.id, speaker: turn.speaker, text: turn.text, state: .final,
                                    startedAtMs: 0, isHint: false, pendingSinceMs: nil
                                ))
                            }
                        }
                    }
                }
                .padding(MSpace.l)
            }
            .mouthyScreen()
            .navigationTitle("振り返り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { model.finishedSession = nil }
                    }
                }
            }
        }
    }

    private var tiles: some View {
        Group {
            SubScoreTile(axis: .communication, value: session.communication, delta: session.communicationDelta)
            SubScoreTile(axis: .fluency, value: session.fluency, delta: session.fluencyDelta)
            SubScoreTile(axis: .accuracy, value: session.accuracy, delta: session.accuracyDelta)
        }
    }

    private var metricsLine: String {
        let wpm = session.speakingWpm.map { "発話中WPM \($0)" } ?? "発話中WPM 算出不可"
        let ratio = session.talkRatio.map { "話した割合 \(Int(($0 * 100).rounded()))%" } ?? "話した割合 —"
        return "\(wpm) · \(ratio) · ヒント \(session.hintCount)回"
    }

    private var when: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: session.startedAt)
    }

    private func correction(_ index: Int, _ item: ReviewCorrection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index)  \(item.tag)").font(.caption.weight(.semibold)).foregroundStyle(MColor.amber)
            Text("あなた").font(.caption2).foregroundStyle(MColor.inkTertiary)
            Text(item.original).font(.callout)
            Text("こう").font(.caption2).foregroundStyle(MColor.green)
            Text(item.better).font(.callout.bold())
            Text(item.reasonJa).font(.footnote).foregroundStyle(MColor.inkSecondary)
        }
        .padding(MSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
        .overlay(RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.line))
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

struct TotalScoreHero: View {
    var total: Int
    var delta: Int?
    var size: CGFloat
    var reduceMotion: Bool
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(MColor.fill, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(shown) / 100)
                    .stroke(MColor.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(shown)")
                    .font(.mTotalScore(size: size))
                    .contentTransition(.numericText())
            }
            .frame(width: 220, height: 220)
            .frame(maxWidth: .infinity)
            Text("総合点").font(.caption).foregroundStyle(MColor.inkSecondary)
            if let delta {
                Text(deltaLabel(delta))
                    .font(.headline)
                    .foregroundStyle(delta < 0 ? MColor.inkSecondary : MColor.green)
            }
        }
        .onAppear {
            if reduceMotion { shown = total }
            else { withAnimation(.easeOut(duration: 0.8)) { shown = total } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("総合点 \(total)")
    }

    private func deltaLabel(_ delta: Int) -> String {
        if delta > 0 { return "前回より +\(delta)" }
        if delta < 0 { return "前回より −\(abs(delta))" }
        return "前回と同じ"
    }
}

struct SubScoreTile: View {
    var axis: ScoreAxis
    var value: Int
    var delta: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(axis.title).font(.caption).foregroundStyle(MColor.inkSecondary)
            Text("×\(Int(axis.weight * 100))%").font(.caption2).foregroundStyle(MColor.inkTertiary)
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Capsule().fill(axis.color).frame(width: CGFloat(value) * 0.7, height: 4)
            if let delta {
                Text(delta > 0 ? "+\(delta)" : (delta < 0 ? "−\(abs(delta))" : "±0"))
                    .font(.caption2)
                    .foregroundStyle(delta < 0 ? MColor.inkSecondary : MColor.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.list))
        .overlay(RoundedRectangle(cornerRadius: MRadius.list).stroke(MColor.line))
    }
}

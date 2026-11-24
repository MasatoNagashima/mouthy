import SwiftUI
import MouthyLogic

struct TalkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: TalkSession?
    @State private var confirmEnd = false

    var launch: TalkLaunch

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let session {
                if let notice = session.notice {
                    Text(notice).font(.caption).foregroundStyle(MColor.inkSecondary).padding(.horizontal, MSpace.l)
                }
                if session.captionsOn {
                    TalkStatusStrip(phase: session.phase, text: session.statusText, level: session.audioLevel, reduceMotion: reduceMotion)
                    TranscriptList(book: session.book, hint: session.hint)
                } else {
                    Spacer()
                    VoiceOrb(speaker: session.orbSpeaker, level: session.audioLevel, size: 132, reduceMotion: reduceMotion)
                    Text(session.statusText).font(.headline).padding(.top, 12)
                    Text("字幕はオフです。会話の記録は、振り返りでいつでも読めます。")
                        .font(.footnote)
                        .foregroundStyle(MColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    if let hint = session.hint { hintCard(hint).padding() }
                    Spacer()
                }
                controls(session)
            } else {
                ProgressView("つないでいます")
                Spacer()
            }
        }
        .mouthyScreen()
        .onAppear {
            let previous = model.sessions.first { !$0.isDiagnostic }
            let talk = TalkSession(launch: launch, settings: model.settings, previous: previous, api: model.api())
            session = talk
            talk.start()
        }
        .confirmationDialog("会話を終えますか？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("終えて振り返る", role: .destructive) { Task { await end() } }
            Button("続ける", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack {
            Button { confirmEnd = true } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("会話を終える")
            VStack(alignment: .leading, spacing: 2) {
                Text(launch.diagnostic ? "3分レベル診断" : launch.scene.title).font(.headline)
                if launch.diagnostic {
                    Text("これは点数ではなく、スタート地点を知るための会話です")
                        .font(.caption2)
                        .foregroundStyle(MColor.inkSecondary)
                }
            }
            Spacer()
            Text(clock).font(.headline.monospacedDigit()).foregroundStyle(MColor.apricotInk)
        }
        .padding(.horizontal, MSpace.s)
    }

    private var clock: String {
        let seconds = session?.remainingSec ?? launch.minutes * 60
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func controls(_ session: TalkSession) -> some View {
        HStack(spacing: 28) {
            Button { session.toggleCaptions() } label: {
                VStack(spacing: 4) {
                    Image(systemName: session.captionsOn ? "captions.bubble.fill" : "captions.bubble")
                        .frame(width: 56, height: 56)
                        .background(session.captionsOn ? MColor.tintGreen : MColor.fill, in: Circle())
                    Text(session.captionsOn ? "字幕オン" : "字幕オフ").font(.caption2)
                }
            }
            .accessibilityLabel(session.captionsOn ? "字幕オン" : "字幕オフ")
            Button { session.togglePause() } label: {
                Image(systemName: session.phase == .paused ? "mic.slash.fill" : "mic.fill")
                    .font(.title)
                    .frame(width: 84, height: 84)
                    .foregroundStyle(micForeground(session.phase))
                    .background(micBackground(session.phase), in: Circle())
                    .overlay(Circle().stroke(MColor.green, lineWidth: session.phase == .waiting ? 2 : 0))
            }
            .disabled(session.phase == .connecting || session.phase == .reconnecting)
            .accessibilityLabel(session.phase == .paused ? "再開" : "マイク")
            Button { session.requestHint() } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "lightbulb.fill")
                            .frame(width: 56, height: 56)
                            .background(MColor.tintAmber, in: Circle())
                        Text("\(session.hintsRemaining)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(MColor.amber, in: Circle())
                            .foregroundStyle(.white)
                            .offset(x: 6, y: -4)
                    }
                    Text("ヒント").font(.caption2)
                }
            }
            .disabled(session.hintsRemaining == 0)
            .accessibilityLabel("ヒント、残り\(session.hintsRemaining)回")
        }
        .foregroundStyle(MColor.ink)
        .padding(.bottom, 12)
    }

    private func micForeground(_ phase: TalkPhase) -> Color {
        switch phase {
        case .listening: return MColor.onGreen
        case .aiSpeaking, .paused, .connecting, .reconnecting: return MColor.inkSecondary
        default: return MColor.green
        }
    }

    private func micBackground(_ phase: TalkPhase) -> Color {
        switch phase {
        case .listening: return MColor.green
        case .aiSpeaking: return MColor.fill
        default: return MColor.surface
        }
    }

    private func hintCard(_ hint: HintPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint.title).font(.caption.weight(.semibold)).foregroundStyle(MColor.amber)
            Text(hint.prompt).font(.body)
            ForEach(hint.choices, id: \.self) { choice in
                Text(choice)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if let starter = hint.starter {
                Text("こう言いはじめてみましょう").font(.caption).foregroundStyle(MColor.inkSecondary)
                Text(starter).font(.title3.bold())
            }
            Text(hint.stage >= 2 ? "タップせずに、声で答えてください" : "ヒントを使っても減点されません")
                .font(.caption2)
                .foregroundStyle(MColor.inkTertiary)
        }
        .padding(MSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.tintAmber, in: RoundedRectangle(cornerRadius: MRadius.card))
        .accessibilityElement(children: .combine)
    }

    private func end() async {
        guard let session else { return }
        let result = await session.finish()
        model.settings.captionsOn = session.captionsOn
        model.addSession(result)
        model.pendingReview = result
        model.talk = nil
    }
}

struct TalkStatusStrip: View {
    var phase: TalkPhase
    var text: String
    var level: Double
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 8) {
            VoiceOrb(speaker: orb, level: level, size: 44, reduceMotion: reduceMotion)
            Text(text).font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, MSpace.l)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var orb: OrbSpeaker {
        switch phase {
        case .aiSpeaking: return .ai
        case .listening: return .learner
        case .waiting, .paused: return .thinking
        default: return .idle
        }
    }
}

struct VoiceOrb: View {
    var speaker: OrbSpeaker
    var level: Double
    var size: CGFloat
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion)) { context in
            let wave = reduceMotion ? 1.0 : 1 + 0.08 * max(level, speaker == .ai ? 0.4 : 0) * abs(sin(context.date.timeIntervalSinceReferenceDate * 3))
            ZStack {
                Circle().stroke(border, style: StrokeStyle(lineWidth: speaker == .thinking ? 2 : 0, dash: speaker == .thinking ? [4, 3] : []))
                Circle().fill(fill).padding(speaker == .thinking ? 4 : 0)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(glyph)
            }
            .frame(width: size, height: size)
            .scaleEffect(speaker == .ai && !reduceMotion ? wave : 1)
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch speaker {
        case .ai: return MColor.apricot
        case .learner: return MColor.green
        case .thinking: return MColor.surface
        case .idle: return MColor.fill
        }
    }
    private var border: Color { speaker == .thinking ? MColor.inkTertiary : .clear }
    private var glyph: Color { speaker == .learner || speaker == .ai ? MColor.onGreen : MColor.inkSecondary }
    private var symbol: String {
        switch speaker {
        case .ai: return "waveform"
        case .learner: return "waveform"
        case .thinking: return "ellipsis"
        case .idle: return "hourglass"
        }
    }
}

struct TranscriptList: View {
    var book: TranscriptBook
    var hint: HintPresentation?
    @State private var pinnedToBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(book.ordered) { utterance in
                        TranscriptBubble(utterance: utterance).id(utterance.id)
                    }
                    if let hint {
                        Text(hint.title).font(.caption.weight(.semibold)).foregroundStyle(MColor.amber).frame(maxWidth: .infinity, alignment: .leading)
                        Text(hint.prompt).frame(maxWidth: .infinity, alignment: .leading)
                            .id("hint")
                    }
                }
                .padding(MSpace.l)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: book.ordered.count) { _, _ in
                if pinnedToBottom, let last = book.ordered.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

struct TranscriptBubble: View {
    var utterance: Utterance

    var body: some View {
        let mine = utterance.speaker == .learner
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(mine ? "あなた" : "Mouthy").font(.caption).foregroundStyle(MColor.inkTertiary)
                Text(utterance.text.isEmpty ? " " : utterance.text)
                    .font(.body)
                    .foregroundStyle(utterance.state == .partial || utterance.state == .pending || utterance.state == .streaming ? MColor.inkTertiary : MColor.ink)
                    .padding(12)
                    .background(mine ? MColor.tintGreen : MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
                    .overlay {
                        if utterance.state == .pending || utterance.state == .failed {
                            RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        } else if mine {
                            RoundedRectangle(cornerRadius: MRadius.card).stroke(MColor.green.opacity(0.45), lineWidth: 1)
                        }
                    }
            }
            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: 40) }
        }
        .accessibilityLabel("\(mine ? "あなた" : "Mouthy")：\(utterance.text)")
    }
}

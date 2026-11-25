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
                    VStack(spacing: 10) {
                        PakuStage(speaker: session.orbSpeaker, level: session.audioLevel, size: 112)
                        TalkStatusPill(phase: session.phase, text: session.statusText, level: session.audioLevel)
                    }
                    .padding(.top, 4)
                    TranscriptList(book: session.book, hint: session.hint)
                } else {
                    TalkStatusPill(phase: session.phase, text: session.statusText, level: session.audioLevel)
                        .padding(.top, 4)
                    Spacer()
                    PakuStage(speaker: session.orbSpeaker, level: session.audioLevel, size: 220)
                    Text(launch.diagnostic ? "パク" : "パク（\(launch.scene.roleJa)）")
                        .font(.footnote)
                        .foregroundStyle(MColor.inkSecondary)
                        .padding(.top, 12)
                    Spacer()
                    if let hint = session.hint {
                        HintCard(hint: hint).padding(.horizontal, MSpace.l)
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "captions.bubble")
                                .foregroundStyle(MColor.inkSecondary)
                                .accessibilityHidden(true)
                            Text("字幕はオフです。会話の記録は、振り返りでいつでも読めます。")
                                .font(.footnote)
                                .foregroundStyle(MColor.inkSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(MSpace.m)
                        .background(MColor.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, MSpace.l)
                    }
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
                Text(launch.diagnostic ? "3分レベル診断" : launch.scene.title).font(.mRounded(.headline))
                if launch.diagnostic {
                    Text("これは点数ではなく、スタート地点を知るための会話です")
                        .font(.caption2)
                        .foregroundStyle(MColor.inkSecondary)
                }
            }
            Spacer()
            Text(clock).font(.mRounded(.headline)).monospacedDigit().foregroundStyle(MColor.inkSecondary)
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
                        .foregroundStyle(session.captionsOn ? MColor.coralInk : MColor.inkSecondary)
                        .background(session.captionsOn ? MColor.tintCoral : MColor.fill, in: Circle())
                    Text(session.captionsOn ? "字幕オン" : "字幕オフ").font(.system(.caption2, design: .rounded, weight: .bold))
                }
            }
            .accessibilityLabel(session.captionsOn ? "字幕オン" : "字幕オフ")
            Button { session.togglePause() } label: {
                Image(systemName: session.phase == .paused ? "mic.slash.fill" : "mic.fill")
                    .font(.title)
                    .frame(width: 84, height: 84)
                    .foregroundStyle(micForeground(session.phase))
                    .background(micBackground(session.phase), in: Circle())
                    .overlay(Circle().stroke(MColor.user, lineWidth: session.phase == .waiting ? 2 : 0))
                    .shadow(color: session.phase == .listening ? MColor.user.opacity(0.35) : .clear, radius: 10)
            }
            .disabled(session.phase == .connecting || session.phase == .reconnecting)
            .accessibilityLabel(session.phase == .paused ? "再開" : "マイク")
            Button { session.requestHint() } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "lightbulb.fill")
                            .frame(width: 56, height: 56)
                            .foregroundStyle(MColor.hintInk)
                            .background(MColor.tintHint, in: Circle())
                        Text("\(session.hintsRemaining)")
                            .font(.system(.caption2, design: .rounded, weight: .heavy))
                            .padding(4)
                            .background(MColor.sun, in: Circle())
                            .foregroundStyle(MColor.onCoral)
                            .offset(x: 6, y: -4)
                    }
                    Text("ヒント").font(.system(.caption2, design: .rounded, weight: .bold))
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
        case .listening: return MColor.surface
        case .aiSpeaking, .paused, .connecting, .reconnecting: return MColor.inkSecondary
        default: return MColor.user
        }
    }

    private func micBackground(_ phase: TalkPhase) -> Color {
        switch phase {
        case .listening: return MColor.user
        case .aiSpeaking: return MColor.tintCoral
        default: return MColor.surface
        }
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

/// The state pill under Paku: 「パクが話しています」 / 「聞いています」 / 「考えている間は待ちます」.
struct TalkStatusPill: View {
    var phase: TalkPhase
    var text: String
    var level: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(.footnote, design: .rounded, weight: .bold))
            if phase == .listening {
                LevelBars(level: level)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch phase {
        case .aiSpeaking: return "speaker.wave.2.fill"
        case .listening: return "mic.fill"
        case .waiting: return "hourglass"
        case .paused: return "pause.fill"
        default: return "ellipsis"
        }
    }

    private var foreground: Color {
        switch phase {
        case .aiSpeaking: return MColor.coralInk
        case .listening: return MColor.user
        default: return MColor.inkSecondary
        }
    }

    private var background: Color {
        switch phase {
        case .aiSpeaking: return MColor.tintCoral
        case .listening: return MColor.tintUser
        default: return MColor.fill
        }
    }
}

/// Small live level meter used while the learner is speaking.
struct LevelBars: View {
    var level: Double
    private static let weights: [Double] = [0.5, 0.8, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: 4 + 10 * CGFloat(min(1, max(0.15, level)) * Self.weights[index]))
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// パク replaces the old voice orb. Expression follows the conversation state.
struct PakuStage: View {
    var speaker: OrbSpeaker
    var level: Double
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(disc)
            PakuView(expression: expression, width: size * (expression == .think ? 0.74 : 0.8), level: level, animated: speaker == .ai)
                .offset(y: expression == .think ? -size * 0.02 : size * 0.02)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: speaker)
        .accessibilityHidden(true)
    }

    private var expression: PakuExpression {
        switch speaker {
        case .ai: return .talk
        case .learner: return .listen
        case .thinking: return .think
        case .idle: return .hello
        }
    }

    private var disc: Color {
        switch speaker {
        case .ai: return MColor.tintCoral
        case .learner: return MColor.tintUser
        case .thinking, .idle: return MColor.fill
        }
    }
}

/// Hint card (ヒント1〜3). Used in the transcript and when captions are off.
struct HintCard: View {
    var hint: HintPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(hint.title, systemImage: "lightbulb")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(MColor.hintInk)
            Text(hint.prompt).font(.body.weight(.semibold)).foregroundStyle(MColor.ink)
            if !hint.choices.isEmpty {
                FlowChoices(choices: hint.choices)
            }
            if let starter = hint.starter {
                Text("こう言いはじめてみましょう").font(.caption).foregroundStyle(MColor.inkSecondary)
                Text(starter).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(MColor.ink)
            }
            Text(hint.stage >= 2 ? "タップせずに、声で答えてください" : "ヒントを使っても減点されません")
                .font(.caption2)
                .foregroundStyle(MColor.inkTertiary)
        }
        .padding(MSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.tintHint, in: RoundedRectangle(cornerRadius: MRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MRadius.card, style: .continuous).stroke(MColor.sun.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct FlowChoices: View {
    var choices: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(choices, id: \.self) { choice in
            Text(choice)
                .font(.callout)
                .foregroundStyle(MColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MColor.surface, in: Capsule())
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
                        HintCard(hint: hint)
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
                HStack(spacing: 4) {
                    if !mine {
                        Circle().fill(MColor.coral).frame(width: 6, height: 6)
                    }
                    Text(mine ? "あなた" : "パク")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(mine ? MColor.user : MColor.coralInk)
                }
                Text(utterance.text.isEmpty ? " " : utterance.text)
                    .font(.body)
                    .foregroundStyle(utterance.state == .partial || utterance.state == .pending || utterance.state == .streaming ? MColor.inkTertiary : MColor.ink)
                    .padding(12)
                    .background(mine ? MColor.tintUser : MColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if utterance.state == .pending || utterance.state == .failed {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        } else if mine {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MColor.user.opacity(utterance.state == .partial ? 0.9 : 0.25), lineWidth: utterance.state == .partial ? 2 : 1)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MColor.coral.opacity(0.35), lineWidth: 1)
                        }
                    }
            }
            .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: 40) }
        }
        .accessibilityLabel("\(mine ? "あなた" : "パク")：\(utterance.text)")
    }
}

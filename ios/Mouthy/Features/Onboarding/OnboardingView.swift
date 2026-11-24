import AuthenticationServices
import AVFoundation
import SwiftUI
import MouthyLogic

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var agreed = false
    @State private var showPolicy = false
    @State private var micDenied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                ProgressView(value: Double(step + 1), total: 4)
                    .tint(MColor.green)
                    .padding(.horizontal, MSpace.l)
                    .padding(.top, 8)
                Text("\(step + 1)/4")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MColor.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MSpace.l)
                    .padding(.top, 6)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MSpace.l) {
                    switch step {
                    case 0: welcome
                    case 1: goals
                    default: consent
                    }
                }
                .padding(MSpace.l)
            }
            VStack(spacing: MSpace.m) {
                if step == 0 {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            let given = [credential.fullName?.familyName, credential.fullName?.givenName].compactMap { $0 }.joined()
                            model.profile.appleUserID = credential.user
                            if !given.isEmpty { model.profile.name = given }
                            model.save()
                        }
                        step = 1
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: MRadius.button))
                    Button("あとで登録する") { step = 1 }
                        .buttonStyle(MouthyButtonStyle(kind: .secondary))
                } else if step == 1 {
                    Button("次へ") { step = 2 }
                        .buttonStyle(MouthyButtonStyle())
                } else {
                    Button("マイクを許可する") { requestMic() }
                        .buttonStyle(MouthyButtonStyle())
                        .disabled(!agreed)
                    if micDenied {
                        Text("マイクがないと、音声の会話はできません。")
                            .font(.footnote)
                            .foregroundStyle(MColor.inkSecondary)
                        Button("設定アプリを開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(MouthyButtonStyle(kind: .secondary))
                        Button("台本で診断の流れを見る") { startDiagnosis() }
                            .buttonStyle(MouthyButtonStyle(kind: .ghost))
                    }
                }
            }
            .padding(MSpace.l)
        }
        .mouthyScreen()
        .sheet(isPresented: $showPolicy) { policy }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: MSpace.l) {
            Text("完璧より、\n伝わる英語。")
                .font(.largeTitle.bold())
            Text("AIが聞き役と進行役。\nあなたは、話すことに集中するだけ。")
                .font(.title3)
                .foregroundStyle(MColor.inkSecondary)
            feature("bubble.left.and.bubble.right.fill", "AIが質問でリード", "話題を考えなくていい。答えやすい質問から順に聞きます")
            feature("hourglass", "詰まっても大丈夫", "黙っても急かしません。3段階のヒントで背中を押します")
            feature("chart.line.uptrend.xyaxis", "伸びが見える", "伝わった割合・話す速さ・正確さの推移を毎回記録")
        }
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: MSpace.l) {
            Text("英語で話したいのは\nどんな場面ですか？")
                .font(.title.bold())
            Text("おすすめのシーンを選ぶのに使います。あとで変えられます。")
                .font(.callout)
                .foregroundStyle(MColor.inkSecondary)
            choiceGrid(PracticeGoal.allCases.map { $0.title }, selected: model.profile.goal.title) { title in
                if let goal = PracticeGoal.allCases.first(where: { $0.title == title }) {
                    model.profile.goal = goal
                }
            }
            Text("TOEICの目安")
                .font(.headline)
            Text("L&Rの点数で大丈夫です。受けていなければ「なし」を選んでください。")
                .font(.footnote)
                .foregroundStyle(MColor.inkSecondary)
            choiceGrid(ToeicBand.allCases.map { $0.title }, selected: model.profile.toeic.title) { title in
                if let band = ToeicBand.allCases.first(where: { $0.title == title }) {
                    model.profile.toeic = band
                }
            }
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: MSpace.l) {
            Text("声で会話します")
                .font(.title.bold())
            Text("はじめる前に、音声の扱いを確認してください。")
                .foregroundStyle(MColor.inkSecondary)
            consentRow("waveform", "音声は会話中だけ送信", "あなたの声は、AIの応答のために音声AI事業者（OpenAI 仮）に送られます。")
            consentRow("mic.slash", "録音は保存しません", "既定では録音を残しません。残るのは文字起こしとスコアだけです。")
            consentRow("trash", "いつでも削除できます", "設定から、履歴の書き出しとアカウントの削除ができます。")
            Button {
                agreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .foregroundStyle(MColor.green)
                    Text("内容を確認し、プライバシーポリシーに同意します")
                        .font(.callout)
                        .foregroundStyle(MColor.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            Button("プライバシーポリシー") { showPolicy = true }
                .font(.footnote.weight(.semibold))
        }
    }

    private var policy: some View {
        NavigationStack {
            ScrollView {
                Text("これは下書きです。法務確認の前の説明で、公開用の文面ではありません。会話中の音声は応答のために OpenAI に送られ、このアプリは録音を保存しません。残るのは端末の中の文字起こしとスコアです。アカウントの削除で、その記録は消えます。")
                    .font(.body)
                    .padding()
            }
            .navigationTitle("プライバシーポリシー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showPolicy = false } } }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(MColor.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.footnote).foregroundStyle(MColor.inkSecondary)
            }
        }
    }

    private func consentRow(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(MColor.apricot).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.footnote).foregroundStyle(MColor.inkSecondary)
            }
        }
    }

    private func choiceGrid(_ titles: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(spacing: 8) {
            ForEach(titles, id: \.self) { title in
                Button(title) { onSelect(title) }
                    .buttonStyle(MouthyButtonStyle(kind: title == selected ? .primary : .secondary))
            }
        }
    }

    private func requestMic() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                if granted {
                    model.profile.consentVersion = "2026-11-23"
                    model.profile.consentAt = Date()
                    model.save()
                    startDiagnosis()
                } else {
                    micDenied = true
                }
            }
        }
    }

    private func startDiagnosis() {
        let scene = SceneLibrary.scene(id: "warmup-03") ?? SceneLibrary.all[0]
        model.profile.consentVersion = model.profile.consentVersion ?? "2026-11-23"
        model.profile.consentAt = model.profile.consentAt ?? Date()
        model.save()
        model.talk = TalkLaunch(scene: scene, minutes: 3, diagnostic: true)
    }
}

struct DiagnosisResultView: View {
    @Environment(AppModel.self) private var model
    var session: PracticeSession

    var body: some View {
        let start = ProgressMath.startPoint(total: session.total)
        ScrollView {
            VStack(alignment: .leading, spacing: MSpace.l) {
                Text("診断が終わりました")
                    .font(.largeTitle.bold())
                Text("あなたのスタート地点")
                    .font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("推定").font(.headline)
                    Text(start.cefr).font(.system(size: 44, weight: .bold, design: .rounded))
                }
                Text(start.message).font(.title3.bold())
                Text("いまの力に合った、答えやすいシーンからおすすめします。")
                    .foregroundStyle(MColor.inkSecondary)
                HStack(spacing: 8) {
                    scoreTile(.communication, session.communication)
                    scoreTile(.fluency, session.fluency)
                    scoreTile(.accuracy, session.accuracy)
                }
                if let wpm = session.speakingWpm {
                    Text("発話中WPM  \(wpm) 語/分").font(.footnote).foregroundStyle(MColor.inkSecondary)
                }
                Text("最初のおすすめ").font(.headline)
                ForEach(recommendations, id: \.id) { scene in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(scene.title).font(.headline)
                            Text("\(scene.category.title) · 5分").font(.caption).foregroundStyle(MColor.inkSecondary)
                        }
                        Spacer()
                        LevelBadge(level: scene.level)
                    }
                    .padding(MSpace.l)
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.card))
                }
                Button("ホームへ") {
                    model.profile.estimatedLevel = start.level
                    model.profile.cefr = start.cefr
                    model.profile.sawDiagnosis = true
                    model.profile.onboardingComplete = true
                    model.finishedSession = nil
                    model.save()
                }
                .buttonStyle(MouthyButtonStyle())
            }
            .padding(MSpace.l)
        }
        .mouthyScreen()
    }

    private var recommendations: [SceneDef] {
        let first = model.recommendation
        let second = SceneLibrary.all.first { $0.released && $0.id != first.id && $0.category == .career } ?? first
        return [first, second]
    }

    private func scoreTile(_ axis: ScoreAxis, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(axis.title).font(.caption).foregroundStyle(MColor.inkSecondary)
            Text("×\(Int(axis.weight * 100))%").font(.caption2).foregroundStyle(MColor.inkTertiary)
            Text("\(value)").font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MColor.surface, in: RoundedRectangle(cornerRadius: MRadius.list))
    }
}

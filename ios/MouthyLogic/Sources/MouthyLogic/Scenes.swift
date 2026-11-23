import Foundation

public enum SceneCategory: String, CaseIterable, Codable, Sendable {
    case warmup, daily, travel, food, shop, office, meeting, career, phone, opinion

    public var title: String {
        switch self {
        case .warmup: return "ウォームアップ・自己紹介"
        case .daily: return "日常・友人"
        case .travel: return "旅行・移動"
        case .food: return "ホテル・飲食"
        case .shop: return "買い物・生活サービス"
        case .office: return "職場・同僚"
        case .meeting: return "会議・プレゼン"
        case .career: return "面接・キャリア"
        case .phone: return "電話・交渉・顧客対応"
        case .opinion: return "意見・ディスカッション"
        }
    }

    public var chip: String {
        switch self {
        case .warmup: return "ウォームアップ"
        case .daily: return "日常"
        case .travel: return "旅行"
        case .food: return "飲食"
        case .shop: return "買い物"
        case .office: return "職場"
        case .meeting: return "会議"
        case .career: return "面接"
        case .phone: return "電話"
        case .opinion: return "意見"
        }
    }

    public var symbol: String {
        switch self {
        case .warmup: return "hand.wave"
        case .daily: return "cup.and.saucer"
        case .travel: return "airplane"
        case .food: return "fork.knife"
        case .shop: return "bag"
        case .office: return "building.2"
        case .meeting: return "person.2.wave.2"
        case .career: return "briefcase"
        case .phone: return "phone"
        case .opinion: return "bubble.left.and.bubble.right"
        }
    }

    /// 既存のトークンAPIが受け付けるロール。シーンの台本は extraInstructions に載せる。
    public var legacyScenarioId: String {
        switch self {
        case .career: return "interview"
        case .office, .meeting, .phone: return "business"
        case .travel, .food, .shop: return "travel"
        case .daily, .opinion: return "daily"
        case .warmup: return "warmup"
        }
    }
}

public struct Checkpoint: Equatable, Sendable {
    public var titleJa: String
    public var questions: [String]
}

public struct KeyPhrase: Equatable, Sendable {
    public var en: String
    public var ja: String
}

public struct SceneDef: Equatable, Identifiable, Sendable {
    public var id: String
    public var category: SceneCategory
    public var title: String
    public var level: Int
    public var roleJa: String
    public var roleEn: String
    public var goalJa: String
    public var goalEn: String
    public var checkpoints: [Checkpoint]
    public var phrases: [KeyPhrase]
    public var released: Bool

    public var cefrLabel: String {
        switch level {
        case 1: return "A2+"
        case 3: return "B1+〜B2"
        default: return "B1"
        }
    }

    public var levelId: String {
        switch level {
        case 1: return "beginner"
        case 3: return "advanced"
        default: return "intermediate"
        }
    }
}

public enum PracticeGoal: String, CaseIterable, Codable, Sendable {
    case interview, work, travel, daily, phone, opinion

    public var title: String {
        switch self {
        case .interview: return "面接・就活"
        case .work: return "会議・仕事"
        case .travel: return "旅行"
        case .daily: return "日常会話"
        case .phone: return "電話・交渉"
        case .opinion: return "意見を言う"
        }
    }

    public var category: SceneCategory {
        switch self {
        case .interview: return .career
        case .work: return .meeting
        case .travel: return .travel
        case .daily: return .daily
        case .phone: return .phone
        case .opinion: return .opinion
        }
    }
}

public enum ToeicBand: String, CaseIterable, Codable, Sendable {
    case under495, band500, band600, band700, unknown

    public var title: String {
        switch self {
        case .under495: return "〜495点"
        case .band500: return "500〜595点"
        case .band600: return "600〜695点"
        case .band700: return "700点以上"
        case .unknown: return "なし・わからない"
        }
    }
}

public enum SceneLibrary {
    public static let comingSoonMessage = "v1.1で追加予定"
    public static let all: [SceneDef] = SceneCatalog.make()

    public static func scene(id: String) -> SceneDef? {
        all.first { $0.id == id }
    }

    public static func releasedCount(in category: SceneCategory) -> Int {
        all.filter { $0.category == category && $0.released }.count
    }

    public static func recommend(goal: PracticeGoal, completedSceneIds: Set<String>) -> SceneDef {
        let preferred = all.filter { $0.released && $0.category == goal.category && !completedSceneIds.contains($0.id) }
        if let first = preferred.first { return first }
        let anyOpen = all.filter { $0.released && !completedSceneIds.contains($0.id) }
        return anyOpen.first ?? all.first { $0.released } ?? all[0]
    }

    public static func instructionBlock(for scene: SceneDef, checkpointIndex: Int) -> String {
        let index = min(max(checkpointIndex, 0), max(scene.checkpoints.count - 1, 0))
        let current = scene.checkpoints.isEmpty ? nil : scene.checkpoints[index]
        var lines = [
            "Scene: \(scene.title).",
            "Stay in this role: \(scene.roleEn).",
            "Learner goal: \(scene.goalEn).",
            "Move through these checkpoints, one question at a time:",
        ]
        for (offset, checkpoint) in scene.checkpoints.enumerated() {
            let mark = offset == index ? "NOW" : (offset < index ? "done" : "later")
            let question = checkpoint.questions.first ?? checkpoint.titleJa
            lines.append("- [\(mark)] \(question)")
        }
        if let current, current.questions.count > 1 {
            lines.append("If the answer is short, use an easier question: \(current.questions.dropFirst().joined(separator: " / "))")
        }
        lines.append("With about one minute left, summarize one thing you heard and ask one light closing question.")
        let text = lines.joined(separator: "\n")
        if text.count <= 1800 { return text }
        return String(text.prefix(1800))
    }
}

enum SceneCatalog {
    static func make() -> [SceneDef] {
        var scenes: [SceneDef] = []
        for (category, rows) in rows {
            for (index, row) in rows.enumerated() {
                let number = index + 1
                let released = number <= 3
                let id = "\(category.rawValue)-\(String(format: "%02d", number))"
                scenes.append(SceneDef(
                    id: id,
                    category: category,
                    title: row.title,
                    level: row.level,
                    roleJa: row.role,
                    roleEn: roleEn(category: category, roleJa: row.role),
                    goalJa: row.goal,
                    goalEn: row.goal,
                    checkpoints: released ? checkpoints(title: row.title) : [],
                    phrases: released ? phrases(level: row.level) : [],
                    released: released
                ))
            }
        }
        return scenes
    }

    private static func roleEn(category: SceneCategory, roleJa: String) -> String {
        "a \(roleJa) in a \(category.title) role-play with a Japanese learner of English"
    }

    private static func checkpoints(title: String) -> [Checkpoint] {
        [
            Checkpoint(titleJa: "切り出す", questions: ["Let's start with \(title). Can you say it in one sentence?"]),
            Checkpoint(titleJa: "理由", questions: ["Why is that?", "Is it mostly because of the people, or the work?"]),
            Checkpoint(titleJa: "具体例", questions: ["Can you give me one example?", "Was that recently, yes or no?"]),
            Checkpoint(titleJa: "質問を返す", questions: ["What would you like to ask me?"]),
        ]
    }

    private static func phrases(level: Int) -> [KeyPhrase] {
        if level <= 1 {
            return [
                KeyPhrase(en: "I'd like to ...", ja: "〜したいです"),
                KeyPhrase(en: "For example, ...", ja: "たとえば、〜"),
                KeyPhrase(en: "Could you ...?", ja: "〜してもらえますか"),
            ]
        }
        return [
            KeyPhrase(en: "I'm interested in ... because ...", ja: "〜なので、〜に興味があります"),
            KeyPhrase(en: "For example, ...", ja: "たとえば、〜"),
            KeyPhrase(en: "In my view, ...", ja: "私の考えでは、〜"),
        ]
    }

    private struct Row {
        var title: String
        var level: Int
        var role: String
        var goal: String
    }

    private static let rows: [(SceneCategory, [Row])] = [
        (.warmup, [
            Row(title: "初対面の自己紹介", level: 1, role: "パーティーで会った人", goal: "名前・出身・仕事を3文以上で伝え、相手に1つ質問する"),
            Row(title: "今日の出来事", level: 1, role: "聞き役の友人", goal: "今日あったことを時系列で3つ話す"),
            Row(title: "週末の予定", level: 1, role: "同僚", goal: "週末の予定と理由を伝える"),
            Row(title: "好きな食べ物", level: 1, role: "料理好きの友人", goal: "好きな料理と理由を話し、作り方を1つ説明する"),
            Row(title: "趣味の話", level: 1, role: "趣味の合う知人", goal: "趣味を始めたきっかけと魅力を話す"),
            Row(title: "地元の紹介", level: 2, role: "日本に興味がある旅行者", goal: "地元の名所を2つ、理由つきですすめる"),
            Row(title: "最近見た映画・ドラマ", level: 2, role: "映画好きの友人", goal: "あらすじと感想を話す"),
            Row(title: "子どもの頃の思い出", level: 2, role: "聞き役", goal: "過去形で思い出を1つ語り切る"),
            Row(title: "今年の目標", level: 2, role: "コーチ", goal: "目標と具体的な行動を2つ話す"),
            Row(title: "1分スピーチ：最近の気づき", level: 3, role: "スピーチ練習の聞き手", goal: "1分話し続け、追加の質問に答える"),
        ]),
        (.daily, [
            Row(title: "カフェでの雑談", level: 1, role: "友人", goal: "最近ハマっていることを話し、会話を5往復続ける"),
            Row(title: "予定を合わせる", level: 1, role: "友人", goal: "候補日を2つ出して約束を決める"),
            Row(title: "おすすめを聞く", level: 1, role: "地元の友人", goal: "店を1つ教えてもらい、追加で質問する"),
            Row(title: "近所の人との立ち話", level: 1, role: "隣人", goal: "天気や近況で会話を3往復続ける"),
            Row(title: "お誘いを断る", level: 2, role: "友人", goal: "理由を添えてやわらかく断り、代案を出す"),
            Row(title: "ホームパーティー", level: 2, role: "ホスト", goal: "お礼と料理の感想を伝え、自分の話をする"),
            Row(title: "ルームメイトとのルール決め", level: 2, role: "ルームメイト", goal: "家事の分担を提案して合意する"),
            Row(title: "ジム・習い事の体験", level: 2, role: "インストラクター", goal: "目的と経験を伝え、質問を1つする"),
            Row(title: "悩み相談にのる", level: 3, role: "相談してくる友人", goal: "共感を示し、アドバイスを1つする"),
            Row(title: "日本文化の説明", level: 3, role: "日本に来た友人", goal: "お正月などの行事を説明し、質問に答える"),
        ]),
        (.travel, [
            Row(title: "入国審査", level: 1, role: "入国審査官", goal: "滞在の目的・期間・滞在先に答える"),
            Row(title: "空港チェックイン", level: 1, role: "航空会社スタッフ", goal: "荷物と座席の希望を伝える"),
            Row(title: "道を尋ねる", level: 1, role: "通行人", goal: "目的地への行き方を聞き、復唱して確認する"),
            Row(title: "タクシー", level: 1, role: "運転手", goal: "行き先と到着希望時刻を伝える"),
            Row(title: "乗り継ぎで迷う", level: 2, role: "空港スタッフ", goal: "乗り継ぎゲートへの行き方と所要時間を聞く"),
            Row(title: "電車の切符と乗り換え", level: 2, role: "駅員", goal: "最適な切符と乗り換えを確認する"),
            Row(title: "観光案内所", level: 2, role: "案内所スタッフ", goal: "半日の観光プランを相談して決める"),
            Row(title: "ツアーの申し込み", level: 2, role: "ツアー会社の担当", goal: "日程・料金・集合場所を確認して申し込む"),
            Row(title: "レンタカーを借りる", level: 3, role: "レンタカー店員", goal: "保険と返却条件を確認して契約する"),
            Row(title: "遅延・欠航の振替", level: 3, role: "航空会社カウンター", goal: "代替便と補償を交渉する"),
        ]),
        (.food, [
            Row(title: "ホテルのチェックイン", level: 1, role: "フロント係", goal: "予約を確認し、朝食の時間を聞く"),
            Row(title: "料理を注文する", level: 1, role: "ウェイター", goal: "料理と飲み物を注文し、おすすめを聞く"),
            Row(title: "カフェでカスタム注文", level: 1, role: "バリスタ", goal: "サイズや好みを伝えて注文する"),
            Row(title: "お会計・割り勘", level: 1, role: "ウェイター", goal: "別会計を頼み、チップの扱いを確認する"),
            Row(title: "部屋のトラブル", level: 2, role: "フロント係", goal: "エアコンの故障を伝え、対応を頼む"),
            Row(title: "レストラン予約の電話", level: 2, role: "店員", goal: "日時・人数・要望を伝えて予約する"),
            Row(title: "アレルギーを伝える", level: 2, role: "ウェイター", goal: "アレルギーを伝え、代わりの料理を選ぶ"),
            Row(title: "注文と違う料理", level: 2, role: "ウェイター", goal: "丁寧に指摘して交換を頼む"),
            Row(title: "同僚とランチ", level: 2, role: "同僚", goal: "メニューを相談しながら雑談を続ける"),
            Row(title: "取引先との会食", level: 3, role: "取引先の担当者", goal: "相手の話を引き出し、自社を短く紹介する"),
        ]),
        (.shop, [
            Row(title: "服のサイズを探す", level: 1, role: "店員", goal: "サイズと色を伝え、試着を頼む"),
            Row(title: "スーパーで探し物", level: 1, role: "店員", goal: "売り場を聞き、代わりの商品を相談する"),
            Row(title: "薬局で相談", level: 1, role: "薬剤師", goal: "症状を伝えて薬を選ぶ"),
            Row(title: "返品・交換", level: 2, role: "店員", goal: "理由を説明して返品か交換を決める"),
            Row(title: "家電の比較相談", level: 2, role: "家電量販店の店員", goal: "2製品の違いを質問して選ぶ"),
            Row(title: "郵便局で荷物を送る", level: 2, role: "郵便局員", goal: "配送方法と料金を比べて送る"),
            Row(title: "携帯SIMの契約", level: 2, role: "ショップ店員", goal: "プランを比較して契約する"),
            Row(title: "病院で症状を説明", level: 2, role: "受付・医師", goal: "症状と期間、困っていることを伝える"),
            Row(title: "銀行口座を開く", level: 3, role: "銀行員", goal: "必要書類と手数料を確認する"),
            Row(title: "部屋探しの内見", level: 3, role: "不動産エージェント", goal: "条件を伝え、契約条件を質問する"),
        ]),
        (.office, [
            Row(title: "初出勤のあいさつ", level: 1, role: "新しいチームの同僚", goal: "自己紹介と担当業務を説明する"),
            Row(title: "朝の雑談", level: 1, role: "同僚", goal: "週末の話で会話を4往復続ける"),
            Row(title: "指示を確認する", level: 1, role: "先輩", goal: "指示の不明点を2つ確認する"),
            Row(title: "仕事を頼む", level: 2, role: "同僚", goal: "期限と理由を添えて依頼する"),
            Row(title: "依頼の期限を調整", level: 2, role: "上司", goal: "優先順位を確認し、期限の調整を交渉する"),
            Row(title: "進捗報告", level: 2, role: "上司", goal: "完了・課題・次の一手を順に報告する"),
            Row(title: "新メンバーへの説明", level: 2, role: "新入社員", goal: "業務の手順を順番に説明する"),
            Row(title: "社内イベントの雑談", level: 2, role: "他部署の社員", goal: "自分の仕事を紹介し、相手の仕事を聞く"),
            Row(title: "ミスの報告と謝罪", level: 3, role: "上司", goal: "事実・原因・対策を伝える"),
            Row(title: "1on1", level: 3, role: "マネージャー", goal: "成果と悩みを話し、支援を求める"),
        ]),
        (.meeting, [
            Row(title: "会議での自己紹介", level: 1, role: "会議の司会", goal: "名前と役割を20秒で話す"),
            Row(title: "聞き返し・確認", level: 1, role: "発表者", goal: "聞き取れない点を丁寧に聞き返す"),
            Row(title: "オンライン会議のトラブル", level: 1, role: "参加者", goal: "音声の不調を伝えて対処する"),
            Row(title: "意見を求められる", level: 2, role: "司会", goal: "賛否と理由を1つ述べる"),
            Row(title: "議事のまとめ", level: 2, role: "チームメンバー", goal: "決定事項と担当者を確認する"),
            Row(title: "ブレインストーミング", level: 2, role: "ファシリテーター", goal: "アイデアを2つ出し、1つを補足する"),
            Row(title: "反対意見を伝える", level: 3, role: "同僚", goal: "角を立てずに懸念と代案を出す"),
            Row(title: "3分プレゼン", level: 3, role: "聴衆", goal: "結論、理由、例の順で説明する"),
            Row(title: "プレゼン後のQ&A", level: 3, role: "質問者", goal: "想定外の質問に答える。分からないときの返し方も使う"),
            Row(title: "データを説明する", level: 3, role: "上司", goal: "グラフの傾向と原因を説明する"),
        ]),
        (.career, [
            Row(title: "面接の自己紹介", level: 1, role: "面接官", goal: "1分で経歴を話す"),
            Row(title: "志望動機", level: 2, role: "面接官", goal: "なぜこの会社と職種なのかを話す"),
            Row(title: "強みと弱み", level: 2, role: "面接官", goal: "強みを具体例で、弱みを改善策つきで話す"),
            Row(title: "学生時代に力を入れたこと", level: 2, role: "面接官", goal: "状況・課題・行動・結果の順で経験を語る"),
            Row(title: "逆質問", level: 2, role: "面接官", goal: "面接官に質問を2つする"),
            Row(title: "業界イベントでのネットワーキング", level: 2, role: "イベント参加者", goal: "自己紹介し、連絡先の交換までつなげる"),
            Row(title: "外資系インターン面接", level: 3, role: "外資系金融の面接官", goal: "業界の志望理由と、最近の市場ニュースへの意見を話す"),
            Row(title: "失敗談を聞かれる", level: 3, role: "面接官", goal: "失敗と学びを具体的に語る"),
            Row(title: "ケース面接入門", level: 3, role: "コンサルの面接官", goal: "簡単な推定問題で、考えを声に出して進める"),
            Row(title: "条件のすり合わせ", level: 3, role: "人事担当", goal: "条件を確認し、希望を伝える"),
        ]),
        (.phone, [
            Row(title: "電話の取り次ぎ", level: 1, role: "取引先の担当者", goal: "担当者の不在を伝え、伝言を受ける"),
            Row(title: "留守電を残す", level: 1, role: "留守番電話", goal: "用件と折り返し先を30秒で残す"),
            Row(title: "予約の変更", level: 2, role: "受付係", goal: "日時の変更を依頼する"),
            Row(title: "サポートへの問い合わせ", level: 2, role: "カスタマーサポート", goal: "不具合を説明し、解決策を得る"),
            Row(title: "見積もりの依頼", level: 2, role: "業者の担当者", goal: "条件を伝えて見積もりを依頼する"),
            Row(title: "価格交渉", level: 3, role: "販売担当", goal: "値引きか条件の改善を引き出す"),
            Row(title: "納期の交渉", level: 3, role: "サプライヤー", goal: "遅延の理由を聞き、代替案で合意する"),
            Row(title: "初回の商談", level: 3, role: "見込み客", goal: "課題を聞き出し、提案につなげる"),
            Row(title: "契約条件の確認", level: 3, role: "取引先の法務担当", goal: "不明点を質問し、合意点をまとめる"),
            Row(title: "クレーム対応", level: 3, role: "怒っている顧客", goal: "謝罪し、事実を確認して解決策を示す"),
        ]),
        (.opinion, [
            Row(title: "好きか嫌いか", level: 1, role: "友人", goal: "理由を1つ添えて意見を言う"),
            Row(title: "おすすめの本・アプリ", level: 1, role: "友人", goal: "理由つきで1つすすめる"),
            Row(title: "リモートワークの賛否", level: 2, role: "同僚", goal: "立場と理由を2つ述べる"),
            Row(title: "AIと仕事", level: 2, role: "ディスカッション相手", goal: "自分の考えを例とともに話す"),
            Row(title: "日本と海外の働き方", level: 2, role: "海外の同僚", goal: "違いを比べて説明する"),
            Row(title: "旅行先を決める", level: 2, role: "友人", goal: "候補を比べて合意する"),
            Row(title: "留学・海外生活の相談", level: 2, role: "留学経験者", goal: "不安を伝え、質問を2つする"),
            Row(title: "ニュースについて話す", level: 3, role: "ニュース好きの友人", goal: "最近のニュースを要約し、意見を述べる"),
            Row(title: "環境問題", level: 3, role: "ディスカッション相手", goal: "対策を1つ提案し、反論に答える"),
            Row(title: "もしもの話", level: 3, role: "友人", goal: "仮定の表現で、やってみたいことを語る"),
        ]),
    ]
}

public struct ScriptedLine: Equatable, Sendable {
    public enum Who: Sendable { case ai, learner }
    public var who: Who
    public var text: String
    public var atMs: Int
}

public struct ScriptedHint: Equatable, Sendable {
    public var stage: Int
    public var prompt: String
    public var choices: [String]
    public var starter: String?
    public var atMs: Int
}

public struct ScriptedTalk: Equatable, Sendable {
    public var lines: [ScriptedLine]
    public var hint: ScriptedHint?
    public var durationMs: Int
    public var stuck: [StuckPhrase]
}

public enum TalkScript {
    public static func script(for scene: SceneDef) -> ScriptedTalk {
        let opening = scene.checkpoints.first?.questions.first ?? "How are you today?"
        return ScriptedTalk(
            lines: [
                ScriptedLine(who: .ai, text: "Hi, thanks for joining. \(opening)", atMs: 400),
                ScriptedLine(who: .learner, text: "I'm a student, and I like working with numbers and people.", atMs: 2_200),
                ScriptedLine(who: .ai, text: "Mm-hmm. Tell me a little more about that.", atMs: 4_000),
                ScriptedLine(who: .learner, text: "I join the finance club last year.", atMs: 6_200),
            ],
            hint: ScriptedHint(
                stage: 2,
                prompt: "Was that in a club, or a part-time job?",
                choices: ["In a club", "At my part-time job"],
                starter: nil,
                atMs: 8_200
            ),
            durationMs: 10_000,
            stuck: [
                StuckPhrase(id: "stuck-1", phrase: "to be honest, ...", meaningJa: "正直に言うと", reason: "6秒の間"),
            ]
        )
    }

    /// 台本の文に、会話中に出してはいけない評価語が無いことを確かめる。
    public static func linesAreSafe(_ talk: ScriptedTalk) -> Bool {
        talk.lines.allSatisfy { !SpokenWords.containsBannedJudgement($0.text) }
    }
}

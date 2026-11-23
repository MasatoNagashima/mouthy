import Foundation
import Observation
import MouthyLogic

@MainActor
@Observable
final class AppModel {
    var profile: LearnerProfile
    var settings: AppSettings
    var sessions: [PracticeSession]
    var tab: AppTab = .home
    var briefScene: SceneDef?
    var briefMinutes = 5
    var talk: TalkLaunch?
    var pendingReview: PracticeSession?
    var finishedSession: PracticeSession?
    var dayKey: String?
    var toast: String?
    var loadFailed = false

    private let fileURL: URL
    private var ready = false

    init(preview: StoreFile? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Mouthy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("store.json")
        if let preview {
            profile = preview.profile
            settings = preview.settings
            sessions = preview.sessions
            ready = false
            return
        }
        if let stored = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.mouthy.decode(StoreFile.self, from: stored) {
            profile = decoded.profile
            settings = decoded.settings
            sessions = decoded.sessions
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            profile = .empty
            settings = .standard
            sessions = []
            loadFailed = true
        } else {
            profile = .empty
            settings = .standard
            sessions = []
        }
        ready = true
    }

    func reload() {
        loadFailed = false
        guard let stored = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.mouthy.decode(StoreFile.self, from: stored) else {
            if FileManager.default.fileExists(atPath: fileURL.path) { loadFailed = true }
            return
        }
        profile = decoded.profile
        settings = decoded.settings
        sessions = decoded.sessions
    }

    func save() {
        guard ready else { return }
        let payload = StoreFile(profile: profile, settings: settings, sessions: sessions)
        guard let data = try? JSONEncoder.mouthy.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func update(_ body: (AppModel) -> Void) {
        body(self)
        save()
    }

    func addSession(_ session: PracticeSession) {
        sessions.append(session)
        sessions.sort { $0.startedAt > $1.startedAt }
        save()
    }

    func session(id: String) -> PracticeSession? {
        sessions.first { $0.id == id }
    }

    func wipe() {
        profile = .empty
        settings = .standard
        sessions = []
        tab = .home
        briefScene = nil
        talk = nil
        finishedSession = nil
        dayKey = nil
        try? FileManager.default.removeItem(at: fileURL)
        save()
    }

    func exportData() -> Data {
        (try? JSONEncoder.mouthy.encode(StoreFile(profile: profile, settings: settings, sessions: sessions))) ?? Data()
    }

    var practiceDays: Set<String> {
        Set(sessions.map { StudyCalendar.dayKey($0.startedAt) })
    }

    func sessions(on key: String) -> [PracticeSession] {
        sessions.filter { StudyCalendar.dayKey($0.startedAt) == key }.sorted { $0.startedAt < $1.startedAt }
    }

    func counts(in year: Int, month: Int) -> [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions {
            let parts = StudyCalendar.tokyo().dateComponents([.year, .month], from: session.startedAt)
            guard parts.year == year, parts.month == month else { continue }
            let key = StudyCalendar.dayKey(session.startedAt)
            counts[key, default: 0] += 1
        }
        return counts
    }

    var streak: Int { StudyCalendar.streak(practiceDays: practiceDays, today: Date()) }

    var monthPracticeDays: Int {
        let parts = StudyCalendar.tokyo().dateComponents([.year, .month], from: Date())
        return Set(sessions.filter { session in
            let item = StudyCalendar.tokyo().dateComponents([.year, .month], from: session.startedAt)
            return item.year == parts.year && item.month == parts.month
        }.map { StudyCalendar.dayKey($0.startedAt) }).count
    }

    var totalTalkSeconds: Int { sessions.reduce(0) { $0 + $1.durationSec } }

    func bestScore(sceneId: String) -> Int? {
        sessions.filter { $0.sceneId == sceneId && !$0.isDiagnostic }.map(\.total).max()
    }

    var recommendation: SceneDef {
        let done = Set(sessions.filter { !$0.isDiagnostic }.map(\.sceneId))
        return SceneLibrary.recommend(goal: profile.goal, completedSceneIds: done)
    }

    func filteredSessions(filter: RecordFilter) -> [PracticeSession] {
        sessions.filter { session in
            switch filter {
            case .all: return true
            case .hasCorrections: return !session.corrections.isEmpty
            case .category(let category): return session.category == category.rawValue
            }
        }
    }

    static var preview: AppModel {
        let now = Date()
        let session = PracticeSession(
            id: "preview",
            sceneId: "career-01",
            sceneTitle: "面接の自己紹介",
            category: SceneCategory.career.rawValue,
            level: 1,
            startedAt: now,
            durationSec: 300,
            total: 68,
            delta: 4,
            communication: 72,
            fluency: 64,
            accuracy: 61,
            communicationDelta: 6,
            fluencyDelta: 3,
            accuracyDelta: 0,
            speakingWpm: 94,
            talkRatio: 0.58,
            reactionSec: 3.8,
            averageWords: 11,
            hintCount: 1,
            strength: "「I like working with numbers and people.」と、理由を2つ並べて伝えられました。",
            nextSteps: [],
            corrections: [
                ReviewCorrection(id: "c1", tag: "時制", original: "I join the finance club last year.", better: "I joined the finance club last year.", reasonJa: "去年のことなので過去形に。今も続けているなら “I’ve been in …” も使えます。"),
            ],
            stuck: [StuckPhrase(id: "s1", phrase: "to be honest, ...", meaningJa: "正直に言うと", reason: "6秒の間")],
            turns: [
                StoredTurn(id: "t1", speaker: .ai, text: "Could you tell me a little about yourself?"),
                StoredTurn(id: "t2", speaker: .learner, text: "I like working with numbers and people."),
            ],
            isDiagnostic: false,
            formulaVersion: ScoreFormula.version
        )
        let model = AppModel(preview: StoreFile(
            profile: LearnerProfile(name: "青木 遥", appleUserID: nil, goal: .interview, toeic: .band500, estimatedLevel: 1, cefr: "A2+", onboardingComplete: true, consentVersion: "2026-11-23", consentAt: now, sawDiagnosis: true),
            settings: .standard,
            sessions: [session]
        ))
        return model
    }
}

enum RecordFilter: Hashable {
    case all
    case hasCorrections
    case category(SceneCategory)
}

extension JSONEncoder {
    static var mouthy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var mouthy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

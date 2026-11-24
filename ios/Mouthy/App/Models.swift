import Foundation
import MouthyLogic

struct LearnerProfile: Codable, Equatable {
    var name: String
    var appleUserID: String?
    var goal: PracticeGoal
    var toeic: ToeicBand
    var estimatedLevel: Int?
    var cefr: String?
    var onboardingComplete: Bool
    var consentVersion: String?
    var consentAt: Date?
    var sawDiagnosis: Bool

    static let empty = LearnerProfile(
        name: "",
        appleUserID: nil,
        goal: .interview,
        toeic: .band500,
        estimatedLevel: nil,
        cefr: nil,
        onboardingComplete: false,
        consentVersion: nil,
        consentAt: nil,
        sawDiagnosis: false
    )

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ゲスト" : name }
    var initial: String { String(displayName.prefix(1)) }
}

struct AppSettings: Codable, Equatable {
    var speechSpeed: Double
    var hintDelaySec: Int
    var captionsOn: Bool
    var reminderOn: Bool
    var reminderHour: Int
    var reminderMinute: Int

    static let standard = AppSettings(
        speechSpeed: 0.9,
        hintDelaySec: 8,
        captionsOn: true,
        reminderOn: false,
        reminderHour: 21,
        reminderMinute: 0
    )

    var speedLabel: String {
        if speechSpeed < 0.95 { return "ゆっくり" }
        if speechSpeed > 1.02 { return "少し速く" }
        return "ふつう"
    }

    var reminderLabel: String {
        String(format: "毎日 %02d:%02d", reminderHour, reminderMinute)
    }
}

struct PracticeSession: Codable, Identifiable, Equatable {
    var id: String
    var sceneId: String
    var sceneTitle: String
    var category: String?
    var level: Int
    var startedAt: Date
    var durationSec: Int
    var total: Int
    var delta: Int?
    var communication: Int
    var fluency: Int
    var accuracy: Int
    var communicationDelta: Int?
    var fluencyDelta: Int?
    var accuracyDelta: Int?
    var speakingWpm: Int?
    var talkRatio: Double?
    var reactionSec: Double?
    var averageWords: Double?
    var hintCount: Int
    var strength: String
    var nextSteps: [String]
    var corrections: [ReviewCorrection]
    var stuck: [StuckPhrase]
    var turns: [StoredTurn]
    var isDiagnostic: Bool
    var formulaVersion: String

    var snapshot: SessionSnapshot {
        SessionSnapshot(
            id: id,
            sceneId: sceneId,
            startedAt: startedAt,
            total: total,
            communication: communication,
            fluency: fluency,
            accuracy: accuracy,
            speakingWpm: speakingWpm,
            talkRatio: talkRatio,
            reactionSec: reactionSec,
            averageWords: averageWords
        )
    }
}

struct StoredTurn: Codable, Identifiable, Equatable {
    var id: String
    var speaker: Speaker
    var text: String
}

struct StoreFile: Codable {
    var profile: LearnerProfile
    var settings: AppSettings
    var sessions: [PracticeSession]
}

struct TalkLaunch: Identifiable, Equatable {
    var id = UUID()
    var scene: SceneDef
    var minutes: Int
    var diagnostic: Bool
}

enum AppTab: Hashable {
    case home, scenes, records, profile
}

enum ReviewRoute: Hashable {
    case session(String)
}

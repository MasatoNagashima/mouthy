import XCTest
@testable import MouthyLogic

final class MouthyLogicTests: XCTestCase {
    func testScoreMatchesTheServerFormula() {
        let score = ScoreFormula.compute(
            levels: [.answers, .answers, .partial],
            checkpointsDone: 2,
            checkpointsTotal: 4,
            learnerAskedOrExpanded: true,
            speakingWpm: 94,
            reactionMedianMs: 3800,
            averageWordsPerTurn: 11,
            wordCount: 100,
            majorErrors: 1,
            minorErrors: 2
        )
        XCTAssertEqual(score.version, "2026-11-23")
        XCTAssertEqual(score.communication, 74)
        XCTAssertEqual(score.fluency, 85)
        XCTAssertEqual(score.accuracy, 79)
        XCTAssertEqual(score.total, 79)
    }

    func testSilenceProducesNoInventedSpeed() {
        let score = ScoreFormula.compute(
            levels: [],
            checkpointsDone: 0,
            checkpointsTotal: 4,
            learnerAskedOrExpanded: false,
            speakingWpm: nil,
            reactionMedianMs: nil,
            averageWordsPerTurn: nil,
            wordCount: 0,
            majorErrors: 0,
            minorErrors: 0
        )
        XCTAssertEqual(score.total, 0)
        XCTAssertEqual(score.fluency, 0)
        XCTAssertEqual(score.accuracy, 0)
    }

    func testTranscriptStaysInSpeechOrderWhenTheTextArrivesLate() {
        var book = TranscriptBook()
        book.beginLearner(id: "learner-1", startedAtMs: 1_000)
        book.beginAI(id: "ai-1", startedAtMs: 5_000, isHint: false)
        book.appendAI(id: "ai-1", delta: "Why banking?")
        book.finishAI(id: "ai-1")
        book.markLearnerPending(id: "learner-1", atMs: 4_000)
        book.resolveLearner(id: "learner-1", text: "I like numbers.")
        XCTAssertEqual(book.ordered.map(\.id), ["learner-1", "ai-1"])
        XCTAssertEqual(book.ordered[0].state, .final)
        XCTAssertEqual(book.ordered[0].text, "I like numbers.")
    }

    func testPendingTranscriptFailsAfterSixSeconds() {
        var book = TranscriptBook()
        book.beginLearner(id: "learner-1", startedAtMs: 0)
        book.markLearnerPending(id: "learner-1", atMs: 1_000)
        book.failOverdue(nowMs: 6_999)
        XCTAssertEqual(book.utterances[0].state, .pending)
        book.failOverdue(nowMs: 7_000)
        XCTAssertEqual(book.utterances[0].state, .failed)
        XCTAssertEqual(book.utterances[0].text, TranscriptBook.failedText)
    }

    func testHintsAdvanceEveryDelayAndDoNotSkip() {
        XCTAssertNil(HintSchedule.stage(silenceMs: 7_999, hintsAlreadyGiven: 0, delayMs: 8_000, maxHints: 3, speaking: false))
        XCTAssertEqual(HintSchedule.stage(silenceMs: 8_000, hintsAlreadyGiven: 0, delayMs: 8_000, maxHints: 3, speaking: false), 1)
        XCTAssertEqual(HintSchedule.stage(silenceMs: 16_000, hintsAlreadyGiven: 1, delayMs: 8_000, maxHints: 3, speaking: false), 2)
        XCTAssertNil(HintSchedule.stage(silenceMs: 16_000, hintsAlreadyGiven: 1, delayMs: 8_000, maxHints: 3, speaking: true))
        XCTAssertNil(HintSchedule.stage(silenceMs: 40_000, hintsAlreadyGiven: 3, delayMs: 8_000, maxHints: 3, speaking: false))
    }

    func testStreakUsesTokyoDaysAndAllowsYesterday() {
        let calendar = StudyCalendar.tokyo()
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let days: Set<String> = ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]
        XCTAssertEqual(StudyCalendar.streak(practiceDays: days, today: today, calendar: calendar), 4)
        let withoutToday: Set<String> = ["2026-11-21", "2026-11-22"]
        XCTAssertEqual(StudyCalendar.streak(practiceDays: withoutToday, today: today, calendar: calendar), 2)
        XCTAssertEqual(StudyCalendar.streak(practiceDays: ["2026-11-20"], today: today, calendar: calendar), 0)
        XCTAssertEqual(StudyCalendar.intensity(sessionCount: 0), 0)
        XCTAssertEqual(StudyCalendar.intensity(sessionCount: 2), 2)
        XCTAssertEqual(StudyCalendar.intensity(sessionCount: 5), 3)
    }

    func testNovember2026StartsOnSunday() {
        let calendar = StudyCalendar.tokyo()
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let month = StudyCalendar.month(2026, 11, today: today, calendar: calendar)
        XCTAssertEqual(month.cells.first?.day, 1)
        XCTAssertEqual(month.cells.filter { $0.day != nil }.count, 30)
        XCTAssertTrue(month.cells.contains { $0.day == 23 && $0.isToday })
        XCTAssertTrue(month.cells.contains { $0.day == 24 && $0.isFuture })
        XCTAssertFalse(StudyCalendar.canMoveForward(year: 2026, month: 11, today: today, calendar: calendar))
        XCTAssertTrue(StudyCalendar.canMoveForward(year: 2026, month: 10, today: today, calendar: calendar))
    }

    func testCatalogReleasesThirtyScenesAndHidesTheInternalLine() {
        XCTAssertEqual(SceneLibrary.all.count, 100)
        XCTAssertEqual(SceneLibrary.all.filter(\.released).count, 30)
        XCTAssertEqual(SceneCategory.allCases.count, 10)
        for category in SceneCategory.allCases {
            XCTAssertEqual(SceneLibrary.releasedCount(in: category), 3, category.title)
        }
        let interview = SceneLibrary.scene(id: "career-01")
        XCTAssertEqual(interview?.title, "面接の自己紹介")
        XCTAssertEqual(interview?.released, true)
        XCTAssertEqual(SceneLibrary.scene(id: "career-07")?.title, "外資系インターン面接")
        XCTAssertEqual(SceneLibrary.scene(id: "career-07")?.released, false)
        let blob = SceneLibrary.all.map { "\($0.title) \($0.goalJa) \($0.roleJa)" }.joined(separator: "\n")
        XCTAssertFalse(blob.contains("Mouthyライン"))
        XCTAssertFalse(blob.contains("ラインまで"))
        let script = TalkScript.script(for: interview!)
        XCTAssertTrue(TalkScript.linesAreSafe(script))
    }

    func testWordCountDropsFillersAndJapanese() {
        XCTAssertEqual(SpokenWords.count("um I join the club えーと"), 4)
        XCTAssertTrue(SpokenWords.containsJapanese("えーと"))
        XCTAssertTrue(SpokenWords.containsBannedJudgement("that was a mistake"))
    }

    func testCorrectionsRoundTripThroughJSON() throws {
        let correction = ReviewCorrection(id: "c1", tag: "時制", original: "I join", better: "I joined", reasonJa: "過去形")
        let phrase = StuckPhrase(id: "s1", phrase: "to be honest", meaningJa: "正直に言うと", reason: "6秒の間")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let correctionData = try encoder.encode(correction)
        let phraseData = try encoder.encode(phrase)
        XCTAssertEqual(try decoder.decode(ReviewCorrection.self, from: correctionData), correction)
        XCTAssertEqual(try decoder.decode(StuckPhrase.self, from: phraseData), phrase)
        _ = TranscriptBook()
    }

    func testTenseCorrectionAndStartPoint() {
        let review = ReviewMath.build(
            levels: [.answers],
            learnerAskedOrExpanded: false,
            learnerTexts: ["I join the finance club last year."],
            checkpointsDone: 1,
            checkpointsTotal: 4,
            speakingWpm: 90,
            reactionMedianMs: 2000,
            averageWordsPerTurn: 7,
            wordCount: 7,
            previousTotal: 60
        )
        XCTAssertEqual(review.corrections.first?.tag, "時制")
        XCTAssertEqual(review.delta, review.score.total - 60)
        XCTAssertEqual(ProgressMath.startPoint(total: 55).cefr, "A2+")
        XCTAssertEqual(ProgressMath.startPoint(total: 55).level, 1)
        XCTAssertEqual(ProgressMath.talkTimeLabel(seconds: 3 * 3600 + 12 * 60), "3時間12分")
    }
}

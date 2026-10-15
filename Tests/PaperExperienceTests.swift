import XCTest
import SwiftData
@testable import Folio

final class PaperExperienceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var paper: StudyRecord { StudyRecord(.paper, id: "p", ["title": "Pure 1", "durationMinutes": "90"]) }

    func testCountdownSurvivesSerializationAndTimeAway() throws {
        let started = PaperClock.start(paper, now: now)
        let restored = try JSONDecoder().decode(StudyRecord.self, from: JSONEncoder().encode(started))
        XCTAssertEqual(PaperClock.remaining(restored, now: now.addingTimeInterval(1200)), 4200, accuracy: 0.01)
        XCTAssertEqual(PaperClock.remaining(restored, now: now.addingTimeInterval(6000)), 0)
        XCTAssertTrue(StudyRules.validate([restored]).isEmpty)
    }
    func testPauseDoesNotConsumeTimeAndResumeUsesRemainingTime() {
        let started = PaperClock.start(paper, now: now)
        let paused = PaperClock.pause(started, now: now.addingTimeInterval(600))
        XCTAssertEqual(PaperClock.remaining(paused, now: now.addingTimeInterval(3600)), 4800)
        let resumed = PaperClock.start(paused, now: now.addingTimeInterval(3600))
        XCTAssertEqual(PaperClock.remaining(resumed, now: now.addingTimeInterval(3900)), 4500, accuracy: 0.01)
        XCTAssertTrue(StudyRules.validate([paused]).isEmpty)
    }
    func testFinishAndResetPreserveScansAndPaperMetadata() {
        var original = paper; original.setIDs("pages", [UUID(), UUID()]); original["notes"] = "Work on paper"
        let finished = PaperClock.finish(PaperClock.start(original, now: now), now: now.addingTimeInterval(100))
        XCTAssertEqual(finished["timerState"], "finished")
        XCTAssertNotNil(finished.date("completedAt"))
        XCTAssertEqual(PaperClock.remaining(finished), 0)
        let reset = PaperClock.reset(finished)
        XCTAssertEqual(PaperClock.remaining(reset), 5400)
        XCTAssertEqual(reset.ids("pages"), original.ids("pages"))
        XCTAssertEqual(reset["notes"], original["notes"])
        XCTAssertTrue(reset["completedAt"].isEmpty)
    }
    func testClockValidationRejectsUnusableStatesAndNumbers() {
        for fields in [
            ["timerState": "running"], ["timerState": "paused"],
            ["timerState": "invented"], ["durationMinutes": "0"],
            ["durationMinutes": "721"], ["durationMinutes": "1.5"], ["timerRemaining": "nan"],
            ["timerRemaining": "-1"], ["timerRemaining": "43201"]
        ] {
            var invalid = paper
            for (field, value) in fields { invalid[field] = value }
            XCTAssertFalse(StudyRules.validate([invalid]).isEmpty, "Accepted \(fields)")
        }
        XCTAssertEqual(PaperClock.label(0), "00:00")
        XCTAssertEqual(PaperClock.label(61), "01:01")
        XCTAssertEqual(PaperClock.label(0.3), "00:01")
        let expired = PaperClock.start(paper, now: now)
        XCTAssertEqual(PaperClock.pause(expired, now: now.addingTimeInterval(6000))["timerState"], "finished")
    }
    func testMultiPageQuestionAndInheritedPageRangeCountOnce() {
        let parent = StudyRecord(.question, id: "q", ["paper": "p", "label": "1", "pageStart": "2", "pageEnd": "3"])
        let child = StudyRecord(.question, id: "a", ["paper": "p", "parent": "q", "label": "1(a)", "marks": "4", "earned": "0"])
        let other = StudyRecord(.question, id: "b", ["paper": "p", "label": "2", "pageStart": "3", "marks": "2", "earned": "1.5"])
        let questions = [parent, child, other]
        XCTAssertEqual(StudyRules.pageRange(child, in: questions), 2...3)
        XCTAssertEqual(StudyMarks.leaves(questions).count, 2)
        XCTAssertEqual(StudyMarks.total(questions), StudyMarks(earned: 1.5, available: 6, marked: 2, count: 2))
    }
    @MainActor func testRunningTimerAndPageMarksSurviveStoreReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = Schema([StudyItem.self])
        let config = ModelConfiguration(schema: schema, url: folder.appending(path: "Study.store"), cloudKitDatabase: .none)
        let pageID = UUID()
        var original = paper; original.setIDs("pages", [pageID])
        let question = StudyRecord(.question, id: "q", ["paper": "p", "label": "Page 1 total", "pageStart": "1", "marks": "5", "earned": "3"])
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            try StudyStore.write([PaperClock.start(original, now: now), question], context: container.mainContext)
        }
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let records = try StudyStore.records(reopened.mainContext)
        let restored = try XCTUnwrap(records.first { $0.id == "p" })
        XCTAssertEqual(restored.ids("pages"), [pageID])
        XCTAssertEqual(PaperClock.remaining(restored, now: now.addingTimeInterval(600)), 4800, accuracy: 0.01)
        XCTAssertEqual(StudyMarks.total(records.filter { $0.type == .question }).earned, 3)
    }
    func testPageTotalCannotDoubleCountIndividualQuestions() {
        let total = StudyRecord(.question, id: "total", ["paper": "p", "label": "Page 2 total", "pageStart": "2", "markingMode": "pageTotal", "marks": "10", "earned": "7"])
        let question = StudyRecord(.question, id: "q", ["paper": "p", "label": "1", "pageStart": "1", "pageEnd": "2", "marks": "3"])
        XCTAssertTrue(StudyRules.validate([paper, total]).isEmpty)
        XCTAssertFalse(StudyRules.validate([question], against: [paper, total]).isEmpty)
        XCTAssertFalse(StudyRules.validate([total], against: [paper, question]).isEmpty)
        var otherPage = question; otherPage["pageStart"] = "3"; otherPage["pageEnd"] = ""
        XCTAssertTrue(StudyRules.validate([otherPage], against: [paper, total]).isEmpty)
        var child = question; child["parent"] = "total"; child["pageStart"] = ""; child["pageEnd"] = ""
        XCTAssertFalse(StudyRules.validate([child], against: [paper, total]).isEmpty)
    }
}

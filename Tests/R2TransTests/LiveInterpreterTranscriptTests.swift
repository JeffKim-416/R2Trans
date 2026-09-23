import XCTest
@testable import R2Trans

final class LiveInterpreterTranscriptTests: XCTestCase {
    func testEmptySnapshotHasNoTranscriptState() {
        XCTAssertEqual(LiveInterpreterTranscriptSnapshot(), LiveInterpreterTranscriptSnapshot())
        XCTAssertEqual(LiveInterpreterTranscriptAccumulator().snapshot, LiveInterpreterTranscriptSnapshot())
    }

    func testSplitDeltasAccumulateSourceAndOfficialText() {
        var accumulator = LiveInterpreterTranscriptAccumulator()

        accumulator.appendSource("Hello")
        accumulator.appendSource(", how are you?")
        accumulator.appendOfficial("안녕")
        accumulator.appendOfficial(", 잘 지내?")

        let snapshot = accumulator.snapshot
        XCTAssertEqual(snapshot.sourceHistory, "Hello, how are you?")
        XCTAssertEqual(snapshot.officialHistory, "안녕, 잘 지내?")
        XCTAssertEqual(snapshot.latestSource, "Hello, how are you?")
        XCTAssertEqual(snapshot.latestOfficial, "안녕, 잘 지내?")
        XCTAssertTrue(snapshot.provisional.isEmpty)
        XCTAssertFalse(snapshot.historyTruncated)
    }

    func testMultilingualTextAndPunctuationRemainUntouched() {
        var accumulator = LiveInterpreterTranscriptAccumulator()
        let source = "버전 1.0.0이 준비됐습니다. English is ready! 日本語も準備完了。"
        let official = "Version 1.0.0 is ready. 영어도 준비됐습니다! 日本語も準備完了。"

        accumulator.appendSource(source)
        accumulator.appendOfficial(official)

        XCTAssertEqual(accumulator.snapshot.sourceHistory, source)
        XCTAssertEqual(accumulator.snapshot.officialHistory, official)
        XCTAssertTrue(accumulator.snapshot.latestSource.contains("1.0.0"))
        XCTAssertTrue(accumulator.snapshot.latestOfficial.contains("1.0.0"))
    }

    func testFocusTailUsesRecentSentencesAndCharacterBound() {
        var accumulator = LiveInterpreterTranscriptAccumulator()
        let sentences = (1...12).map { "Sentence \($0) with enough text to make the history considerably longer." }
        accumulator.appendSource(sentences.joined(separator: " "))
        accumulator.appendOfficial(sentences.joined(separator: " "))

        let snapshot = accumulator.snapshot
        XCTAssertLessThanOrEqual(snapshot.latestSource.count, LiveInterpreterTranscriptAccumulator.sourceFocusLimit)
        XCTAssertLessThanOrEqual(snapshot.latestOfficial.count, LiveInterpreterTranscriptAccumulator.officialFocusLimit)
        XCTAssertTrue(snapshot.latestSource.contains("Sentence 12"))
        XCTAssertTrue(snapshot.latestOfficial.contains("Sentence 12"))
        XCTAssertFalse(snapshot.latestSource.contains("Sentence 1 "))
    }

    func testHistoryRetentionIsBoundedAndMarksTruncation() {
        var accumulator = LiveInterpreterTranscriptAccumulator()
        let source = String(repeating: "가", count: LiveInterpreterTranscriptAccumulator.sourceHistoryLimit + 11)
        let official = String(repeating: "a", count: LiveInterpreterTranscriptAccumulator.officialHistoryLimit + 11)

        accumulator.appendSource(source)
        XCTAssertEqual(accumulator.snapshot.sourceHistory.count, LiveInterpreterTranscriptAccumulator.sourceHistoryLimit)
        XCTAssertTrue(accumulator.snapshot.historyTruncated)

        accumulator.appendOfficial(official)
        XCTAssertEqual(accumulator.snapshot.officialHistory.count, LiveInterpreterTranscriptAccumulator.officialHistoryLimit)
        XCTAssertTrue(accumulator.snapshot.historyTruncated)
    }

    func testProvisionalTextReplacesAndOfficialOutputClearsIt() {
        var accumulator = LiveInterpreterTranscriptAccumulator()
        accumulator.appendSource("The meeting starts")
        accumulator.setProvisional("회의가 시작될 것 같습니다")
        XCTAssertEqual(accumulator.snapshot.provisional, "회의가 시작될 것 같습니다")

        accumulator.setProvisional("회의가 시작됩니다")
        XCTAssertEqual(accumulator.snapshot.provisional, "회의가 시작됩니다")

        accumulator.appendOfficial("회의가 시작됩니다.")
        XCTAssertTrue(accumulator.snapshot.provisional.isEmpty)
        XCTAssertEqual(accumulator.snapshot.latestOfficial, "회의가 시작됩니다.")
    }

    func testResetClearsPreviousSessionState() {
        var accumulator = LiveInterpreterTranscriptAccumulator()
        accumulator.appendSource("previous source")
        accumulator.appendOfficial("previous translation")
        accumulator.setProvisional("previous provisional")
        XCTAssertFalse(accumulator.snapshot.sourceHistory.isEmpty)

        accumulator.reset()

        XCTAssertEqual(accumulator.snapshot, LiveInterpreterTranscriptSnapshot())
        XCTAssertTrue(accumulator.sourceSinceOfficialOutput.isEmpty)
    }
}

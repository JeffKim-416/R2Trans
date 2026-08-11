import Foundation
import XCTest
@testable import R2Trans

final class TranslationRequestSafetyTests: XCTestCase {
    func testLongTextChunksReconstructOriginalWithoutOversizedRequests() {
        let text = (0..<40)
            .map { "Paragraph \($0): " + String(repeating: "translation input ", count: 12) }
            .joined(separator: "\n\n")

        let chunks = TranslationTextChunker.chunks(text, maximumCharacters: 240)
        let reconstructed = chunks
            .map { $0.text + $0.trailingSeparator }
            .joined()

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 240 })
        XCTAssertEqual(reconstructed, text)
    }

    func testUnbrokenLongTextUsesHardBoundariesWithoutDroppingCharacters() {
        let text = String(repeating: "가", count: 1_001)
        let chunks = TranslationTextChunker.chunks(text, maximumCharacters: 200)

        XCTAssertEqual(chunks.map { $0.text + $0.trailingSeparator }.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 200 })
    }

    func testOutputTokenLimitIsBoundedForLongInput() {
        let text = String(repeating: "긴 입력", count: 2_000)

        XCTAssertEqual(
            TranslationRequestLimits.outputTokenLimit(for: text, ceiling: 4_096),
            4_096
        )
        XCTAssertLessThanOrEqual(
            TranslationRequestLimits.outputTokenLimit(for: text, ceiling: 512),
            512
        )
    }

    func testInstallationSafetyIdentifierIsStableAndPseudonymous() throws {
        let suiteName = "R2TransTests.OpenAISafetyIdentifier.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstUUID = try XCTUnwrap(UUID(uuidString: "12345678-1234-1234-1234-1234567890AB"))
        let secondUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let first = OpenAISafetyIdentifier.loadOrCreate(
            defaults: defaults,
            makeUUID: { firstUUID }
        )
        let second = OpenAISafetyIdentifier.loadOrCreate(
            defaults: defaults,
            makeUUID: { secondUUID }
        )

        XCTAssertEqual(first, "r2trans_123456781234123412341234567890ab")
        XCTAssertEqual(second, first)
    }
}

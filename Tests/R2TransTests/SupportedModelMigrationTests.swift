import Foundation
import XCTest
@testable import R2Trans

final class SupportedModelMigrationTests: XCTestCase {
    func testCurrentCatalogUsesGPT56Tiers() {
        XCTAssertEqual(
            SupportedModel.all.map(\.id),
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        )
        XCTAssertEqual(SupportedModel.defaultID, "gpt-5.6-luna")
    }

    func testUnknownStoredModelFallsBackToDefault() throws {
        let suiteName = "R2TransTests.SupportedModelMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("future-model", forKey: "model")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.model, SupportedModel.defaultID)
        XCTAssertEqual(defaults.string(forKey: "model"), SupportedModel.defaultID)
    }
}

final class LiveInterpreterSettingsTests: XCTestCase {
    func testProvisionalSubtitlesDefaultToEnabledAndPersistChanges() throws {
        let suiteName = "R2TransTests.LiveInterpreterSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.liveInterpreterProvisionalSubtitlesEnabled)

        settings.liveInterpreterProvisionalSubtitlesEnabled = false

        XCTAssertFalse(AppSettings(defaults: defaults).liveInterpreterProvisionalSubtitlesEnabled)
    }
}

final class AutoDetectPairTests: XCTestCase {
    func testKoreanChineseAndSpanishPairsAreAvailable() {
        XCTAssertEqual(AutoDetectPair.allCases.map(\.rawValue), [
            "ko-KR <-> en-US",
            "ko-KR <-> ja-JP",
            "ko-KR <-> zh-CN",
            "ko-KR <-> es-ES"
        ])
        XCTAssertEqual(AutoDetectPair.koreanChinese.secondLanguageCode, "zh-CN")
        XCTAssertEqual(AutoDetectPair.koreanSpanish.secondLanguageCode, "es-ES")
    }
}

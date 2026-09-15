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

    func testLegacyModelsMigrateToEquivalentGPT56Tier() {
        let migrations = [
            ("gpt-5.6", "gpt-5.6-sol"),
            ("gpt-5.5", "gpt-5.6-sol"),
            ("gpt-5.4", "gpt-5.6-sol"),
            ("gpt-5.4-mini", "gpt-5.6-terra"),
            ("gpt-5.4-nano", "gpt-5.6-luna"),
            ("gpt-5.3-codex", "gpt-5.6-sol"),
            ("gpt-5.2", "gpt-5.6-sol")
        ]

        for (storedID, expectedID) in migrations {
            XCTAssertEqual(
                SupportedModel.normalizedID(storedID),
                expectedID,
                "Unexpected migration for \(storedID)"
            )
        }
    }

    func testUnknownModelIsLeftForSettingsFallback() {
        XCTAssertEqual(SupportedModel.normalizedID("future-model"), "future-model")
    }

    func testReadingLegacyStoredModelPersistsMigration() throws {
        let suiteName = "R2TransTests.SupportedModelMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("gpt-5.4-mini", forKey: "model")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.model, "gpt-5.6-terra")
        XCTAssertEqual(defaults.string(forKey: "model"), "gpt-5.6-terra")
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

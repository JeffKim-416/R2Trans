import Foundation
import XCTest
@testable import R2Trans

final class LiveTranscriptionProtocolTests: XCTestCase {
    func testLanguageHintsUseRealtimeAcceptedCodes() {
        XCTAssertNil(LiveTranscriptionProtocol.realtimeLanguageCode(from: nil))
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "en-US"), "en")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "ko-KR"), "ko")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "es-ES"), "es")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "ja-JP"), "ja")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "zh-CN"), "zh-cn")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "zh-TW"), "zh-tw")
        XCTAssertEqual(LiveTranscriptionProtocol.realtimeLanguageCode(from: "zh-HK"), "zh-tw")
        XCTAssertNil(LiveTranscriptionProtocol.realtimeLanguageCode(from: "fr-FR"))
    }

    func testSessionPayloadConfiguresLiveTranscriptionAndServerVAD() throws {
        let payload = LiveTranscriptionProtocol.sessionUpdatePayload(languageCode: "ko")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertEqual(payload["type"] as? String, "session.update")

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["delay"] as? String, "low")
        XCTAssertEqual(transcription["languages"] as? [String], ["ko"])

        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection["threshold"] as? Double, 0.5)
        XCTAssertEqual(turnDetection["prefix_padding_ms"] as? Int, 300)
        XCTAssertEqual(turnDetection["silence_duration_ms"] as? Int, 500)
    }

    func testAutomaticLanguageOmitsLanguagesField() throws {
        let payload = LiveTranscriptionProtocol.sessionUpdatePayload(languageCode: nil)
        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])

        XCTAssertNil(transcription["languages"])
    }
}

final class RealtimeTranscriptionEventTests: XCTestCase {
    func testDecodesTranscriptDeltaAndCompletion() throws {
        let delta = try decode(
            """
            {
              "type": "conversation.item.input_audio_transcription.delta",
              "item_id": "item_003",
              "content_index": 0,
              "delta": "Hello,"
            }
            """
        )
        XCTAssertEqual(delta, .transcriptDelta(itemID: "item_003", delta: "Hello,"))

        let completed = try decode(
            """
            {
              "type": "conversation.item.input_audio_transcription.completed",
              "item_id": "item_003",
              "content_index": 0,
              "transcript": "Hello, how are you?"
            }
            """
        )
        XCTAssertEqual(
            completed,
            .transcriptCompleted(itemID: "item_003", transcript: "Hello, how are you?")
        )
    }

    func testDecodesBothCurrentAndLegacyItemOrderingEvents() throws {
        for type in ["conversation.item.added", "conversation.item.created"] {
            let event = try decode(
                """
                {
                  "type": "\(type)",
                  "previous_item_id": "item_001",
                  "item": { "id": "item_002" }
                }
                """
            )
            XCTAssertEqual(
                event,
                .itemCreated(itemID: "item_002", previousItemID: "item_001")
            )
        }

        let committed = try decode(
            """
            {
              "type": "input_audio_buffer.committed",
              "previous_item_id": "item_001",
              "item_id": "item_002"
            }
            """
        )
        XCTAssertEqual(
            committed,
            .itemCreated(itemID: "item_002", previousItemID: "item_001")
        )
    }

    func testDecodesPerItemTranscriptionFailure() throws {
        let event = try decode(
            """
            {
              "type": "conversation.item.input_audio_transcription.failed",
              "item_id": "item_003",
              "content_index": 0,
              "error": {
                "type": "transcription_error",
                "code": "audio_unintelligible",
                "message": "The audio could not be transcribed."
              }
            }
            """
        )

        XCTAssertEqual(
            event,
            .transcriptFailed(
                itemID: "item_003",
                message: "The audio could not be transcribed."
            )
        )
    }

    func testDecodesTopLevelServerErrorForTerminalHandling() throws {
        let event = try decode(
            """
            {
              "type": "error",
              "error": {
                "type": "invalid_request_error",
                "code": "invalid_event",
                "message": "The event was invalid."
              }
            }
            """
        )

        XCTAssertEqual(event, .serverError("The event was invalid."))
        XCTAssertEqual(event?.terminalFailureMessage, "The event was invalid.")
    }

    func testPerItemFailureIsNotClassifiedAsTerminal() throws {
        let event = try decode(
            """
            {
              "type": "conversation.item.input_audio_transcription.failed",
              "item_id": "item_003",
              "error": { "message": "Could not transcribe this turn." }
            }
            """
        )

        XCTAssertNil(event?.terminalFailureMessage)
    }

    private func decode(_ json: String) throws -> RealtimeTranscriptionEvent? {
        try RealtimeTranscriptionEvent.decode(
            XCTUnwrap(json.data(using: .utf8))
        )
    }
}

final class LiveTranscriptAssemblerTests: XCTestCase {
    func testFinalTranscriptReplacesAccumulatedPartialText() {
        var assembler = LiveTranscriptAssembler()

        XCTAssertTrue(assembler.append(delta: "Hel", to: "item_001"))
        XCTAssertTrue(assembler.append(delta: "lo", to: "item_001"))
        XCTAssertEqual(assembler.transcript, "Hello")

        XCTAssertTrue(assembler.complete(itemID: "item_001", transcript: "Hello!"))
        XCTAssertEqual(assembler.transcript, "Hello!")
        XCTAssertFalse(assembler.append(delta: " stale", to: "item_001"))
        XCTAssertEqual(assembler.transcript, "Hello!")
    }

    func testLateOrderingMetadataMovesPreviouslyObservedPlaceholder() {
        var assembler = LiveTranscriptAssembler()
        assembler.complete(itemID: "item_002", transcript: "second")
        assembler.complete(itemID: "item_001", transcript: "first")
        XCTAssertEqual(assembler.transcript, "second\nfirst")

        assembler.register(itemID: "item_001", previousItemID: nil)
        assembler.register(itemID: "item_002", previousItemID: "item_001")
        XCTAssertEqual(assembler.transcript, "first\nsecond")
    }

    func testOutOfOrderCompletionsAreReconciledThroughPredecessorChain() {
        var assembler = LiveTranscriptAssembler()
        assembler.complete(itemID: "item_003", transcript: "third")
        assembler.register(itemID: "item_003", previousItemID: "item_002")
        assembler.complete(itemID: "item_002", transcript: "second")
        assembler.register(itemID: "item_002", previousItemID: "item_001")
        assembler.complete(itemID: "item_001", transcript: "first")
        assembler.register(itemID: "item_001", previousItemID: nil)

        XCTAssertEqual(assembler.transcript, "first\nsecond\nthird")
    }

    func testEvictedItemCannotBeResurrectedByLateCompletion() {
        var assembler = LiveTranscriptAssembler(
            maximumItemCount: 2,
            maximumCharacterCount: 1_000
        )
        assembler.register(itemID: "item_001", previousItemID: nil)
        assembler.complete(itemID: "item_001", transcript: "first")
        assembler.register(itemID: "item_002", previousItemID: "item_001")
        assembler.complete(itemID: "item_002", transcript: "second")
        assembler.register(itemID: "item_003", previousItemID: "item_002")
        assembler.complete(itemID: "item_003", transcript: "third")

        XCTAssertEqual(assembler.transcript, "second\nthird")
        XCTAssertFalse(assembler.complete(itemID: "item_001", transcript: "late first"))
        XCTAssertFalse(assembler.register(itemID: "item_001", previousItemID: nil))
        XCTAssertEqual(assembler.transcript, "second\nthird")
    }
}

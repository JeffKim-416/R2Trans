import Foundation
import XCTest
@testable import R2Trans

final class OpenAIResponsesTests: XCTestCase {
    func testCompletedResponseReturnsOutputText() throws {
        let response = try decodeResponse(
            """
            {
              "status": "completed",
              "incomplete_details": null,
              "output": [
                {
                  "type": "message",
                  "status": "completed",
                  "content": [
                    { "type": "output_text", "text": "  안녕하세요.  " }
                  ]
                }
              ]
            }
            """
        )

        XCTAssertEqual(try response.validatedTextOutput(), "안녕하세요.")
    }

    func testIncompleteResponseDiscardsPartialOutput() throws {
        let response = try decodeResponse(
            """
            {
              "status": "incomplete",
              "incomplete_details": { "reason": "max_output_tokens" },
              "output_text": "partial translation"
            }
            """
        )

        XCTAssertThrowsError(try response.validatedTextOutput()) { error in
            XCTAssertEqual(
                error as? ResponsesResponseValidationError,
                .responseNotCompleted(status: "incomplete", reason: "max_output_tokens")
            )
        }
    }

    func testCompletedResponseRejectsIncompleteMessageItem() throws {
        let response = try decodeResponse(
            """
            {
              "status": "completed",
              "incomplete_details": null,
              "output": [
                {
                  "type": "message",
                  "status": "incomplete",
                  "content": [
                    { "type": "output_text", "text": "partial translation" }
                  ]
                }
              ]
            }
            """
        )

        XCTAssertThrowsError(try response.validatedTextOutput()) { error in
            XCTAssertEqual(
                error as? ResponsesResponseValidationError,
                .outputItemNotCompleted(status: "incomplete")
            )
        }
    }

    func testCompletedResponseRejectsIncompleteDetails() throws {
        let response = try decodeResponse(
            """
            {
              "status": "completed",
              "incomplete_details": { "reason": "content_filter" },
              "output_text": "partial translation"
            }
            """
        )

        XCTAssertThrowsError(try response.validatedTextOutput()) { error in
            XCTAssertEqual(
                error as? ResponsesResponseValidationError,
                .incompleteDetailsOnCompletedResponse(reason: "content_filter")
            )
        }
    }

    func testMissingStatusCannotBeTreatedAsSuccess() throws {
        let response = try decodeResponse(
            """
            {
              "output_text": "unverified translation"
            }
            """
        )

        XCTAssertThrowsError(try response.validatedTextOutput()) { error in
            XCTAssertEqual(
                error as? ResponsesResponseValidationError,
                .responseNotCompleted(status: nil, reason: nil)
            )
        }
    }

    func testRequestEncodesPrivacyAndReasoningFields() throws {
        let request = ResponsesRequest(
            model: "gpt-5.6-luna",
            instructions: "Translate.",
            input: "Hello",
            maxOutputTokens: 512,
            reasoning: ResponsesReasoning(effort: "none"),
            store: false,
            safetyIdentifier: "r2trans_1234567890abcdef1234567890abcdef"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual(json["max_output_tokens"] as? Int, 512)
        XCTAssertEqual((json["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(
            json["safety_identifier"] as? String,
            "r2trans_1234567890abcdef1234567890abcdef"
        )
    }

    private func decodeResponse(_ json: String) throws -> ResponsesResponse {
        try JSONDecoder().decode(ResponsesResponse.self, from: Data(json.utf8))
    }
}

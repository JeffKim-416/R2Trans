import Foundation

final class OpenAITranslator: Sendable {
    private let settings = AppSettings.shared
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        let translated = try await translateInChunks(
            text,
            instructions: makeInstructions(),
            model: settings.model,
            maximumChunkCharacters: TranslationRequestLimits.maximumInputCharactersPerRequest,
            maximumOutputTokens: TranslationRequestLimits.maximumOutputTokens
        )

        guard let retryInstructions = autoDetectRetryInstructionsIfNeeded(
            originalText: text,
            translatedText: translated
        ) else {
            return translated
        }

        return try await translateInChunks(
            text,
            instructions: retryInstructions,
            model: settings.model,
            maximumChunkCharacters: TranslationRequestLimits.maximumInputCharactersPerRequest,
            maximumOutputTokens: TranslationRequestLimits.maximumOutputTokens
        )
    }

    func translateLiveTranscript(_ text: String, targetLanguageCode: String) async throws -> String {
        let targetLanguage = SupportedLanguage.englishName(for: targetLanguageCode)
        let instructions = """
        You are a low-latency live subtitle translator.
        Translate the partial speech transcript to \(targetLanguage).
        The input may be incomplete, so produce the best provisional translation from the stable meaning available now.
        Do not copy the source text unchanged unless it is a name, URL, code, or number that should be preserved.
        Return only the translated subtitle text.
        Do not add explanations, labels, or quotation marks.
        """

        return try await translateInChunks(
            text,
            instructions: instructions,
            model: SupportedModel.defaultID,
            maximumChunkCharacters: TranslationRequestLimits.maximumLiveInputCharactersPerRequest,
            maximumOutputTokens: TranslationRequestLimits.maximumLiveOutputTokens
        )
    }

    private func translateInChunks(
        _ text: String,
        instructions: String,
        model: String,
        maximumChunkCharacters: Int,
        maximumOutputTokens: Int
    ) async throws -> String {
        let chunks = TranslationTextChunker.chunks(
            text,
            maximumCharacters: maximumChunkCharacters
        )
        var translatedText = ""

        for chunk in chunks {
            if chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translatedText += chunk.text
            } else {
                let outputTokenLimit = TranslationRequestLimits.outputTokenLimit(
                    for: chunk.text,
                    ceiling: maximumOutputTokens
                )
                translatedText += try await performTranslationRequest(
                    chunk.text,
                    instructions: instructions,
                    model: model,
                    maxOutputTokens: outputTokenLimit
                )
            }

            translatedText += chunk.trailingSeparator
        }

        let result = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw R2TransError.openAIResponseMissing
        }

        return result
    }

    private func performTranslationRequest(
        _ text: String,
        instructions: String,
        model: String,
        maxOutputTokens: Int
    ) async throws -> String {
        let apiKey = try KeychainStore.loadAPIKeyOrThrow()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw R2TransError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ResponsesRequest(
            model: model,
            instructions: instructions,
            input: text,
            maxOutputTokens: maxOutputTokens,
            reasoning: ResponsesReasoning(effort: "none"),
            store: false,
            safetyIdentifier: OpenAISafetyIdentifier.value
        )

        request.httpBody = try JSONEncoder.snakeCaseEncoder.encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw R2TransError.openAIRequestFailed(
                "\(AppText.text(.networkError))\n\n\(urlError.localizedDescription)"
            )
        } catch {
            throw R2TransError.openAIRequestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw R2TransError.openAIRequestFailed("OpenAI did not return an HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? String(data: data, encoding: .utf8) ?? "Unknown OpenAI API error."
            throw R2TransError.openAIRequestFailed(friendlyErrorMessage(statusCode: httpResponse.statusCode, apiMessage: message))
        }

        let decoded: ResponsesResponse

        do {
            decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        } catch {
            throw R2TransError.openAIRequestFailed("OpenAI returned an invalid response.")
        }

        do {
            return try decoded.validatedTextOutput()
        } catch ResponsesResponseValidationError.missingText {
            throw R2TransError.openAIResponseMissing
        } catch let validationError as ResponsesResponseValidationError {
            throw R2TransError.openAIRequestFailed(validationError.localizedDescription)
        }
    }

    private func makeInstructions() -> String {
        switch settings.workMode {
        case .translation:
            return makeTranslationInstructions()
        case .rewrite:
            return makeRewriteInstructions()
        }
    }

    private func makeTranslationInstructions() -> String {
        let modeInstruction: String

        if settings.autoDetectEnabled {
            let pair = settings.autoDetectPair
            let firstLanguage = SupportedLanguage.englishName(for: pair.firstLanguageCode)
            let secondLanguage = SupportedLanguage.englishName(for: pair.secondLanguageCode)
            let pairSpecificInstruction: String

            switch pair {
            case .koreanEnglish:
                pairSpecificInstruction = """
                For Korean <-> English, treat text with Hangul as Korean and text with Latin words and no Hangul as English.
                English input must be translated into Korean. Never return English for English input.
                Korean input must be translated into English.
                """
            case .koreanJapanese:
                pairSpecificInstruction = """
                For Korean <-> Japanese, treat text with Hangul as Korean and text with Japanese kana or kanji without Hangul as Japanese.
                Korean input must be translated into Japanese, and Japanese input must be translated into Korean.
                """
            }

            modeInstruction = """
            Detect whether the user's text is primarily \(firstLanguage) or \(secondLanguage).
            If it is primarily \(firstLanguage), translate it to \(secondLanguage).
            If it is primarily \(secondLanguage), translate it to \(firstLanguage).
            If both languages appear, choose the predominant language and translate to the other language in this pair.
            \(pairSpecificInstruction)
            """
        } else {
            let sourceLanguage = SupportedLanguage.englishName(for: settings.sourceLanguageCode)
            let targetLanguage = SupportedLanguage.englishName(for: settings.targetLanguageCode)
            modeInstruction = "Translate the user's text from \(sourceLanguage) to \(targetLanguage)."
        }

        return """
        You are a precise translation engine.
        \(modeInstruction)
        \(styleInstruction(for: settings.translationStyle))
        Return only the translated text.
        Preserve line breaks, list structure, numbers, names, URLs, code, and markdown when possible.
        Do not add explanations or quotation marks.
        """
    }

    private func makeForcedTranslationInstructions(sourceLanguageCode: String, targetLanguageCode: String) -> String {
        let sourceLanguage = SupportedLanguage.englishName(for: sourceLanguageCode)
        let targetLanguage = SupportedLanguage.englishName(for: targetLanguageCode)

        return """
        You are a precise translation engine.
        Translate the user's text from \(sourceLanguage) to \(targetLanguage).
        The output language must be \(targetLanguage).
        Do not return the source text unchanged unless it is a name, URL, code, or number that should be preserved.
        \(styleInstruction(for: settings.translationStyle))
        Return only the translated text.
        Preserve line breaks, list structure, numbers, names, URLs, code, and markdown when possible.
        Do not add explanations or quotation marks.
        """
    }

    private func makeRewriteInstructions() -> String {
        """
        You are a precise rewriting engine.
        Rewrite the user's text in the same language as the input. Do not translate it into another language.
        Improve rough, awkward, or unclear wording while preserving the original meaning, intent, facts, names, numbers, URLs, code, markdown, and line breaks when possible.
        \(styleInstruction(for: settings.translationStyle))
        Return only the rewritten text.
        Do not add explanations or quotation marks.
        """
    }

    private func styleInstruction(for style: TranslationStyle) -> String {
        switch style {
        case .natural:
            return "Make the translation sound natural and fluent."
        case .formal:
            return "Use formal, polished, professional wording."
        case .polite:
            return "Use courteous, respectful, and considerate wording."
        case .groveling:
            return "Use very humble, apologetic, and deferential wording without adding new substantive meaning."
        case .nyang:
            return """
            If the target output language is Korean, use a cute Korean nyangnyang style with endings like '냥' or '다냥' where natural.
            Do not overuse it, and preserve the original meaning.
            If the target output language is not Korean, use the Natural style instead.
            """
        }
    }

    private func friendlyErrorMessage(statusCode: Int, apiMessage: String) -> String {
        let friendlyMessage: String

        switch statusCode {
        case 401, 403:
            friendlyMessage = AppText.text(.openAIUnauthorized)
        case 429:
            friendlyMessage = AppText.text(.openAIRateLimited)
        case 500...599:
            friendlyMessage = AppText.text(.openAITemporaryFailure)
        default:
            friendlyMessage = "OpenAI API error (\(statusCode))."
        }

        return "\(friendlyMessage)\n\n\(apiMessage)"
    }

    private func autoDetectRetryInstructionsIfNeeded(originalText: String, translatedText: String) -> String? {
        guard settings.workMode == .translation, settings.autoDetectEnabled else {
            return nil
        }

        switch settings.autoDetectPair {
        case .koreanEnglish:
            guard Self.looksEnglish(originalText) else {
                return nil
            }

            if !Self.containsHangul(translatedText) || Self.normalizedForComparison(originalText) == Self.normalizedForComparison(translatedText) {
                return makeForcedTranslationInstructions(sourceLanguageCode: "en-US", targetLanguageCode: "ko-KR")
            }

            return nil
        case .koreanJapanese:
            return nil
        }
    }

    private static func looksEnglish(_ text: String) -> Bool {
        let scalarCounts = text.unicodeScalars.reduce(into: (latin: 0, hangul: 0)) { result, scalar in
            if CharacterSet.r2TransHangul.contains(scalar) {
                result.hangul += 1
            } else if CharacterSet.r2TransLatin.contains(scalar) {
                result.latin += 1
            }
        }

        return scalarCounts.latin > 0 && scalarCounts.hangul == 0
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.r2TransHangul.contains($0) }
    }

    private static func normalizedForComparison(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension CharacterSet {
    static let r2TransHangul = CharacterSet(charactersIn: "\u{AC00}"..."\u{D7A3}")
    static let r2TransLatin = CharacterSet(charactersIn: "A"..."Z").union(CharacterSet(charactersIn: "a"..."z"))
}

struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
    let reasoning: ResponsesReasoning
    let store: Bool
    let safetyIdentifier: String
}

struct ResponsesReasoning: Encodable {
    let effort: String
}

struct ResponsesResponse: Decodable {
    let status: String?
    let incompleteDetails: IncompleteDetails?
    let outputText: String?
    let output: [OutputItem]?

    func validatedTextOutput() throws -> String {
        guard status == "completed" else {
            throw ResponsesResponseValidationError.responseNotCompleted(
                status: status,
                reason: incompleteDetails?.reason
            )
        }

        guard incompleteDetails == nil else {
            throw ResponsesResponseValidationError.incompleteDetailsOnCompletedResponse(
                reason: incompleteDetails?.reason
            )
        }

        if let incompleteMessage = output?.first(where: {
            $0.type == "message" && $0.status != "completed"
        }) {
            throw ResponsesResponseValidationError.outputItemNotCompleted(
                status: incompleteMessage.status
            )
        }

        let text: String

        if let outputText, !outputText.isEmpty {
            text = outputText
        } else {
            text = output?
                .filter { $0.type == "message" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap(\.text)
                .joined(separator: "")
                ?? ""
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ResponsesResponseValidationError.missingText
        }

        return trimmedText
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case incompleteDetails = "incomplete_details"
        case outputText = "output_text"
        case output
    }
}

struct IncompleteDetails: Decodable, Equatable {
    let reason: String?
}

struct OutputItem: Decodable {
    let type: String?
    let status: String?
    let content: [OutputContent]?
}

struct OutputContent: Decodable {
    let type: String?
    let text: String?
}

enum ResponsesResponseValidationError: Error, Equatable, LocalizedError {
    case responseNotCompleted(status: String?, reason: String?)
    case incompleteDetailsOnCompletedResponse(reason: String?)
    case outputItemNotCompleted(status: String?)
    case missingText

    var errorDescription: String? {
        switch self {
        case .responseNotCompleted(let status, let reason):
            return Self.incompleteMessage(status: status, reason: reason)
        case .incompleteDetailsOnCompletedResponse(let reason):
            return Self.incompleteMessage(status: "completed", reason: reason)
        case .outputItemNotCompleted(let status):
            return Self.incompleteMessage(status: status, reason: nil)
        case .missingText:
            return "OpenAI returned a completed response without translated text."
        }
    }

    private static func incompleteMessage(status: String?, reason: String?) -> String {
        let statusDescription = status ?? "missing"
        let reasonDescription = reason.map { ", reason: \($0)" } ?? ""
        return "OpenAI response was not completed (status: \(statusDescription)\(reasonDescription)). Partial output was discarded."
    }
}

enum TranslationRequestLimits {
    static let maximumInputCharactersPerRequest = 2_000
    static let maximumLiveInputCharactersPerRequest = 320
    static let maximumOutputTokens = 4_096
    static let maximumLiveOutputTokens = 512
    static let minimumOutputTokens = 256

    static func outputTokenLimit(for text: String, ceiling: Int) -> Int {
        let safeCeiling = max(1, ceiling)
        let estimatedInputTokens = max(1, (text.utf8.count + 2) / 3)
        let estimatedOutputTokens: Int

        if estimatedInputTokens > (Int.max - minimumOutputTokens) / 2 {
            estimatedOutputTokens = Int.max
        } else {
            estimatedOutputTokens = estimatedInputTokens * 2 + minimumOutputTokens
        }

        return min(safeCeiling, max(minimumOutputTokens, estimatedOutputTokens))
    }
}

struct TranslationTextChunk: Equatable {
    let text: String
    let trailingSeparator: String
}

enum TranslationTextChunker {
    private struct SplitPoint {
        let contentEnd: String.Index
        let consumedEnd: String.Index
        let separator: String
    }

    static func chunks(_ text: String, maximumCharacters: Int) -> [TranslationTextChunk] {
        precondition(maximumCharacters > 0)

        guard !text.isEmpty else {
            return [TranslationTextChunk(text: "", trailingSeparator: "")]
        }

        var chunks: [TranslationTextChunk] = []
        var remaining = text[...]

        while let hardEnd = remaining.index(
            remaining.startIndex,
            offsetBy: maximumCharacters,
            limitedBy: remaining.endIndex
        ), hardEnd < remaining.endIndex {
            let candidate = remaining[..<hardEnd]
            let minimumPreferredIndex = candidate.index(
                candidate.startIndex,
                offsetBy: maximumCharacters * 3 / 5
            )
            let splitPoint = preferredSplitPoint(
                in: candidate,
                minimumIndex: minimumPreferredIndex
            ) ?? SplitPoint(
                contentEnd: hardEnd,
                consumedEnd: hardEnd,
                separator: ""
            )

            chunks.append(
                TranslationTextChunk(
                    text: String(remaining[..<splitPoint.contentEnd]),
                    trailingSeparator: splitPoint.separator
                )
            )
            remaining = remaining[splitPoint.consumedEnd...]
        }

        if !remaining.isEmpty || chunks.isEmpty {
            chunks.append(TranslationTextChunk(text: String(remaining), trailingSeparator: ""))
        }

        return chunks
    }

    private static func preferredSplitPoint(
        in candidate: Substring,
        minimumIndex: String.Index
    ) -> SplitPoint? {
        let separators = ["\r\n\r\n", "\n\n", "\r\n", "\n", ". ", "! ", "? ", "。", "！", "？", "\t", " "]

        for separator in separators {
            guard let range = candidate.range(of: separator, options: .backwards),
                  range.upperBound >= minimumIndex else {
                continue
            }

            switch separator {
            case ". ", "! ", "? ":
                let contentEnd = candidate.index(after: range.lowerBound)
                return SplitPoint(
                    contentEnd: contentEnd,
                    consumedEnd: range.upperBound,
                    separator: String(candidate[contentEnd..<range.upperBound])
                )
            case "。", "！", "？":
                return SplitPoint(
                    contentEnd: range.upperBound,
                    consumedEnd: range.upperBound,
                    separator: ""
                )
            default:
                return SplitPoint(
                    contentEnd: range.lowerBound,
                    consumedEnd: range.upperBound,
                    separator: String(candidate[range])
                )
            }
        }

        return nil
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

private extension JSONEncoder {
    static var snakeCaseEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

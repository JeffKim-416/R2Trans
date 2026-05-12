import Foundation

final class OpenAITranslator {
    private let settings = AppSettings.shared
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        let apiKey = KeychainStore.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw R2TransError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let instructions = makeInstructions()
        let body = ResponsesRequest(
            model: settings.model,
            instructions: instructions,
            input: text,
            maxOutputTokens: 2048
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

        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        let translated = decoded.textOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else {
            throw R2TransError.openAIResponseMissing
        }

        return translated
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
            modeInstruction = """
            Detect whether the user's text is primarily \(firstLanguage) or \(secondLanguage).
            If it is primarily \(firstLanguage), translate it to \(secondLanguage).
            If it is primarily \(secondLanguage), translate it to \(firstLanguage).
            If both languages appear, choose the predominant language and translate to the other language in this pair.
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
}

private struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let maxOutputTokens: Int
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    var textOutput: String {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "")
            ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OutputItem: Decodable {
    let content: [OutputContent]?
}

private struct OutputContent: Decodable {
    let type: String?
    let text: String?
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

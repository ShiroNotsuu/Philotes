import Foundation

struct APIChatMessage: Encodable {
    let role: String
    let content: String
    var toolCalls: [APIAssistantToolCall]?
    var toolCallID: String?

    init(
        role: String,
        content: String,
        toolCalls: [APIAssistantToolCall]? = nil,
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

struct APIAssistantToolCall: Encodable {
    struct FunctionPayload: Encodable {
        let name: String
        let arguments: String
    }

    let id: String
    let type = "function"
    let function: FunctionPayload

    init(_ toolCall: APIToolCall) {
        id = toolCall.id
        function = FunctionPayload(
            name: toolCall.name,
            arguments: toolCall.arguments
        )
    }
}

struct APIToolDefinition: Encodable {
    struct FunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: APIToolParameterSchema
    }

    let type = "function"
    let function: FunctionDefinition

    init(
        name: String,
        description: String,
        parameters: APIToolParameterSchema
    ) {
        function = FunctionDefinition(
            name: name,
            description: description,
            parameters: parameters
        )
    }
}

struct APIToolParameterSchema: Encodable {
    let type = "object"
    let properties: [String: APIToolParameterProperty]
    let required: [String]
    let additionalProperties = false
}

struct APIToolParameterProperty: Encodable {
    let type: String
    let description: String
}

struct APIToolCall: Equatable {
    let id: String
    let name: String
    let arguments: String
}

enum APIToolChoice: Encodable {
    case auto
    case function(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case function
    }

    private struct FunctionChoice: Encodable {
        let name: String
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")
        case .function(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("function", forKey: .type)
            try container.encode(
                FunctionChoice(name: name),
                forKey: .function
            )
        }
    }
}

struct ChatStreamResult {
    let text: String
    let toolCalls: [APIToolCall]
}

struct CustomAPIClient {
    let configuration: APIConfiguration
    private let session: URLSession

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init(
        configuration: APIConfiguration,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.session = session ?? Self.sharedSession
    }

    func streamChat(
        messages: [APIChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let result = try await streamChatWithTools(
            messages: messages,
            tools: [],
            onDelta: onDelta
        )
        return result.text
    }

    func streamChatWithTools(
        messages: [APIChatMessage],
        tools: [APIToolDefinition],
        toolChoice: APIToolChoice? = nil,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ChatStreamResult {
        let request = try makeRequest(
            messages: messages,
            stream: true,
            tools: tools,
            toolChoice: toolChoice
        )
        let (bytes, response) = try await session.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let errorBody = try await collectData(from: bytes)
            try validateHTTPResponse(
                response,
                fallbackBody: errorBody
            )
        }
        try validateHTTPResponse(response, fallbackBody: nil)

        let contentType = (
            (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type") ?? ""
        ).lowercased()

        if !contentType.contains("application/json") {
            return try await parseEventStream(bytes, onDelta: onDelta)
        }

        let data = try await collectData(from: bytes)
        if let result = try decodeCompletionResult(from: data) {
            if !result.text.isEmpty {
                await onDelta(result.text)
            }
            guard !result.text.isEmpty || !result.toolCalls.isEmpty else {
                throw CustomAPIError.emptyResponse
            }
            return result
        }
        throw CustomAPIError.emptyResponse
    }

    func completeChatWithTools(
        messages: [APIChatMessage],
        tools: [APIToolDefinition],
        toolChoice: APIToolChoice? = nil
    ) async throws -> ChatStreamResult {
        let request = try makeRequest(
            messages: messages,
            stream: false,
            tools: tools,
            toolChoice: toolChoice
        )
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, fallbackBody: data)
        guard let result = try decodeCompletionResult(from: data),
              !result.text.isEmpty || !result.toolCalls.isEmpty
        else {
            throw CustomAPIError.emptyResponse
        }
        return result
    }

    func testConnection() async throws -> String {
        let request = try makeRequest(
            messages: [
                APIChatMessage(
                    role: "user",
                    content: "Reply with exactly: OK"
                )
            ],
            stream: false
        )
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, fallbackBody: data)

        guard let text = try decodeCompletion(from: data),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CustomAPIError.emptyResponse
        }
        return text
    }

    private func makeRequest(
        messages: [APIChatMessage],
        stream: Bool,
        tools: [APIToolDefinition] = [],
        toolChoice: APIToolChoice? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = stream ? 300 : 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            stream ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Philotes/0.1", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        if let apiKey = configuration.apiKey,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(
                "Bearer \(apiKey)",
                forHTTPHeaderField: "Authorization"
            )
        }

        let body = ChatRequest(
            model: configuration.model,
            messages: messages,
            stream: stream,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : toolChoice
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func parseEventStream(
        _ bytes: URLSession.AsyncBytes,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ChatStreamResult {
        let decoder = JSONDecoder()
        var fullText = ""
        var toolCalls: [Int: ToolCallAccumulator] = [:]

        for try await line in bytes.lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            var payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty,
                  !payload.hasPrefix(":")
            else {
                continue
            }

            if payload.hasPrefix("data:") {
                payload = String(payload.dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if payload == "[DONE]" {
                break
            }
            guard payload.hasPrefix("{"),
                  let data = payload.data(using: .utf8)
            else {
                continue
            }

            if let error = providerError(from: data, decoder: decoder) {
                throw CustomAPIError.provider(sanitized(error))
            }

            if let completion = try? decoder.decode(
                ChatCompletionResponse.self,
                from: data
            ) {
                if fullText.isEmpty,
                   let content = completion.choices.first?.message.content,
                   !content.isEmpty {
                    fullText = content
                    await onDelta(content)
                }
                let responseToolCalls = completion.choices.first?
                    .message.toolCalls?
                    .enumerated()
                    .map { index, toolCall in
                        APIToolCall(
                            id: toolCall.id ?? "tool-\(index)",
                            name: toolCall.function.name,
                            arguments: toolCall.function.arguments
                        )
                    } ?? []
                guard !responseToolCalls.isEmpty else { break }
                return ChatStreamResult(
                    text: fullText,
                    toolCalls: responseToolCalls
                )
            }

            guard let chunk = try? decoder.decode(
                ChatCompletionChunk.self,
                from: data
            ) else {
                continue
            }
            let delta = chunk.choices.first?.delta.content ?? ""
            if !delta.isEmpty {
                fullText += delta
                await onDelta(delta)
            }

            for toolCallDelta in chunk.choices.first?.delta.toolCalls ?? [] {
                var accumulator = toolCalls[toolCallDelta.index]
                    ?? ToolCallAccumulator()
                if let id = toolCallDelta.id, !id.isEmpty {
                    accumulator.id = id
                }
                if let name = toolCallDelta.function?.name, !name.isEmpty {
                    accumulator.name += name
                }
                if let arguments = toolCallDelta.function?.arguments {
                    accumulator.arguments += arguments
                }
                toolCalls[toolCallDelta.index] = accumulator
            }
        }

        let mergedToolCalls: [APIToolCall] = toolCalls.keys.sorted().compactMap {
            index -> APIToolCall? in
            guard let accumulator = toolCalls[index],
                  !accumulator.name.isEmpty
            else {
                return nil
            }
            return APIToolCall(
                id: accumulator.id ?? "tool-\(index)",
                name: accumulator.name,
                arguments: accumulator.arguments
            )
        }

        guard !fullText.isEmpty || !mergedToolCalls.isEmpty else {
            throw CustomAPIError.emptyResponse
        }
        return ChatStreamResult(
            text: fullText,
            toolCalls: mergedToolCalls
        )
    }

    private func decodeCompletion(from data: Data) throws -> String? {
        try decodeCompletionResult(from: data)?.text
    }

    private func decodeCompletionResult(
        from data: Data
    ) throws -> ChatStreamResult? {
        let decoder = JSONDecoder()
        if let error = providerError(from: data, decoder: decoder) {
            throw CustomAPIError.provider(sanitized(error))
        }
        guard let response = try? decoder.decode(
            ChatCompletionResponse.self,
            from: data
        ) else {
            return nil
        }
        let message = response.choices.first?.message
        let toolCalls = message?.toolCalls?
            .enumerated()
            .map { index, toolCall in
                APIToolCall(
                    id: toolCall.id ?? "tool-\(index)",
                    name: toolCall.function.name,
                    arguments: toolCall.function.arguments
                )
            } ?? []
        return ChatStreamResult(
            text: message?.content ?? "",
            toolCalls: toolCalls
        )
    }

    private func providerError(
        from data: Data,
        decoder: JSONDecoder
    ) -> String? {
        guard let envelope = try? decoder.decode(
            ProviderErrorEnvelope.self,
            from: data
        ), let error = envelope.error else {
            return nil
        }
        return error.message ?? error.type ?? "API 返回了未知错误"
    }

    private func collectData(
        from bytes: URLSession.AsyncBytes
    ) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if Task.isCancelled {
                throw CancellationError()
            }
            if data.count < 1_000_000 {
                data.append(byte)
            }
        }
        return data
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        fallbackBody: Data?
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CustomAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let decoder = JSONDecoder()
            let detail = fallbackBody.flatMap { body -> String? in
                if let providerMessage = providerError(
                    from: body,
                    decoder: decoder
                ) {
                    return providerMessage
                }
                return String(data: body, encoding: .utf8)
            }
            .map { sanitized(String($0.prefix(600))) }
            ?? ""
            throw CustomAPIError.httpStatus(
                httpResponse.statusCode,
                detail
            )
        }
    }

    private func sanitized(_ text: String) -> String {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            return text
        }
        return text.replacingOccurrences(of: apiKey, with: "[REDACTED]")
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [APIChatMessage]
    let stream: Bool
    let tools: [APIToolDefinition]?
    let toolChoice: APIToolChoice?

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?

            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let toolCalls: [ResponseToolCall]?

            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ToolCallDelta: Decodable {
    let index: Int
    let id: String?
    let function: FunctionDelta?

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }
}

private struct ResponseToolCall: Decodable {
    let id: String?
    let function: ResponseFunction

    struct ResponseFunction: Decodable {
        let name: String
        let arguments: String
    }
}

private struct ToolCallAccumulator {
    var id: String?
    var name = ""
    var arguments = ""
}

private struct ProviderErrorEnvelope: Decodable {
    struct ProviderError: Decodable {
        let message: String?
        let type: String?
    }

    let error: ProviderError?
}

enum CustomAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case provider(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "API 返回了无法识别的响应。"
        case .httpStatus(let status, let detail):
            if detail.isEmpty {
                return "API 请求失败（HTTP \(status)）。"
            }
            return "API 请求失败（HTTP \(status)）：\(detail)"
        case .provider(let message):
            return "API 错误：\(message)"
        case .emptyResponse:
            return "模型返回了空响应：流式和非流式请求都没有正文或可执行工具动作。"
        }
    }
}

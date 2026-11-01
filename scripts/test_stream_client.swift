import Foundation

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw TestFailure("MockURLProtocol handler 未设置")
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
struct StreamClientSmokeTest {
    static func main() async throws {
        try testEndpointNormalization()
        try testAuthorizationPreferences()
        try await testEventStream()
        try await testToolCallStream()
        try testAdvancedToolMapping()
        try await testToolResultProtocol()
        try await testForcedToolChoice()
        try await testNonStreamingToolCompletion()
        try await testStreamWithoutContentType()
        try await testNonStreamingConnection()
        try await testHTTPErrorRedaction()
        print("PASS endpoint normalization, one-click authorization, SSE, tool calls, tool replay, tool results, forced tool choice, non-stream tool fallback, advanced tools, stream fallback, redaction")
    }

    private static func testEndpointNormalization() throws {
        let deepseek = try APISettings.resolvedValues(
            provider: .deepseek,
            baseURL: "",
            model: ""
        )
        try expect(
            deepseek.baseURL == "https://api.deepseek.com/v1",
            "DeepSeek base URL preset mismatch"
        )
        try expect(
            deepseek.model == "deepseek-chat",
            "DeepSeek model preset mismatch"
        )

        let base = try APISettings.endpointURL(
            from: "https://api.example.com/v1/"
        )
        try expect(
            base.absoluteString == "https://api.example.com/v1/chat/completions",
            "base endpoint should append chat/completions"
        )

        let complete = try APISettings.endpointURL(
            from: "https://api.example.com/v1/chat/completions"
        )
        try expect(
            complete.absoluteString == "https://api.example.com/v1/chat/completions",
            "complete endpoint should not be appended twice"
        )

        _ = try APISettings.endpointURL(
            from: "http://127.0.0.1:8765"
        )
        _ = try APISettings.endpointURL(
            from: "http://[::1]:8765"
        )

        do {
            _ = try APISettings.endpointURL(
                from: "http://api.example.com/v1"
            )
            throw TestFailure("remote HTTP should be rejected")
        } catch APIConfigurationError.insecureEndpoint {
            // Expected.
        }

        do {
            _ = try APISettings.endpointURL(
                from: "https://user:secret@api.example.com/v1"
            )
            throw TestFailure("embedded credentials should be rejected")
        } catch APIConfigurationError.embeddedCredentials {
            // Expected.
        }
    }

    private static func testAuthorizationPreferences() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(
            forKey: MacControlPreferences.autoApproveKey
        )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey: MacControlPreferences.autoApproveKey
                )
            } else {
                defaults.removeObject(
                    forKey: MacControlPreferences.autoApproveKey
                )
            }
        }

        defaults.set(
            true,
            forKey: MacControlPreferences.autoApproveKey
        )
        try expect(
            MacControlPreferences.isAutoApproveEnabled,
            "one-click authorization should persist"
        )
        defaults.set(
            false,
            forKey: MacControlPreferences.autoApproveKey
        )
        try expect(
            !MacControlPreferences.isAutoApproveEnabled,
            "one-click authorization should be revocable"
        )
    }

    private static func testEventStream() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """
        MockURLProtocol.handler = { request in
            try expectRequest(
                request,
                model: "mock-model",
                stream: true,
                apiKey: "test-key"
            )
            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "text/event-stream; charset=utf-8"
                ),
                Data(sse.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: "test-key"
            ),
            session: mockSession()
        )
        var deltas: [String] = []
        let result = try await client.streamChat(
            messages: [
                APIChatMessage(role: "user", content: "hello")
            ]
        ) { delta in
            deltas.append(delta)
        }

        try expect(result == "你好", "SSE result should be 你好")
        try expect(deltas == ["你", "好"], "SSE should preserve chunk boundaries")
    }

    private static func testStreamWithoutContentType() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"好"}}]}
        data: [DONE]
        """
        MockURLProtocol.handler = { request in
            (
                response(for: request, status: 200, contentType: nil),
                Data(sse.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        let result = try await client.streamChat(
            messages: [
                APIChatMessage(role: "user", content: "hello")
            ]
        ) { _ in }
        try expect(result == "好", "SSE without Content-Type should still parse")
    }

    private static func testToolCallStream() async throws {
        let sse = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"open_application","arguments":"{\\"bundle"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"_id\\":\\"com.apple.Safari\\"}"}}]}}]}

        data: [DONE]
        """
        MockURLProtocol.handler = { request in
            try expectRequest(
                request,
                model: "mock-model",
                stream: true,
                apiKey: nil,
                expectedToolNames: [
                    "open_application",
                    "activate_application",
                    "open_url",
                ]
            )
            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "text/event-stream"
                ),
                Data(sse.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        let result = try await client.streamChatWithTools(
            messages: [
                APIChatMessage(role: "user", content: "打开 Safari")
            ],
            tools: MacControlTool.basicDefinitions
        ) { _ in }

        try expect(result.toolCalls.count == 1, "one tool call expected")
        let toolCall = try {
            guard let toolCall = result.toolCalls.first else {
                throw TestFailure("tool call missing")
            }
            return toolCall
        }()
        try expect(toolCall.id == "call_1", "tool call id mismatch")
        try expect(toolCall.name == "open_application", "tool name mismatch")
        let action = try MacControlTool.request(from: toolCall)
        try expect(action.title.contains("Safari"), "tool request title mismatch")
    }

    private static func testAdvancedToolMapping() throws {
        let expectedNames = [
            "run_applescript",
            "click_screen",
            "type_text",
            "press_key",
            "read_safari_page",
            "capture_screen",
        ]
        try expect(
            MacControlTool.advancedDefinitions.map(\.function.name)
                == expectedNames,
            "advanced tool definitions mismatch"
        )

        let availableNames = Set(
            (MacControlTool.basicDefinitions
                + MacControlTool.advancedDefinitions)
                .map(\.function.name)
        )
        let previousCalls = [
            APIToolCall(
                id: "old-click",
                name: "click_screen",
                arguments: #"{"x":480,"y":360}"#
            ),
            APIToolCall(
                id: "old-type",
                name: "type_text",
                arguments: #"{"text":"重试"}"#
            ),
        ]
        try expect(
            MacToolReplay.preferredToolName(
                from: previousCalls,
                availableToolNames: availableNames
            ) == "click_screen",
            "retry should prefer the first previous tool call"
        )
        let replayed = MacToolReplay.replay(
            previousCalls,
            matching: "click_screen"
        )
        try expect(
            replayed.map(\.name) == ["click_screen", "type_text"]
                && replayed.map(\.arguments) == previousCalls.map(\.arguments),
            "retry should replay the whole previous tool batch"
        )
        try expect(
            replayed.allSatisfy { call in
                !previousCalls.contains(where: { $0.id == call.id })
            },
            "replayed tool calls should receive fresh IDs"
        )

        let openTask = "用 Safari 打开新浪新闻并总结"
        try expect(
            MacIntentPlanner.preferredToolName(
                for: openTask,
                availableToolNames: availableNames,
                afterAction: false,
                hasCapturedScreen: false
            ) == "read_safari_page",
            "Safari observation task should use read_safari_page"
        )
        let localOpen = MacIntentPlanner.localToolCall(
            for: openTask,
            toolName: "read_safari_page"
        )
        try expect(
            localOpen?.name == "read_safari_page",
            "local Safari reader fallback mismatch"
        )
        try expect(
            MacIntentPlanner.preferredToolName(
                for: openTask,
                availableToolNames: availableNames,
                afterAction: true,
                hasCapturedScreen: true
            ) == nil,
            "Safari reader should satisfy observation intent"
        )

        let activation = try MacControlTool.request(
            from: APIToolCall(
                id: "call_activate",
                name: "activate_application",
                arguments: #"{"bundle_id":"com.apple.Safari"}"#
            )
        )
        guard case .activateApplication(let bundleID, _) = activation.kind else {
            throw TestFailure("application activation mapping failed")
        }
        try expect(
            bundleID == "com.apple.Safari",
            "application activation bundle mismatch"
        )

        let appleScript = try MacControlTool.request(
            from: APIToolCall(
                id: "call_script",
                name: "run_applescript",
                arguments: #"{"script":"return \"hello\""}"#
            )
        )
        guard case .runAppleScript(let source) = appleScript.kind else {
            throw TestFailure("AppleScript mapping failed")
        }
        try expect(source == #"return "hello""#, "AppleScript source mismatch")

        let click = try MacControlTool.request(
            from: APIToolCall(
                id: "call_click",
                name: "click_screen",
                arguments: #"{"x":320,"y":180,"button":"right"}"#
            )
        )
        guard case .clickScreen(let x, let y, let button) = click.kind else {
            throw TestFailure("screen click mapping failed")
        }
        try expect(
            x == 320 && y == 180 && button == "right",
            "screen click arguments mismatch"
        )

        let typing = try MacControlTool.request(
            from: APIToolCall(
                id: "call_type",
                name: "type_text",
                arguments: #"{"text":"主人，晚上好 🐳"}"#
            )
        )
        guard case .typeText(let text) = typing.kind else {
            throw TestFailure("Unicode typing mapping failed")
        }
        try expect(text == "主人，晚上好 🐳", "Unicode typing text mismatch")

        let shortcut = try MacControlTool.request(
            from: APIToolCall(
                id: "call_key",
                name: "press_key",
                arguments: #"{"key":"cmd+shift+4"}"#
            )
        )
        guard case .pressKey(let key) = shortcut.kind else {
            throw TestFailure("key shortcut mapping failed")
        }
        try expect(key == "cmd+shift+4", "key shortcut mismatch")

        let capture = try MacControlTool.request(
            from: APIToolCall(
                id: "call_capture",
                name: "capture_screen",
                arguments: #"{"include_ocr":false}"#
            )
        )
        guard case .captureScreen(let includeOCR) = capture.kind else {
            throw TestFailure("screen capture mapping failed")
        }
        try expect(!includeOCR, "OCR option mismatch")

        let safari = try MacControlTool.request(
            from: APIToolCall(
                id: "call_safari",
                name: "read_safari_page",
                arguments: #"{"url":"https://news.sina.com.cn/"}"#
            )
        )
        guard case .readSafariPage(let safariURL) = safari.kind else {
            throw TestFailure("Safari page reader mapping failed")
        }
        try expect(
            safariURL?.absoluteString == "https://news.sina.com.cn/",
            "Safari page reader URL mismatch"
        )
        let safariScript = MacControlService.safariPageReadScript(
            url: safariURL
        )
        try expect(
            safariScript.contains("text of front document"),
            "Safari reader should use the permission-free document text"
        )
        try expect(
            !safariScript.contains("do JavaScript"),
            "Safari reader must not require Apple Events JavaScript"
        )

        do {
            _ = try MacControlTool.request(
                from: APIToolCall(
                    id: "call_bad_click",
                    name: "click_screen",
                    arguments: #"{"x":10,"y":10,"button":"middle"}"#
                )
            )
            throw TestFailure("unsupported mouse button should fail")
        } catch MacControlError.invalidArguments {
            // Expected.
        }
    }

    private static func testToolResultProtocol() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"/(看了一眼屏幕;.20)/看见了。"}}]}
        data: [DONE]
        """
        MockURLProtocol.handler = { request in
            let bodyData = try requestBody(from: request)
            let body = try JSONSerialization.jsonObject(
                with: bodyData
            ) as? [String: Any]
            let messages = try {
                guard let messages = body?["messages"] as? [[String: Any]]
                else {
                    throw TestFailure("follow-up messages missing")
                }
                return messages
            }()
            try expect(messages.count == 2, "follow-up message count mismatch")

            let assistant = messages[0]
            try expect(
                assistant["role"] as? String == "assistant",
                "assistant tool-call role mismatch"
            )
            let calls = assistant["tool_calls"] as? [[String: Any]]
            let function = calls?.first?["function"] as? [String: Any]
            try expect(
                calls?.first?["id"] as? String == "call_capture",
                "assistant tool-call id mismatch"
            )
            try expect(
                function?["name"] as? String == "capture_screen",
                "assistant tool-call name mismatch"
            )

            let toolResult = messages[1]
            try expect(
                toolResult["role"] as? String == "tool",
                "tool result role mismatch"
            )
            try expect(
                toolResult["tool_call_id"] as? String == "call_capture",
                "tool result call id mismatch"
            )
            try expect(
                (toolResult["content"] as? String)?.contains("识别到的屏幕文字")
                    == true,
                "tool result content mismatch"
            )
            try expect(body?["tools"] == nil, "follow-up must not expose tools")

            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "text/event-stream"
                ),
                Data(sse.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        let toolCall = APIToolCall(
            id: "call_capture",
            name: "capture_screen",
            arguments: #"{"include_ocr":true}"#
        )
        let result = try await client.streamChatWithTools(
            messages: [
                APIChatMessage(
                    role: "assistant",
                    content: "",
                    toolCalls: [APIAssistantToolCall(toolCall)]
                ),
                APIChatMessage(
                    role: "tool",
                    content: "成功；识别到的屏幕文字：主人晚上好",
                    toolCallID: "call_capture"
                ),
            ],
            tools: []
        ) { _ in }
        try expect(result.text.contains("看见了"), "follow-up reply mismatch")
    }

    private static func testForcedToolChoice() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"我先看一下屏幕。"}}]}
        data: [DONE]
        """
        MockURLProtocol.handler = { request in
            let data = try requestBody(from: request)
            let body = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]
            let choice = body?["tool_choice"] as? [String: Any]
            let function = choice?["function"] as? [String: Any]
            try expect(
                choice?["type"] as? String == "function",
                "forced tool_choice type mismatch"
            )
            try expect(
                function?["name"] as? String == "capture_screen",
                "forced tool_choice function mismatch"
            )
            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "text/event-stream"
                ),
                Data(sse.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        _ = try await client.streamChatWithTools(
            messages: [
                APIChatMessage(role: "user", content: "看看当前屏幕")
            ],
            tools: MacControlTool.advancedDefinitions,
            toolChoice: .function("capture_screen")
        ) { _ in }
    }

    private static func testNonStreamingToolCompletion() async throws {
        let json = """
        {"choices":[{"message":{"content":"/(准备好了;.10)/我来操作。","tool_calls":[{"id":"call_open","type":"function","function":{"name":"open_application","arguments":"{\\"bundle_id\\":\\"com.apple.Safari\\"}"}}]}}]}
        """
        MockURLProtocol.handler = { request in
            let data = try requestBody(from: request)
            let body = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]
            try expect(
                body?["stream"] as? Bool == false,
                "non-stream tool fallback should not request SSE"
            )
            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "application/json"
                ),
                Data(json.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        let result = try await client.completeChatWithTools(
            messages: [
                APIChatMessage(role: "user", content: "打开 Safari")
            ],
            tools: MacControlTool.basicDefinitions
        )
        try expect(result.text.contains("我来操作"), "tool fallback text mismatch")
        try expect(
            result.toolCalls.first?.name == "open_application",
            "tool fallback call mismatch"
        )
    }

    private static func testNonStreamingConnection() async throws {
        let json = """
        {"choices":[{"message":{"content":"OK"}}]}
        """
        MockURLProtocol.handler = { request in
            try expectRequest(
                request,
                model: "mock-model",
                stream: false,
                apiKey: nil
            )
            return (
                response(
                    for: request,
                    status: 200,
                    contentType: "application/json"
                ),
                Data(json.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: nil
            ),
            session: mockSession()
        )
        let result = try await client.testConnection()
        try expect(result == "OK", "non-stream response should decode")
    }

    private static func testHTTPErrorRedaction() async throws {
        let secret = "super-secret-key"
        let json = """
        {"error":{"message":"invalid \(secret)","type":"authentication_error"}}
        """
        MockURLProtocol.handler = { request in
            (
                response(
                    for: request,
                    status: 401,
                    contentType: "application/json"
                ),
                Data(json.utf8)
            )
        }

        let client = CustomAPIClient(
            configuration: APIConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "mock-model",
                apiKey: secret
            ),
            session: mockSession()
        )

        do {
            _ = try await client.testConnection()
            throw TestFailure("HTTP 401 should throw")
        } catch {
            let message = error.localizedDescription
            try expect(message.contains("HTTP 401"), "error should include status")
            try expect(message.contains("[REDACTED]"), "error should redact API key")
            try expect(!message.contains(secret), "error must not expose API key")
        }
    }

    private static func expectRequest(
        _ request: URLRequest,
        model: String,
        stream: Bool,
        apiKey: String?,
        expectedToolNames: [String]? = nil
    ) throws {
        try expect(
            request.url?.absoluteString == "https://example.com/v1/chat/completions",
            "request URL mismatch"
        )
        try expect(
            request.value(forHTTPHeaderField: "Accept")
                == (stream ? "text/event-stream" : "application/json"),
            "Accept header mismatch"
        )

        let expectedAuthorization = apiKey.map { "Bearer \($0)" }
        try expect(
            request.value(forHTTPHeaderField: "Authorization")
                == expectedAuthorization,
            "Authorization header mismatch"
        )

        let bodyData = try requestBody(from: request)
        let body = try JSONSerialization.jsonObject(
            with: bodyData
        ) as? [String: Any]
        try expect(body?["model"] as? String == model, "request model mismatch")
        try expect(body?["stream"] as? Bool == stream, "request stream mismatch")
        if let expectedToolNames {
            let tools = body?["tools"] as? [[String: Any]]
            let names = tools?.compactMap {
                ($0["function"] as? [String: Any])?["name"] as? String
            }
            try expect(names == expectedToolNames, "request tools mismatch")
        }
    }

    private static func requestBody(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? TestFailure("无法读取请求体")
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        contentType: String?
    ) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

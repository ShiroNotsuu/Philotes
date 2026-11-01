import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit
import Vision

enum MacControlPreferences {
    static let enabledKey = "macControlEnabled"
    static let advancedEnabledKey = "advancedMacControlEnabled"
    static let autoApproveKey = "macAutoApproveEnabled"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: enabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isAdvancedEnabled: Bool {
        guard UserDefaults.standard.object(forKey: advancedEnabledKey) != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: advancedEnabledKey)
    }

    static var isAutoApproveEnabled: Bool {
        guard UserDefaults.standard.object(
            forKey: autoApproveKey
        ) != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: autoApproveKey)
    }
}

enum MacSystemPermission {
    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    static var hasEventPostingAccess: Bool {
        CGPreflightPostEventAccess()
    }

    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestEventPostingAccess() -> Bool {
        guard !hasEventPostingAccess else { return true }
        return CGRequestPostEventAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        guard !hasScreenRecordingAccess else { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func requestAccessibilityAndOpenSettings() {
        _ = requestAccessibilityAccess()
        _ = requestEventPostingAccess()
        openAccessibilitySettings()
    }

    static func requestScreenRecordingAndOpenSettings() {
        _ = requestScreenRecordingAccess()
        openScreenRecordingSettings()
    }

    static func requestAllAdvancedAccess() {
        _ = requestAccessibilityAccess()
        _ = requestEventPostingAccess()
        _ = requestScreenRecordingAccess()
    }

    static func requestPermissions(
        for actions: [MacActionRequest]
    ) {
        var needsAccessibility = false
        var needsScreenRecording = false

        for action in actions {
            switch action.kind {
            case .clickScreen, .typeText, .pressKey:
                needsAccessibility = true
            case .captureScreen:
                needsScreenRecording = true
            case .openApplication, .activateApplication, .openURL,
                 .runAppleScript, .readSafariPage:
                break
            }
        }

        if needsAccessibility {
            _ = requestAccessibilityAccess()
            _ = requestEventPostingAccess()
        }
        if needsScreenRecording {
            _ = requestScreenRecordingAccess()
        }
    }

    static func openAccessibilitySettings() {
        open(
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ]
        )
    }

    static func openScreenRecordingSettings() {
        open(
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            ]
        )
    }

    private static func open(_ rawURLs: [String]) {
        for rawURL in rawURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

struct MacApplicationTarget {
    let bundleID: String?
    let appName: String?

    var label: String {
        appName ?? bundleID ?? "目标应用"
    }
}

enum MacIntentPlanner {
    static func applicationTarget(
        in text: String
    ) -> MacApplicationTarget? {
        let normalized = text.lowercased()
        let applications: [(
            terms: [String],
            bundleID: String,
            appName: String
        )] = [
            (["safari", "浏览器"], "com.apple.Safari", "Safari"),
            (["备忘录", "notes"], "com.apple.Notes", "Notes"),
            (["访达", "finder"], "com.apple.finder", "Finder"),
            (["邮件", "mail"], "com.apple.mail", "Mail"),
            (["日历", "calendar"], "com.apple.iCal", "Calendar"),
            (["音乐", "music"], "com.apple.Music", "Music"),
            (["微信", "wechat"], "com.tencent.xinWeChat", "WeChat"),
            (
                ["系统设置", "system settings"],
                "com.apple.systempreferences",
                "System Settings"
            ),
        ]
        return applications.first {
            $0.terms.contains { normalized.contains($0) }
        }.map {
            MacApplicationTarget(
                bundleID: $0.bundleID,
                appName: $0.appName
            )
        }
    }

    static func requiresScreenObservation(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let directTerms = [
            "屏幕", "画面", "截图", "图片文字", "ocr",
        ]
        if directTerms.contains(where: { normalized.contains($0) }) {
            return true
        }

        let contextualTerms = [
            "页面", "网页", "浏览器", "新闻", "视频", "图表",
        ]
        let observationTerms = [
            "看", "读", "总结", "内容", "当前", "现在",
            "这个", "上面", "显示", "告诉我", "分析",
        ]
        return contextualTerms.contains(where: { normalized.contains($0) })
            && observationTerms.contains(where: { normalized.contains($0) })
    }

    static func containsOpenIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("打开")
            || normalized.contains("访问")
            || normalized.contains("open")
    }

    static func preferredToolName(
        for text: String,
        availableToolNames: Set<String>,
        afterAction: Bool,
        hasCapturedScreen: Bool
    ) -> String? {
        if applicationTarget(in: text)?.bundleID == "com.apple.Safari",
           requiresScreenObservation(text),
           !hasCapturedScreen,
           availableToolNames.contains("read_safari_page") {
            return "read_safari_page"
        }

        if !afterAction,
           containsOpenIntent(text),
           availableToolNames.contains("open_application") {
            if applicationTarget(in: text) != nil {
                return "open_application"
            }
            let normalized = text.lowercased()
            if availableToolNames.contains("open_url"),
               ["网页", "网站", "新闻", "url", "http"].contains(
                   where: normalized.contains
               ) {
                return "open_url"
            }
        }

        guard !hasCapturedScreen,
              availableToolNames.contains("capture_screen"),
              requiresScreenObservation(text)
        else {
            return nil
        }
        return "capture_screen"
    }

    static func localToolCall(
        for text: String,
        toolName: String
    ) -> APIToolCall? {
        let arguments: [String: Any]
        switch toolName {
        case "capture_screen":
            arguments = ["include_ocr": true]
        case "read_safari_page":
            if let rawURL = knownURL(in: text) ?? firstURL(in: text) {
                arguments = ["url": rawURL]
            } else {
                arguments = [:]
            }
        case "open_application", "activate_application":
            guard let target = applicationTarget(in: text) else {
                return nil
            }
            var targetArguments: [String: Any] = [:]
            if let bundleID = target.bundleID {
                targetArguments["bundle_id"] = bundleID
            }
            if let appName = target.appName {
                targetArguments["app_name"] = appName
            }
            arguments = targetArguments
        case "open_url":
            if let rawURL = firstURL(in: text) {
                arguments = ["url": rawURL]
            } else if let target = applicationTarget(in: text) {
                var targetArguments: [String: Any] = [:]
                if let bundleID = target.bundleID {
                    targetArguments["bundle_id"] = bundleID
                }
                if let appName = target.appName {
                    targetArguments["app_name"] = appName
                }
                return APIToolCall(
                    id: "local-\(UUID().uuidString)",
                    name: "open_application",
                    arguments: encodedArguments(targetArguments)
                )
            } else {
                return nil
            }
        default:
            return nil
        }

        return APIToolCall(
            id: "local-\(UUID().uuidString)",
            name: toolName,
            arguments: encodedArguments(arguments)
        )
    }

    private static func firstURL(in text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first {
                $0.lowercased().hasPrefix("http://")
                    || $0.lowercased().hasPrefix("https://")
            }
    }

    private static func knownURL(in text: String) -> String? {
        if text.contains("新浪") {
            return "https://news.sina.com.cn/"
        }
        return nil
    }

    private static func encodedArguments(
        _ arguments: [String: Any]
    ) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return encoded
    }
}

enum MacToolReplay {
    static func preferredToolName(
        from previousToolCalls: [APIToolCall],
        availableToolNames: Set<String>
    ) -> String? {
        previousToolCalls.first {
            availableToolNames.contains($0.name)
        }?.name
    }

    static func replay(
        _ previousToolCalls: [APIToolCall],
        matching toolName: String
    ) -> [APIToolCall] {
        guard previousToolCalls.contains(where: {
            $0.name == toolName
        }) else {
            return []
        }
        return previousToolCalls.map {
            APIToolCall(
                id: "local-\(UUID().uuidString)",
                name: $0.name,
                arguments: $0.arguments
            )
        }
    }
}

struct MacActionRequest: Identifiable {
    enum Kind {
        case openApplication(bundleID: String?, appName: String?)
        case activateApplication(bundleID: String?, appName: String?)
        case openURL(URL)
        case runAppleScript(String)
        case clickScreen(x: Int, y: Int, button: String)
        case typeText(String)
        case pressKey(String)
        case captureScreen(includeOCR: Bool)
        case readSafariPage(URL?)
    }

    let id = UUID()
    let toolCallID: String
    let kind: Kind
    let title: String
    let detail: String
    let systemImage: String

    var requiresForegroundApplication: Bool {
        switch kind {
        case .clickScreen, .typeText, .pressKey, .captureScreen:
            return true
        case .openApplication, .activateApplication, .openURL,
             .runAppleScript, .readSafariPage:
            return false
        }
    }
}

enum MacControlTool {
    static let basicDefinitions: [APIToolDefinition] = [
        APIToolDefinition(
            name: "open_application",
            description: """
            Propose opening a macOS application. Use bundle_id when known. \
            Common bundle IDs: Safari com.apple.Safari, Notes com.apple.Notes, \
            Calendar com.apple.iCal, Mail com.apple.mail, Music com.apple.Music, \
            WeChat com.tencent.xinWeChat. Philotes handles confirmation or the \
            user's one-click authorization before execution.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "bundle_id": APIToolParameterProperty(
                        type: "string",
                        description: "The macOS application bundle identifier."
                    ),
                    "app_name": APIToolParameterProperty(
                        type: "string",
                        description: "The visible application name when no bundle ID is known."
                    ),
                ],
                required: []
            )
        ),
        APIToolDefinition(
            name: "activate_application",
            description: """
            Bring an already running macOS application to the foreground before \
            clicking, typing, pressing keys, or inspecting its window. Philotes \
            handles confirmation or the user's one-click authorization.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "bundle_id": APIToolParameterProperty(
                        type: "string",
                        description: "The macOS application bundle identifier."
                    ),
                    "app_name": APIToolParameterProperty(
                        type: "string",
                        description: "The visible application name when no bundle ID is known."
                    ),
                ],
                required: []
            )
        ),
        APIToolDefinition(
            name: "open_url",
            description: """
            Propose opening an HTTP or HTTPS URL in the user's default browser. \
            Philotes handles confirmation or the user's one-click authorization.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "url": APIToolParameterProperty(
                        type: "string",
                        description: "A complete http:// or https:// URL."
                    ),
                ],
                required: ["url"]
            )
        ),
    ]

    static let advancedDefinitions: [APIToolDefinition] = [
        APIToolDefinition(
            name: "run_applescript",
            description: """
            Propose running a macOS AppleScript. AppleScript can modify \
            applications and data. Philotes handles confirmation or the user's \
            one-click authorization, then returns the script output as a tool \
            result. Never claim it ran before execution.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "script": APIToolParameterProperty(
                        type: "string",
                        description: "The complete AppleScript source to execute."
                    ),
                ],
                required: ["script"]
            )
        ),
        APIToolDefinition(
            name: "click_screen",
            description: """
            Propose clicking a point in the global macOS screen coordinate space. \
            Requires Accessibility permission and Philotes authorization. \
            If the target coordinate is unknown, request capture_screen first.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "x": APIToolParameterProperty(
                        type: "integer",
                        description: "Horizontal screen coordinate."
                    ),
                    "y": APIToolParameterProperty(
                        type: "integer",
                        description: "Vertical screen coordinate."
                    ),
                    "button": APIToolParameterProperty(
                        type: "string",
                        description: "Mouse button: left or right. Defaults to left."
                    ),
                ],
                required: ["x", "y"]
            )
        ),
        APIToolDefinition(
            name: "type_text",
            description: """
            Propose typing Unicode text into the currently focused control. Requires \
            Accessibility permission and Philotes authorization.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "text": APIToolParameterProperty(
                        type: "string",
                        description: "The exact text to type."
                    ),
                ],
                required: ["text"]
            )
        ),
        APIToolDefinition(
            name: "press_key",
            description: """
            Propose pressing a key or shortcut, for example return, escape, tab, \
            cmd+c, cmd+shift+4, or an arrow key. Requires Accessibility permission \
            and Philotes authorization.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "key": APIToolParameterProperty(
                        type: "string",
                        description: "Key or plus-separated shortcut."
                    ),
                ],
                required: ["key"]
            )
        ),
        APIToolDefinition(
            name: "read_safari_page",
            description: """
            Activate Safari, optionally open a URL, and read the current page's \
            title, URL, and visible body text. Use this for summarizing a web page \
            instead of taking repeated screenshots. Philotes handles confirmation \
            or the user's one-click authorization first.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "url": APIToolParameterProperty(
                        type: "string",
                        description: "Optional HTTP or HTTPS URL to open before reading."
                    ),
                ],
                required: []
            )
        ),
        APIToolDefinition(
            name: "capture_screen",
            description: """
            Propose a one-time screenshot of the main display. The screenshot stays \
            local and Vision OCR text is returned to the model. Requires Screen \
            Recording permission and Philotes authorization.
            """,
            parameters: APIToolParameterSchema(
                properties: [
                    "include_ocr": APIToolParameterProperty(
                        type: "boolean",
                        description: "Whether to extract text. Defaults to true."
                    ),
                ],
                required: []
            )
        ),
    ]

    static var enabledDefinitions: [APIToolDefinition] {
        basicDefinitions
            + (MacControlPreferences.isAdvancedEnabled ? advancedDefinitions : [])
    }

    static func request(from toolCall: APIToolCall) throws -> MacActionRequest {
        let data = Data(toolCall.arguments.utf8)
        let object = (
            try? JSONSerialization.jsonObject(with: data)
        ) as? [String: Any]
        let arguments = object ?? [:]

        switch toolCall.name {
        case "open_application":
            let bundleID = nonEmptyString(arguments["bundle_id"])
            let appName = nonEmptyString(arguments["app_name"])
            guard bundleID != nil || appName != nil else {
                throw MacControlError.invalidArguments(
                    "打开应用时需要 bundle_id 或 app_name。"
                )
            }
            let label = appName ?? bundleID ?? L10n.string("应用")
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .openApplication(
                    bundleID: bundleID,
                    appName: appName
                ),
                title: L10n.format("打开 %@", label),
                detail: bundleID.map {
                    L10n.format("应用标识：%@", $0)
                } ?? L10n.string("将通过应用名称定位并打开。"),
                systemImage: "app.dashed"
            )

        case "activate_application":
            let bundleID = nonEmptyString(arguments["bundle_id"])
            let appName = nonEmptyString(arguments["app_name"])
            guard bundleID != nil || appName != nil else {
                throw MacControlError.invalidArguments(
                    "激活应用时需要 bundle_id 或 app_name。"
                )
            }
            let label = appName ?? bundleID ?? L10n.string("应用")
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .activateApplication(
                    bundleID: bundleID,
                    appName: appName
                ),
                title: L10n.format("切换到 %@", label),
                detail: L10n.string("执行后续键鼠或截图前，先把目标应用带到前台。"),
                systemImage: "macwindow.on.rectangle"
            )

        case "open_url":
            guard let rawURL = nonEmptyString(arguments["url"]),
                  let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                throw MacControlError.invalidArguments(
                    "URL 必须是完整的 http 或 https 地址。"
                )
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .openURL(url),
                title: L10n.string("打开网页"),
                detail: url.absoluteString,
                systemImage: "safari"
            )

        case "run_applescript":
            guard let script = nonEmptyString(arguments["script"]),
                  script.count <= 20_000
            else {
                throw MacControlError.invalidArguments(
                    "AppleScript 不能为空，且不能超过 20,000 个字符。"
                )
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .runAppleScript(script),
                title: L10n.string("运行 AppleScript"),
                detail: script,
                systemImage: "terminal"
            )

        case "click_screen":
            guard let x = integer(arguments["x"]),
                  let y = integer(arguments["y"]),
                  (0...20_000).contains(x),
                  (0...20_000).contains(y)
            else {
                throw MacControlError.invalidArguments(
                    "点击坐标无效。"
                )
            }
            let button = (nonEmptyString(arguments["button"]) ?? "left")
                .lowercased()
            guard button == "left" || button == "right" else {
                throw MacControlError.invalidArguments(
                    "鼠标按钮只支持 left 或 right。"
                )
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .clickScreen(x: x, y: y, button: button),
                title: L10n.format(
                    "%@屏幕",
                    L10n.string(button == "right" ? "右键" : "点击")
                ),
                detail: L10n.format("全局坐标 (%lld, %lld)", Int64(x), Int64(y)),
                systemImage: "cursorarrow"
            )

        case "type_text":
            guard let text = nonEmptyString(arguments["text"]),
                  text.count <= 10_000
            else {
                throw MacControlError.invalidArguments(
                    "输入文本不能为空，且不能超过 10,000 个字符。"
                )
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .typeText(text),
                title: L10n.string("输入文本"),
                detail: text,
                systemImage: "keyboard"
            )

        case "press_key":
            guard let key = nonEmptyString(arguments["key"]) else {
                throw MacControlError.invalidArguments(
                    "请指定要按下的按键或快捷键。"
                )
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .pressKey(key),
                title: L10n.string("按键"),
                detail: key,
                systemImage: "command"
            )

        case "capture_screen":
            let includeOCR = arguments["include_ocr"] as? Bool ?? true
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .captureScreen(includeOCR: includeOCR),
                title: L10n.string("读取主屏幕快照"),
                detail: includeOCR
                    ? L10n.string("截图保存在本机，并提取屏幕文字供模型参考。")
                    : L10n.string("截图只保存在本机。"),
                systemImage: "camera.viewfinder"
            )

        case "read_safari_page":
            let url: URL?
            if let rawURL = nonEmptyString(arguments["url"]) {
                guard let parsed = URL(string: rawURL),
                      let scheme = parsed.scheme?.lowercased(),
                      scheme == "http" || scheme == "https"
                else {
                    throw MacControlError.invalidArguments(
                        "Safari 页面 URL 必须是完整的 http 或 https 地址。"
                    )
                }
                url = parsed
            } else {
                url = nil
            }
            return MacActionRequest(
                toolCallID: toolCall.id,
                kind: .readSafariPage(url),
                title: L10n.string("读取 Safari 页面"),
                detail: url?.absoluteString
                    ?? L10n.string("读取 Safari 当前标签页的标题与正文。"),
                systemImage: "safari"
            )

        default:
            throw MacControlError.unsupportedTool(toolCall.name)
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

enum MacControlService {
    @MainActor
    static func targetApplication(
        for request: MacActionRequest
    ) -> MacApplicationTarget? {
        switch request.kind {
        case .openApplication(let bundleID, let appName),
             .activateApplication(let bundleID, let appName):
            guard let url = resolveApplication(
                bundleID: bundleID,
                appName: appName
            ) else {
                return nil
            }
            return targetApplication(at: url)

        case .openURL(let url):
            guard let appURL = NSWorkspace.shared.urlForApplication(
                toOpen: url
            ) else {
                return nil
            }
            return targetApplication(at: appURL)

        case .runAppleScript, .clickScreen, .typeText, .pressKey,
             .captureScreen, .readSafariPage:
            return nil
        }
    }

    @MainActor
    static func execute(
        _ request: MacActionRequest,
        foregroundApplication: MacApplicationTarget? = nil
    ) async throws -> String {
        if request.requiresForegroundApplication,
           let foregroundApplication {
            try await activateApplication(
                bundleID: foregroundApplication.bundleID,
                appName: foregroundApplication.appName
            )
        }

        switch request.kind {
        case .openURL(let url):
            guard NSWorkspace.shared.open(url) else {
                throw MacControlError.executionFailed("系统没有打开这个网页。")
            }
            return "已打开网页：\(url.absoluteString)"

        case .openApplication(let bundleID, let appName):
            guard let applicationURL = resolveApplication(
                bundleID: bundleID,
                appName: appName
            ) else {
                throw MacControlError.applicationNotFound(
                    appName ?? bundleID ?? "指定应用"
                )
            }
            try await launchApplication(at: applicationURL)
            return "已打开应用：\(applicationURL.deletingPathExtension().lastPathComponent)"

        case .activateApplication(let bundleID, let appName):
            try await activateApplication(
                bundleID: bundleID,
                appName: appName
            )
            return "已将应用带到前台：\(appName ?? bundleID ?? "目标应用")"

        case .runAppleScript(let source):
            return try runAppleScript(source)

        case .clickScreen(let x, let y, let button):
            try ensureAccessibilityPermission()
            postMouseClick(
                at: CGPoint(x: x, y: y),
                rightButton: button == "right"
            )
            return "已在屏幕坐标 (\(x), \(y)) 执行\(button == "right" ? "右键" : "左键")点击。"

        case .typeText(let text):
            try ensureAccessibilityPermission()
            try postUnicodeText(text)
            return "已向当前焦点控件输入 \(text.count) 个字符。"

        case .pressKey(let key):
            try ensureAccessibilityPermission()
            try postKeyCombination(key)
            return "已发送按键：\(key)"

        case .captureScreen(let includeOCR):
            return try await captureMainDisplay(includeOCR: includeOCR)

        case .readSafariPage(let url):
            return try readSafariPage(url: url)
        }
    }

    private static func readSafariPage(url: URL?) throws -> String {
        let source = safariPageReadScript(url: url)
        let output = try executeAppleScript(source)
        return String(output.prefix(9_000))
    }

    static func safariPageReadScript(url: URL?) -> String {
        let openStatement: String
        if let url {
            openStatement = """
            set URL of front document to "\(appleScriptEscaped(url.absoluteString))"
            delay 1.5
            """
        } else {
            openStatement = ""
        }

        return """
        tell application "Safari"
            activate
            delay 0.8
            if (count of windows) = 0 then
                make new document
            end if
            \(openStatement)
            set pageTitle to name of front document
            set pageURL to URL of front document
            set pageText to text of front document
            if (length of pageText) > 12000 then
                set pageText to text 1 thru 12000 of pageText
            end if
            return pageTitle & linefeed & pageURL & linefeed & pageText
        end tell
        """
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) throws -> String {
        let output = try executeAppleScript(source)
        if output.isEmpty {
            return "AppleScript 已执行完成。"
        }
        return "AppleScript 输出：\(String(output.prefix(4_000)))"
    }

    private static func executeAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw MacControlError.executionFailed("无法创建 AppleScript。")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "AppleScript 执行失败。"
            let code = errorInfo[NSAppleScript.errorNumber] as? Int
            if code == -1743 || code == -1744 {
                throw MacControlError.appleEventsPermissionRequired
            }
            throw MacControlError.executionFailed(message)
        }
        return result.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func ensureAccessibilityPermission() throws {
        let accessibilityGranted =
            MacSystemPermission.requestAccessibilityAccess()
        let postingGranted =
            MacSystemPermission.requestEventPostingAccess()
        guard accessibilityGranted, postingGranted else {
            throw MacControlError.accessibilityPermissionRequired
        }
    }

    private static func postMouseClick(
        at point: CGPoint,
        rightButton: Bool
    ) {
        let downType: CGEventType = rightButton ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightButton ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = rightButton ? .right : .left
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
        CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }

    private static func postUnicodeText(_ text: String) throws {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)

        // A single CGEvent Unicode payload is intentionally small. Chunking
        // also avoids truncating long Chinese text and composed emoji.
        var cursor = 0
        while cursor < units.count {
            var end = min(cursor + 20, units.count)
            if end < units.count,
               (0xD800...0xDBFF).contains(units[end - 1]),
               (0xDC00...0xDFFF).contains(units[end]) {
                end -= 1
            }
            guard end > cursor,
                  let keyDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: true
                  ),
                  let keyUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: false
                  )
            else {
                throw MacControlError.executionFailed("无法创建键盘输入事件。")
            }

            units[cursor..<end].withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
                keyUp.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            cursor = end

            if cursor < units.count {
                Thread.sleep(forTimeInterval: 0.004)
            }
        }
    }

    private static func postKeyCombination(_ raw: String) throws {
        let parts = raw
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let keyName = parts.last else {
            throw MacControlError.invalidArguments("按键不能为空。")
        }

        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default:
                throw MacControlError.invalidArguments(
                    "不支持的修饰键：\(modifier)"
                )
            }
        }

        guard let keyCode = keyCode(for: keyName) else {
            throw MacControlError.invalidArguments(
                "不支持的按键：\(keyName)"
            )
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        let keyCodes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4,
            "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20,
            "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
            "7": 26, "-": 27, "8": 28, "0": 29, "]": 30,
            "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "return": 36, "enter": 36, "l": 37, "j": 38,
            "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48,
            "space": 49, "`": 50, "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53, "left": 123, "right": 124,
            "down": 125, "up": 126, "home": 115, "end": 119,
            "pageup": 116, "pagedown": 121,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        return keyCodes[key]
    }

    private static func captureMainDisplay(
        includeOCR: Bool
    ) async throws -> String {
        guard MacSystemPermission.requestScreenRecordingAccess() else {
            throw MacControlError.screenRecordingPermissionRequired
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw MacControlError.screenRecordingPermissionRequired
        }

        guard let display = content.displays.first(where: {
            $0.displayID == CGMainDisplayID()
        }) ?? content.displays.first else {
            throw MacControlError.executionFailed("没有找到可捕获的显示器。")
        }

        let filter = SCContentFilter(
            display: display,
            excludingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let screenshotURL = try saveScreenshot(image)

        guard includeOCR else {
            return "主屏幕快照已保存在本机：\(screenshotURL.path)"
        }
        let text = try recognizeText(in: image)
        if text.isEmpty {
            return """
            主屏幕快照已保存在本机：\(screenshotURL.path)
            没有识别到可读文字。
            """
        }
        return """
        主屏幕快照已保存在本机：\(screenshotURL.path)
        识别到的屏幕文字如下：
        \(text)
        """
    }

    private static func saveScreenshot(_ image: CGImage) throws -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = support
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw MacControlError.executionFailed("无法编码屏幕截图。")
        }
        let url = directory.appendingPathComponent(
            "screen-\(UUID().uuidString).png"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        return String(lines.joined(separator: "\n").prefix(8_000))
    }

    private static func resolveApplication(
        bundleID: String?,
        appName: String?
    ) -> URL? {
        if let bundleID,
           let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
           ) {
            return applicationURL
        }
        guard let appName else { return nil }
        return findApplication(named: appName)
    }

    private static func targetApplication(
        at applicationURL: URL
    ) -> MacApplicationTarget {
        MacApplicationTarget(
            bundleID: Bundle(url: applicationURL)?.bundleIdentifier,
            appName: applicationURL
                .deletingPathExtension()
                .lastPathComponent
        )
    }

    private static func activateApplication(
        bundleID: String?,
        appName: String?
    ) async throws {
        guard let applicationURL = resolveApplication(
            bundleID: bundleID,
            appName: appName
        ) else {
            throw MacControlError.applicationNotFound(
                appName ?? bundleID ?? "指定应用"
            )
        }
        let resolvedBundleID = bundleID
            ?? Bundle(url: applicationURL)?.bundleIdentifier
        let running = resolvedBundleID.flatMap {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: $0
            ).first
        }

        if let running {
            let activated = running.activate(
                options: [.activateAllWindows]
            )
            guard activated else {
                throw MacControlError.executionFailed(
                    "系统没有把\(running.localizedName ?? appName ?? "目标应用")切到前台。"
                )
            }
            return
        }
        try await launchApplication(at: applicationURL)
    }

    private static func findApplication(named rawName: String) -> URL? {
        var appName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty,
              !appName.contains("/"),
              !appName.contains("..")
        else {
            return nil
        }
        if appName.lowercased().hasSuffix(".app") {
            appName = String(appName.dropLast(4))
        }

        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeApplications,
        ]

        for root in roots {
            let direct = root
                .appendingPathComponent(appName, isDirectory: true)
                .appendingPathExtension("app")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }

            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            var scanned = 0
            for case let candidate as URL in enumerator {
                scanned += 1
                if scanned > 2_000 {
                    break
                }
                guard candidate.pathExtension.lowercased() == "app" else {
                    continue
                }
                if candidate.deletingPathExtension().lastPathComponent
                    .localizedCaseInsensitiveCompare(appName) == .orderedSame {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func launchApplication(at url: URL) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application == nil {
                    continuation.resume(
                        throwing: MacControlError.executionFailed(
                            "系统没有返回已启动的应用。"
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum MacControlError: LocalizedError {
    case unsupportedTool(String)
    case invalidArguments(String)
    case applicationNotFound(String)
    case executionFailed(String)
    case accessibilityPermissionRequired
    case appleEventsPermissionRequired
    case screenRecordingPermissionRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let name):
            return "模型请求了不支持的 Mac 操作：\(name)"
        case .invalidArguments(let message):
            return message
        case .applicationNotFound(let name):
            return "没有找到应用“\(name)”。"
        case .executionFailed(let message):
            return message
        case .accessibilityPermissionRequired:
            return """
            键鼠事件权限尚未开启。请在系统设置 → 隐私与安全性 → \
            装置控制和资料取用中，同时允许 Philotes 的辅助功能与键鼠事件合成权限。
            """
        case .appleEventsPermissionRequired:
            return "请在系统设置 → 隐私与安全性 → 自动化中允许 Philotes 控制目标应用。"
        case .screenRecordingPermissionRequired:
            return "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Philotes。"
        }
    }
}

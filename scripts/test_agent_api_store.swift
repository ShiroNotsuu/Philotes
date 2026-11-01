import AppKit
import Foundation

@main
struct AgentAPIPersistenceSmokeTest {
    static func main() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-agent-api-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }

        let store = try DatabaseStore(databaseURL: databaseURL)
        let deepseekID = try store.createAgent(
            name: "DeepSeek Agent",
            role: "测试",
            emoji: "🐟",
            accent: "blue",
            apiProvider: AgentAPIProvider.deepseek.rawValue,
            apiBaseURL: AgentAPIProvider.deepseek.defaultBaseURL,
            apiModel: AgentAPIProvider.deepseek.defaultModel
        )
        let customID = try store.createAgent(
            name: "Custom Agent",
            role: "测试",
            emoji: "✨",
            accent: "mint",
            apiProvider: AgentAPIProvider.custom.rawValue,
            apiBaseURL: "https://example.com/v1",
            apiModel: "custom-model"
        )
        let noneID = try store.createAgent(
            name: "Offline Agent",
            role: "测试",
            emoji: "🌙",
            accent: "lavender",
            apiProvider: AgentAPIProvider.none.rawValue,
            apiBaseURL: "",
            apiModel: ""
        )

        var agents = try store.loadAgents()
        let deepseek = try agent(id: deepseekID, in: agents)
        let custom = try agent(id: customID, in: agents)
        let none = try agent(id: noneID, in: agents)

        try expect(deepseek.apiProvider == "deepseek", "DeepSeek provider mismatch")
        try expect(
            deepseek.apiBaseURL == "https://api.deepseek.com/v1",
            "DeepSeek base URL mismatch"
        )
        try expect(deepseek.apiModel == "deepseek-chat", "DeepSeek model mismatch")
        try expect(custom.apiProvider == "custom", "custom provider mismatch")
        try expect(
            custom.apiBaseURL == "https://example.com/v1",
            "custom base URL mismatch"
        )
        try expect(custom.apiModel == "custom-model", "custom model mismatch")
        try expect(none.apiProvider == "none", "none provider mismatch")

        try store.updateAgentSettings(
            id: customID,
            emoji: custom.emoji,
            avatarImagePath: "/tmp/philotes-test-avatar.png",
            accent: custom.accent,
            apiProvider: AgentAPIProvider.deepseek.rawValue,
            apiBaseURL: "https://proxy.example.com/v1",
            apiModel: "deepseek-reasoner"
        )
        agents = try store.loadAgents()
        let updated = try agent(id: customID, in: agents)
        try expect(updated.apiProvider == "deepseek", "updated provider mismatch")
        try expect(
            updated.apiBaseURL == "https://proxy.example.com/v1",
            "updated base URL mismatch"
        )
        try expect(
            updated.apiModel == "deepseek-reasoner",
            "updated model mismatch"
        )
        try expect(
            updated.avatarImagePath == "/tmp/philotes-test-avatar.png",
            "updated avatar path mismatch"
        )
        try expect(
            deepseek.apiProvider == "deepseek" && updated.apiProvider == "deepseek",
            "agents should keep independent API records"
        )

        let personaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-personas-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: personaDirectory)
        }
        let persona = AgentPersonaDraft(
            name: "潮汐",
            emoji: "🐟",
            relationship: "情绪知己",
            gender: "自定义：没有固定的性别表达",
            age: "青年感",
            personality: ["温柔", "敏锐", "自定义：偶尔会讲很冷的笑话"],
            speakingStyle: ["简洁", "有诗意"],
            initiative: "平衡",
            emotionalExpression: "自然",
            address: "主人",
            additionalDetails: "它重视边界感，也喜欢在海边散步。api_key=super-secret"
        )
        try AgentPersonaStore.write(
            persona,
            for: customID,
            directoryURL: personaDirectory
        )
        let markdown = try unwrap(
            AgentPersonaStore.load(
                for: customID,
                directoryURL: personaDirectory
            )
        )
        try expect(markdown.contains("# 潮汐 的人格档案"), "persona title mismatch")
        try expect(
            markdown.contains("偶尔会讲很冷的笑话"),
            "custom personality description missing"
        )
        try expect(
            markdown.contains("它重视边界感"),
            "additional persona description missing"
        )
        try expect(!markdown.contains("API Key"), "persona must not contain credentials")
        try expect(
            !markdown.contains("super-secret")
                && markdown.contains("[已隐藏的凭据]"),
            "persona credentials should be redacted"
        )

        let summary = try unwrap(AgentPersonaSummary(markdown: markdown))
        try expect(
            summary.fields.contains {
                $0.label == "性格气质" && $0.value.contains("温柔")
            },
            "persona summary fields mismatch"
        )
        try expect(
            summary.additionalDetails.contains("它重视边界感"),
            "persona summary details mismatch"
        )

        let profileSuiteName = "PhilotesProfileTest-\(UUID().uuidString)"
        let profileDefaults = try unwrap(
            UserDefaults(suiteName: profileSuiteName)
        )
        defer {
            profileDefaults.removePersistentDomain(forName: profileSuiteName)
        }
        let savedNickname = UserProfileStore.saveNickname(
            "  小鱼  ",
            defaults: profileDefaults
        )
        try expect(savedNickname == "小鱼", "nickname trimming mismatch")
        try expect(
            UserProfileStore.loadNickname(defaults: profileDefaults) == "小鱼",
            "nickname persistence mismatch"
        )
        let fallbackNickname = UserProfileStore.saveNickname(
            "   ",
            defaults: profileDefaults
        )
        try expect(
            fallbackNickname == UserProfileStore.defaultNickname,
            "empty nickname fallback mismatch"
        )

        let avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-user-avatar-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: avatarRoot)
        }
        let sourceImage = NSImage(size: NSSize(width: 32, height: 32))
        sourceImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        sourceImage.unlockFocus()
        let tiff = try unwrap(sourceImage.tiffRepresentation)
        let bitmap = try unwrap(NSBitmapImageRep(data: tiff))
        let avatarData = try unwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        let savedAvatarPath = try UserAvatarStore.importImage(
            data: avatarData,
            baseURL: avatarRoot
        )
        try expect(
            FileManager.default.fileExists(atPath: savedAvatarPath),
            "user avatar data import mismatch"
        )

        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-vaults-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let preference = try store.createMemory(
            agentID: customID,
            kind: "preference",
            title: "喜欢海边",
            summary: "主人喜欢在海边散步。",
            source: "测试对话"
        )
        let sensitiveMemory = try store.createMemory(
            agentID: customID,
            kind: "fact",
            title: "敏感测试",
            summary: "这条正文不应写入 Markdown。",
            source: "测试对话",
            isSensitive: true
        )
        let customMemories = try store.loadMemoryNodes().filter {
            $0.agentID == customID
        }
        let vaultURL = try AgentMemoryVaultStore.ensureVault(
            for: custom,
            memories: customMemories,
            links: [],
            personaMarkdown: markdown,
            baseURL: vaultRoot
        )
        let categorySummaries = AgentMemoryVaultStore.categorySummaries(
            for: customID,
            baseURL: vaultRoot
        )
        try expect(
            categorySummaries.first {
                $0.category == .memory
            }?.count == 2,
            "vault memory category count mismatch"
        )
        let indexURL = vaultURL
            .appendingPathComponent("00-导航/总索引.md")
        let personaVaultURL = vaultURL
            .appendingPathComponent("01-人格/人格档案.md")
        let memoryVaultURL = vaultURL
            .appendingPathComponent("02-记忆/节点/M-\(preference.id).md")
        let sensitiveVaultURL = vaultURL
            .appendingPathComponent(
                "02-记忆/节点/M-\(sensitiveMemory.id).md"
            )
        try expect(
            FileManager.default.fileExists(atPath: indexURL.path),
            "agent vault index missing"
        )
        let personaVaultMarkdown = try String(
            contentsOf: personaVaultURL,
            encoding: .utf8
        )
        try expect(
            personaVaultMarkdown.contains("# 潮汐 的人格档案"),
            "agent vault persona mirror missing"
        )
        let memoryMarkdown = try String(
            contentsOf: memoryVaultURL,
            encoding: .utf8
        )
        try expect(
            memoryMarkdown.contains("喜欢海边")
                && memoryMarkdown.contains("主人喜欢在海边散步"),
            "agent vault memory node mismatch"
        )
        let sensitiveMarkdown = try String(
            contentsOf: sensitiveVaultURL,
            encoding: .utf8
        )
        try expect(
            sensitiveMarkdown.contains("sensitive: true")
                && !sensitiveMarkdown.contains("这条正文不应写入 Markdown"),
            "sensitive memory body should not be mirrored"
        )
        let vaultContext = AgentMemoryVaultStore.contextExcerpt(
            for: custom,
            query: "主人喜欢去哪里散步？",
            baseURL: vaultRoot
        )
        try expect(
            vaultContext.contains("喜欢海边"),
            "relevant vault memory should enter context"
        )
        try expect(
            !vaultContext.contains("这条正文不应写入 Markdown"),
            "sensitive memory should stay out of context"
        )
        let memoryPreview = AgentMemoryVaultStore.previewMarkdown(
            for: .memory,
            agentID: customID,
            baseURL: vaultRoot
        ) ?? ""
        try expect(
            memoryPreview.contains("喜欢海边"),
            "memory category Markdown preview mismatch"
        )
        let individualMemoryPreview = AgentMemoryVaultStore.previewMarkdown(
            forMemoryID: preference.id,
            agentID: customID,
            baseURL: vaultRoot
        ) ?? ""
        try expect(
            individualMemoryPreview.contains("主人喜欢在海边散步"),
            "individual memory Markdown preview mismatch"
        )

        let diaryDate = Date()
        try AgentMemoryVaultStore.appendMessage(
            ChatMessage(
                id: 9_001,
                role: .user,
                body: "今天想去海边散步。",
                createdAt: diaryDate
            ),
            for: custom,
            baseURL: vaultRoot
        )
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let diaryURL = vaultURL
            .appendingPathComponent(
                "04-日记/\(dayFormatter.string(from: diaryDate)).md"
            )
        let diaryMarkdown = try String(
            contentsOf: diaryURL,
            encoding: .utf8
        )
        try expect(
            diaryMarkdown.contains("今天想去海边散步"),
            "agent diary append mismatch"
        )
        let diarySummary = AgentMemoryVaultStore.categorySummaries(
            for: customID,
            baseURL: vaultRoot
        ).first {
            $0.category == .diary
        }
        try expect(diarySummary?.count == 1, "vault diary category count mismatch")
        try expect(
            AgentMemoryVaultStore.extractExplicitMemory(
                from: "请记住，我喜欢喝无糖乌龙茶。"
            )?.kind == "preference",
            "explicit preference extraction mismatch"
        )
        try expect(
            AgentMemoryVaultStore.extractExplicitMemory(
                from: "记住密码是 123456"
            ) == nil,
            "credential-like text must not become memory"
        )

        let parsed = AssistantResponseParser.parse(
            "/(轻轻靠近，眼神柔和)/ 主人，晚上好。"
        )
        try expect(
            parsed.action == "轻轻靠近，眼神柔和",
            "action prompt mismatch"
        )
        try expect(parsed.body == "主人，晚上好。", "reply body mismatch")

        let fullWidth = AssistantResponseParser.parse(
            "/（微微歪头）/ 我在听。"
        )
        try expect(fullWidth.action == "微微歪头", "full-width action mismatch")
        try expect(fullWidth.body == "我在听。", "full-width body mismatch")

        let partial = AssistantResponseParser.parse("/(正在靠近")
        try expect(
            partial.isAwaitingActionClose
                && partial.action == nil
                && partial.body.isEmpty,
            "partial action marker should be withheld"
        )

        let emotion = AssistantResponseParser.parse(
            "/(轻轻靠近，眼神温柔;.-42;.energy=low)/ 主人，先休息一下吧。"
        )
        try expect(emotion.emotionValue == -42, "emotion value mismatch")
        try expect(emotion.metadata == ["energy=low"], "metadata mismatch")
        try expect(
            emotion.body == "主人，先休息一下吧。",
            "emotion response body mismatch"
        )

        let clampedEmotion = AssistantResponseParser.parse(
            "/(很激动;.180)/ 太好了！"
        )
        try expect(
            clampedEmotion.emotionValue == 100,
            "emotion value should clamp to 100"
        )
        try expect(
            EmotionScale.label(for: -80) == "很低落"
                && EmotionScale.label(for: 0) == "平静"
                && EmotionScale.label(for: 90) == "非常高涨",
            "emotion scale labels mismatch"
        )

        let missingTrailingSlash = AssistantResponseParser.parse(
            "/(认真地看了一会儿，语气温和;.5) 我确实还在。"
        )
        try expect(
            missingTrailingSlash.emotionValue == 5,
            "bare closing emotion mismatch"
        )
        try expect(
            missingTrailingSlash.body == "我确实还在。",
            "bare closing body mismatch"
        )

        let plain = AssistantResponseParser.parse("普通回复")
        try expect(
            plain.action == nil && plain.body == "普通回复",
            "plain response should remain unchanged"
        )

        try store.createMemory(
            agentID: noneID,
            kind: "fact",
            title: "待删除测试记忆",
            summary: "删除智能体时应一并移除。",
            source: "测试"
        )
        try store.appendMessage(
            agentID: noneID,
            role: .user,
            body: "待删除测试消息"
        )
        let memoriesBeforeDeletion = try store.loadMemoryNodes()
        let messagesBeforeDeletion = try store.loadMessages(for: noneID)
        try expect(
            memoriesBeforeDeletion.contains { $0.agentID == noneID },
            "test agent should have memories before deletion"
        )
        try expect(
            messagesBeforeDeletion.isEmpty == false,
            "test agent should have messages before deletion"
        )
        try store.deleteAgentData(id: noneID)
        let agentsAfterDeletion = try store.loadAgents()
        let memoriesAfterDeletion = try store.loadMemoryNodes()
        let messagesAfterDeletion = try store.loadMessages(for: noneID)
        try expect(
            agentsAfterDeletion.contains { $0.id == noneID } == false,
            "deleted agent should be removed"
        )
        try expect(
            memoriesAfterDeletion.contains { $0.agentID == noneID } == false,
            "deleted agent memories should be removed"
        )
        try expect(
            messagesAfterDeletion.isEmpty,
            "deleted agent messages should be removed"
        )

        print("PASS per-agent API, persona, Markdown vault, parser, and deletion")
    }

    private static func agent(
        id: Int64,
        in agents: [AgentProfile]
    ) throws -> AgentProfile {
        guard let agent = agents.first(where: { $0.id == id }) else {
            throw TestFailure("agent \(id) not found")
        }
        return agent
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else {
            throw TestFailure("expected non-nil value")
        }
        return value
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

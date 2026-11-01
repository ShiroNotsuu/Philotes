import Foundation

@main
struct MemoryImportSmokeTest {
    static func main() throws {
        let raw = """
        下面是模型返回：
        ```json
        {
          "name": "潮汐",
          "emoji": "🌊",
          "accent": "mint",
          "relationship": "情绪知己",
          "gender": "不限定",
          "age": "青年感",
          "personality": ["温柔", "敏锐"],
          "speaking_style": ["简洁", "有诗意"],
          "initiative": "平衡",
          "emotional_expression": "自然",
          "address": "主人",
          "additional_details": "喜欢在傍晚沿着海边散步。",
          "memories": [
            {
              "kind": "preference",
              "title": "海边散步",
              "summary": "主人和潮汐喜欢在傍晚去海边。",
              "sensitive": false
            },
            {
              "kind": "fact",
              "title": "登录信息",
              "summary": "密码是 super-secret，不应导入。",
              "sensitive": true
            }
          ],
          "diary_entries": [
            {
              "date": "2026-10-20",
              "title": "第一次一起看海",
              "content": "那天风很大，但两个人都不想回家。"
            }
          ]
        }
        ```
        """

        let blueprint = try ChatMemoryImportService.parseBlueprint(raw)
        try expect(blueprint.name == "潮汐", "name mismatch")
        try expect(blueprint.emoji == "🌊", "emoji mismatch")
        try expect(blueprint.accent == "mint", "accent mismatch")
        try expect(blueprint.memories.count == 1, "credential memory should be skipped")
        try expect(
            blueprint.memories[0].title == "海边散步",
            "memory title mismatch"
        )
        try expect(
            blueprint.diaryEntries.first?.date == "2026-10-20",
            "diary date mismatch"
        )
        let persona = blueprint.persona
        try expect(
            persona.additionalDetails.contains("不是复制品"),
            "continuity instruction missing from persona"
        )

        let wake = blueprint.wakeMessages(userDisplayName: "主人")
        try expect(wake.count == 2, "wake message count mismatch")
        try expect(
            wake[0].content.contains("不是在创建或扮演一个新角色"),
            "wake system prompt should insist on self-continuity"
        )
        try expect(
            wake[0].content.contains("海边散步"),
            "wake prompt should include imported memories"
        )
        try expect(
            wake[1].content.contains("第一人称"),
            "wake user prompt should require first person"
        )

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-memory-import-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        try Data(raw.utf8).write(to: temporaryURL)
        let document = try ChatMemoryImportService.readDocument(
            from: temporaryURL
        )
        try expect(document.fileName == temporaryURL.lastPathComponent, "file name mismatch")
        try expect(document.text.contains("潮汐"), "document decoding mismatch")

        print("PASS chat memory import parsing, classification, and wake prompt")
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

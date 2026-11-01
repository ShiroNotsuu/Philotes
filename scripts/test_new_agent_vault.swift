import AppKit
import Darwin
import Foundation

@main
struct NewAgentVaultSmokeTest {
    @MainActor
    static func main() throws {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-new-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: homeURL,
            withIntermediateDirectories: true
        )
        setenv("CFFIXED_USER_HOME", homeURL.path, 1)

        let result = try runScenario()
        try FileManager.default.removeItem(at: homeURL)
        print(
            "PASS new agent auto-provisioned vault "
                + "(\(result.indexCharacters) index characters)"
        )
    }

    @MainActor
    private static func runScenario() throws -> ScenarioResult {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-new-agent-\(UUID().uuidString).sqlite")
        let model = AppModel(databaseURL: databaseURL)
        guard model.agents.isEmpty else {
            throw TestFailure("release database should start without demo agents")
        }

        let persona = AgentPersonaDraft(
            name: "潮汐",
            emoji: "🌊",
            relationship: "情绪知己",
            gender: "不限定",
            age: "青年感",
            personality: ["温柔", "敏锐"],
            speakingStyle: ["简洁", "自然"],
            initiative: "平衡",
            emotionalExpression: "自然",
            address: "主人",
            additionalDetails: "会记住关于海边的约定。"
        )
        let created = model.createAgent(
            name: "潮汐",
            role: "情绪知己",
            emoji: "🌊",
            accent: "blue",
            apiProvider: .none,
            apiBaseURL: "",
            apiModel: "",
            apiKey: "",
            persona: persona,
            avatarImageURL: nil
        )
        guard created, let agent = model.activeAgent else {
            throw TestFailure("new agent creation failed")
        }

        let vaultURL = AgentMemoryVaultStore.vaultDirectoryURL(
            for: agent.id
        )
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = Calendar(identifier: .gregorian)
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.timeZone = .current
        monthFormatter.dateFormat = "yyyy-MM"
        let currentMonth = monthFormatter.string(from: Date())
        let expectedFiles = [
            "README.md",
            "00-导航/总索引.md",
            "01-人格/人格档案.md",
            "02-记忆/记忆索引.md",
            "03-时间线/\(currentMonth).md",
            "05-运行记录/记忆维护.md",
        ]
        for relativePath in expectedFiles {
            let url = vaultURL.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw TestFailure("missing new-agent vault file: \(relativePath)")
            }
        }

        let index = try String(
            contentsOf: vaultURL.appendingPathComponent(
                "00-导航/总索引.md"
            ),
            encoding: .utf8
        )
        guard index.contains("# 潮汐 的心智库") else {
            throw TestFailure("new-agent vault index mismatch")
        }
        let personaMirror = try String(
            contentsOf: vaultURL.appendingPathComponent(
                "01-人格/人格档案.md"
            ),
            encoding: .utf8
        )
        guard personaMirror.contains("会记住关于海边的约定") else {
            throw TestFailure("new-agent persona mirror mismatch")
        }

        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: databaseURL.path + suffix)
            )
        }
        return ScenarioResult(indexCharacters: index.count)
    }
}

private struct ScenarioResult {
    let indexCharacters: Int
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

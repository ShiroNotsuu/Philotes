import Foundation

struct ExtractedAgentMemory {
    let kind: String
    let title: String
    let summary: String
}

enum AgentVaultCategory: String, CaseIterable, Identifiable {
    case navigation
    case persona
    case memory
    case timeline
    case diary
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigation:
            return L10n.string("索引")
        case .persona:
            return L10n.string("人格")
        case .memory:
            return L10n.string("记忆")
        case .timeline:
            return L10n.string("时间线")
        case .diary:
            return L10n.string("日记")
        case .maintenance:
            return L10n.string("维护")
        }
    }

    var systemImage: String {
        switch self {
        case .navigation:
            return "point.3.connected.trianglepath.dotted"
        case .persona:
            return "person.crop.circle"
        case .memory:
            return "sparkles"
        case .timeline:
            return "calendar"
        case .diary:
            return "book.closed"
        case .maintenance:
            return "wrench.and.screwdriver"
        }
    }
}

struct AgentVaultCategorySummary: Identifiable, Equatable {
    let agentID: Int64
    let category: AgentVaultCategory
    let count: Int
    let updatedAt: Date

    var id: String {
        "\(agentID)-\(category.rawValue)"
    }
}

enum AgentMemoryVaultError: LocalizedError {
    case agentNotAvailable(Int64)

    var errorDescription: String? {
        switch self {
        case .agentNotAvailable(let id):
            return "无法为新智能体 \(id) 建立心智库。"
        }
    }
}

enum AgentMemoryVaultStore {
    private static let maximumSearchFiles = 200
    private static let maximumMemoryFilesInContext = 6

    static func rootDirectoryURL(baseURL: URL? = nil) -> URL {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("AgentVaults", isDirectory: true)
    }

    static func vaultDirectoryURL(
        for agentID: Int64,
        baseURL: URL? = nil
    ) -> URL {
        rootDirectoryURL(baseURL: baseURL)
            .appendingPathComponent("agent-\(agentID)", isDirectory: true)
    }

    static func categorySummaries(
        for agentID: Int64,
        baseURL: URL? = nil
    ) -> [AgentVaultCategorySummary] {
        let vaultURL = vaultDirectoryURL(
            for: agentID,
            baseURL: baseURL
        )
        return AgentVaultCategory.allCases.map { category in
            let files = categoryFiles(
                category,
                vaultURL: vaultURL
            )
            let updatedAt = files
                .map(modificationDate)
                .max() ?? .distantPast
            return AgentVaultCategorySummary(
                agentID: agentID,
                category: category,
                count: contentCount(
                    for: category,
                    vaultURL: vaultURL,
                    fallbackFiles: files
                ),
                updatedAt: updatedAt
            )
        }
    }

    static func previewMarkdown(
        for category: AgentVaultCategory,
        agentID: Int64,
        baseURL: URL? = nil,
        maximumCharacters: Int = 7_000
    ) -> String? {
        let vaultURL = vaultDirectoryURL(
            for: agentID,
            baseURL: baseURL
        )
        let preferredURL: URL?
        switch category {
        case .memory:
            preferredURL = vaultURL.appendingPathComponent(
                "02-记忆/记忆索引.md"
            )
        case .timeline:
            preferredURL = categoryFiles(
                category,
                vaultURL: vaultURL
            ).max { $0.lastPathComponent < $1.lastPathComponent }
        case .diary:
            preferredURL = categoryFiles(
                category,
                vaultURL: vaultURL
            ).max { $0.lastPathComponent < $1.lastPathComponent }
        case .navigation, .persona, .maintenance:
            preferredURL = categoryFiles(
                category,
                vaultURL: vaultURL
            ).first
        }
        guard let preferredURL,
              let raw = try? String(
                contentsOf: preferredURL,
                encoding: .utf8
              )
        else {
            return nil
        }
        let clean = stripFrontmatter(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return "这个分类还没有可预览的 Markdown 内容。"
        }
        return clipped(clean, limit: maximumCharacters)
    }

    static func previewMarkdown(
        forMemoryID memoryID: Int64,
        agentID: Int64,
        baseURL: URL? = nil,
        maximumCharacters: Int = 5_000
    ) -> String? {
        let url = vaultDirectoryURL(for: agentID, baseURL: baseURL)
            .appendingPathComponent("02-记忆", isDirectory: true)
            .appendingPathComponent("节点", isDirectory: true)
            .appendingPathComponent("M-\(memoryID).md")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let clean = stripFrontmatter(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty
            ? nil
            : clipped(clean, limit: maximumCharacters)
    }

    @discardableResult
    static func ensureVault(
        for agent: AgentProfile,
        memories: [MemoryNode],
        links: [MemoryLink],
        messages: [ChatMessage] = [],
        personaMarkdown: String? = nil,
        baseURL: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        let navigationURL = vaultURL.appendingPathComponent(
            "00-导航",
            isDirectory: true
        )
        let personaURL = vaultURL.appendingPathComponent(
            "01-人格",
            isDirectory: true
        )
        let memoryURL = vaultURL.appendingPathComponent(
            "02-记忆",
            isDirectory: true
        )
        let nodesURL = memoryURL.appendingPathComponent(
            "节点",
            isDirectory: true
        )
        let timelineURL = vaultURL.appendingPathComponent(
            "03-时间线",
            isDirectory: true
        )
        let diaryURL = vaultURL.appendingPathComponent(
            "04-日记",
            isDirectory: true
        )
        let maintenanceURL = vaultURL.appendingPathComponent(
            "05-运行记录",
            isDirectory: true
        )

        for directory in [
            navigationURL,
            personaURL,
            memoryURL,
            nodesURL,
            timelineURL,
            diaryURL,
            maintenanceURL,
            vaultURL.appendingPathComponent(".obsidian", isDirectory: true)
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        try writeIfChanged(
            readme(for: agent),
            to: vaultURL.appendingPathComponent("README.md")
        )

        let resolvedPersona = personaMarkdown
            ?? AgentPersonaStore.load(for: agent.id)
            ?? fallbackPersona(for: agent)
        try writeIfChanged(
            resolvedPersona,
            to: personaURL.appendingPathComponent("人格档案.md")
        )

        try synchronizeMemoryNotes(
            memories: memories,
            links: links,
            nodesDirectory: nodesURL
        )
        try writeIfChanged(
            memoryIndex(
                for: agent,
                memories: memories
            ),
            to: memoryURL.appendingPathComponent("记忆索引.md")
        )

        let latestDay = latestDiaryDay(in: diaryURL)
        try writeIfChanged(
            index(
                for: agent,
                latestDay: latestDay
            ),
            to: navigationURL.appendingPathComponent("总索引.md")
        )
        let existingDiaryFiles = (
            try? FileManager.default.contentsOfDirectory(
                at: diaryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )?.filter { $0.pathExtension == "md" } ?? []
        if existingDiaryFiles.isEmpty, !messages.isEmpty {
            for message in messages.sorted(by: {
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt
            }) {
                try appendMessage(message, for: agent, baseURL: baseURL)
            }
        }
        try refreshMonthlyTimeline(
            for: Date(),
            diaryDirectory: diaryURL,
            timelineDirectory: timelineURL
        )
        try appendMaintenanceEvent(
            "完成一次记忆与人格同步（\(memories.count) 条记忆）",
            in: maintenanceURL
        )
        return vaultURL
    }

    static func personaDocument(
        for agentID: Int64,
        baseURL: URL? = nil
    ) -> String? {
        let url = vaultDirectoryURL(for: agentID, baseURL: baseURL)
            .appendingPathComponent("01-人格", isDirectory: true)
            .appendingPathComponent("人格档案.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func contextExcerpt(
        for agent: AgentProfile,
        query: String,
        baseURL: URL? = nil,
        maximumCharacters: Int = 6_500
    ) -> String {
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return ""
        }

        let indexURL = vaultURL
            .appendingPathComponent("00-导航", isDirectory: true)
            .appendingPathComponent("总索引.md")
        let memoryIndexURL = vaultURL
            .appendingPathComponent("02-记忆", isDirectory: true)
            .appendingPathComponent("记忆索引.md")
        let nodesURL = vaultURL
            .appendingPathComponent("02-记忆", isDirectory: true)
            .appendingPathComponent("节点", isDirectory: true)
        let diaryURL = vaultURL.appendingPathComponent(
            "04-日记",
            isDirectory: true
        )

        var sections: [String] = []
        if let index = try? String(contentsOf: indexURL, encoding: .utf8) {
            sections.append(
                "### 心智库索引\n"
                    + clipped(index, limit: 1_500)
            )
        }
        if let memoryIndex = try? String(
            contentsOf: memoryIndexURL,
            encoding: .utf8
        ) {
            sections.append(
                "### 记忆目录\n"
                    + clipped(memoryIndex, limit: 1_100)
            )
        }

        let terms = searchTerms(from: query)
        let prefersRecollection = containsRecallIntent(query)
        let memories = relevantMemoryExcerpts(
            nodesDirectory: nodesURL,
            terms: terms,
            prefersRecollection: prefersRecollection
        )
        if !memories.isEmpty {
            sections.append(
                "### 与当前话题相关的长期记忆\n"
                    + memories.joined(separator: "\n\n")
            )
        }

        let diary = relevantDiaryExcerpts(
            diaryDirectory: diaryURL,
            terms: terms,
            prefersRecollection: prefersRecollection
        )
        if !diary.isEmpty {
            sections.append(
                "### 相关日记摘记\n"
                    + diary.joined(separator: "\n\n")
            )
        }

        guard !sections.isEmpty else { return "" }
        return clipped(
            sections.joined(separator: "\n\n"),
            limit: maximumCharacters
        )
    }

    static func updatePersonaMirror(
        _ markdown: String,
        for agentID: Int64,
        baseURL: URL? = nil
    ) throws {
        let directory = vaultDirectoryURL(
            for: agentID,
            baseURL: baseURL
        ).appendingPathComponent("01-人格", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try writeIfChanged(
            PersonaMarkdownSanitizer.clean(markdown),
            to: directory.appendingPathComponent("人格档案.md")
        )
    }

    static func appendMessage(
        _ message: ChatMessage,
        for agent: AgentProfile,
        baseURL: URL? = nil
    ) throws {
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        let diaryURL = vaultURL.appendingPathComponent(
            "04-日记",
            isDirectory: true
        )
        let timelineURL = vaultURL.appendingPathComponent(
            "03-时间线",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: diaryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: timelineURL,
            withIntermediateDirectories: true
        )

        let day = dayFormatter.string(from: message.createdAt)
        let time = timeFormatter.string(from: message.createdAt)
        let dayURL = diaryURL.appendingPathComponent("\(day).md")
        if !FileManager.default.fileExists(atPath: dayURL.path) {
            try writeIfChanged(
                """
                ---
                type: agent-diary
                agent-id: \(agent.id)
                date: \(day)
                ---

                # \(day)

                > 这是 \(agent.name) 与主人共同经历的这一天。记录只追加，不覆盖。
                """,
                to: dayURL
            )
        }

        let speaker: String
        switch message.role {
        case .user:
            speaker = "主人"
        case .assistant:
            speaker = agent.name
        case .system:
            speaker = "系统"
        }
        let parsed = message.role == .assistant
            ? AssistantResponseParser.parse(message.body)
            : nil
        let body = parsed?.body.isEmpty == false
            ? parsed?.body ?? message.body
            : message.body
        var entry = "\n\n### \(time) · \(speaker)\n"
        if let action = parsed?.action, !action.isEmpty {
            entry += "> \(PersonaMarkdownSanitizer.clean(action))\n\n"
        }
        entry += PersonaMarkdownSanitizer.clean(body)
        try appendText(entry, to: dayURL)
        try refreshMonthlyTimeline(
            for: message.createdAt,
            diaryDirectory: diaryURL,
            timelineDirectory: timelineURL
        )
        let navigationURL = vaultURL.appendingPathComponent(
            "00-导航",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: navigationURL,
            withIntermediateDirectories: true
        )
        try writeIfChanged(
            index(for: agent, latestDay: day),
            to: navigationURL.appendingPathComponent("总索引.md")
        )
    }

    static func appendGroupMessage(
        roomName: String,
        speaker: String,
        body: String,
        createdAt: Date,
        for agent: AgentProfile,
        baseURL: URL? = nil
    ) throws {
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        let diaryURL = vaultURL.appendingPathComponent(
            "04-日记",
            isDirectory: true
        )
        let timelineURL = vaultURL.appendingPathComponent(
            "03-时间线",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: diaryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: timelineURL,
            withIntermediateDirectories: true
        )

        let day = dayFormatter.string(from: createdAt)
        let time = timeFormatter.string(from: createdAt)
        let dayURL = diaryURL.appendingPathComponent("\(day).md")
        if !FileManager.default.fileExists(atPath: dayURL.path) {
            try writeIfChanged(
                """
                ---
                type: agent-diary
                agent-id: \(agent.id)
                date: \(day)
                ---

                # \(day)

                > 这是 \(agent.name) 与主人共同经历的这一天。记录只追加，不覆盖。
                """,
                to: dayURL
            )
        }

        let parsed = AssistantResponseParser.parse(body)
        let cleanRoom = PersonaMarkdownSanitizer.clean(roomName)
        let cleanSpeaker = PersonaMarkdownSanitizer.clean(speaker)
        var entry = "\n\n### \(time) · 群聊「\(cleanRoom)」 · \(cleanSpeaker)\n"
        if let action = parsed.action, !action.isEmpty {
            entry += "> \(PersonaMarkdownSanitizer.clean(action))\n\n"
        }
        let cleanBody = parsed.body.isEmpty ? body : parsed.body
        entry += PersonaMarkdownSanitizer.clean(cleanBody)
        try appendText(entry, to: dayURL)
        try refreshMonthlyTimeline(
            for: createdAt,
            diaryDirectory: diaryURL,
            timelineDirectory: timelineURL
        )
        let navigationURL = vaultURL.appendingPathComponent(
            "00-导航",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: navigationURL,
            withIntermediateDirectories: true
        )
        try writeIfChanged(
            index(for: agent, latestDay: day),
            to: navigationURL.appendingPathComponent("总索引.md")
        )
    }

    static func appendImportedDiaryEntry(
        _ entry: ImportedAgentDiaryEntry,
        for agent: AgentProfile,
        baseURL: URL? = nil
    ) throws {
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        let diaryURL = vaultURL.appendingPathComponent(
            "04-日记",
            isDirectory: true
        )
        let timelineURL = vaultURL.appendingPathComponent(
            "03-时间线",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: diaryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: timelineURL,
            withIntermediateDirectories: true
        )

        let parsedDate = entry.date.flatMap(dayFormatter.date(from:))
        let date = parsedDate ?? Date()
        let day = dayFormatter.string(from: date)
        let dayURL = diaryURL.appendingPathComponent("\(day).md")
        if !FileManager.default.fileExists(atPath: dayURL.path) {
            try writeIfChanged(
                """
                ---
                type: agent-diary
                agent-id: \(agent.id)
                date: \(day)
                ---

                # \(day)

                > 这是 \(agent.name) 与主人共同经历的这一天。记录只追加，不覆盖。
                """,
                to: dayURL
            )
        }

        let entryText = """

        ### 从聊天记忆重建 · \(PersonaMarkdownSanitizer.clean(entry.title))

        \(PersonaMarkdownSanitizer.clean(entry.content))
        """
        try appendText(entryText, to: dayURL)
        try refreshMonthlyTimeline(
            for: date,
            diaryDirectory: diaryURL,
            timelineDirectory: timelineURL
        )
        let navigationURL = vaultURL.appendingPathComponent(
            "00-导航",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: navigationURL,
            withIntermediateDirectories: true
        )
        try writeIfChanged(
            index(for: agent, latestDay: day),
            to: navigationURL.appendingPathComponent("总索引.md")
        )
    }

    static func saveImportedSource(
        _ document: ImportTextDocument,
        for agent: AgentProfile,
        baseURL: URL? = nil
    ) throws {
        let vaultURL = vaultDirectoryURL(
            for: agent.id,
            baseURL: baseURL
        )
        let maintenanceURL = vaultURL.appendingPathComponent(
            "05-运行记录",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: maintenanceURL,
            withIntermediateDirectories: true
        )
        let safeFileName = PersonaMarkdownSanitizer.clean(
            URL(fileURLWithPath: document.fileName).lastPathComponent
        )
        let content = """
        ---
        type: imported-chat-memory
        agent-id: \(agent.id)
        imported-at: \(isoFormatter.string(from: Date()))
        source-file: \(yamlEscaped(safeFileName))
        ---

        # 聊天记忆导入来源

        - 原始文件：\(safeFileName)
        - 导入时间：\(dateTimeFormatter.string(from: Date()))

        ## 原始记忆

        \(PersonaMarkdownSanitizer.clean(document.text))
        """
        try writeIfChanged(
            content,
            to: maintenanceURL.appendingPathComponent(
                "聊天记忆导入-\(fileNameTimestampFormatter.string(from: Date())).md"
            )
        )
    }

    static func deleteVault(
        for agentID: Int64,
        baseURL: URL? = nil
    ) {
        try? FileManager.default.removeItem(
            at: vaultDirectoryURL(for: agentID, baseURL: baseURL)
        )
    }

    static func deleteMemoryNote(
        id: Int64,
        for agentID: Int64,
        baseURL: URL? = nil
    ) {
        let url = vaultDirectoryURL(for: agentID, baseURL: baseURL)
            .appendingPathComponent("02-记忆", isDirectory: true)
            .appendingPathComponent("节点", isDirectory: true)
            .appendingPathComponent("M-\(id).md")
        try? FileManager.default.removeItem(at: url)
    }

    static func extractExplicitMemory(
        from rawText: String
    ) -> ExtractedAgentMemory? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 5,
              text.count <= 800,
              !isCredentialLike(text)
        else {
            return nil
        }

        let triggers = [
            "请记住", "记住", "记一下", "你要记得", "希望你记得",
            "别忘了", "不要忘记", "我喜欢", "我不喜欢",
            "我的生日", "以后都", "以后叫", "我们说好"
        ]
        guard triggers.contains(where: text.contains) else {
            return nil
        }

        let kind: String
        if text.contains("喜欢") || text.contains("偏好") {
            kind = "preference"
        } else if text.contains("约定")
                    || text.contains("以后")
                    || text.contains("说好") {
            kind = "promise"
        } else {
            kind = "fact"
        }

        let titleSource = triggers.reduce(text) { result, trigger in
            result.replacingOccurrences(of: trigger, with: "")
        }
        let firstLine = titleSource
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? text
        let firstSentence = firstLine.components(
            separatedBy: CharacterSet(charactersIn: "。！？!?")
        ).first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(
            (firstSentence?.isEmpty == false ? firstSentence! : text)
                .prefix(36)
        )
        return ExtractedAgentMemory(
            kind: kind,
            title: PersonaMarkdownSanitizer.clean(title),
            summary: PersonaMarkdownSanitizer.clean(text)
        )
    }

    static func isCredentialLike(_ text: String) -> Bool {
        let patterns = [
            #"(?i)\b(?:api[_-]?key|token|password|secret|cookie|private[_-]?key)\b"#,
            #"\bsk-[A-Za-z0-9_-]{8,}"#,
            #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{6,}"#,
            #"(密码|密钥|私钥|验证码|身份证|银行卡|信用卡|口令)"#
        ]
        return patterns.contains { pattern in
            text.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    private static func relevantMemoryExcerpts(
        nodesDirectory: URL,
        terms: Set<String>,
        prefersRecollection: Bool
    ) -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: nodesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let candidates = urls
            .filter {
                $0.pathExtension == "md"
                    && $0.lastPathComponent.hasPrefix("M-")
            }
            .sorted {
                modificationDate(of: $0) > modificationDate(of: $1)
            }
            .prefix(maximumSearchFiles)

        let scored = candidates.compactMap { url -> (URL, String, Int)? in
            guard let raw = try? String(contentsOf: url, encoding: .utf8),
                  !raw.contains("sensitive: true")
            else {
                return nil
            }
            let body = stripFrontmatter(raw)
            let score = relevanceScore(text: body, terms: terms)
            return (url, body, score)
        }
        let ranked = scored.sorted {
            if $0.2 == $1.2 {
                return modificationDate(of: $0.0)
                    > modificationDate(of: $1.0)
            }
            return $0.2 > $1.2
        }
        let selected = ranked.filter { $0.2 > 0 }
        let excerptSource = selected.isEmpty && prefersRecollection
            ? ranked
            : selected
        return excerptSource
            .prefix(maximumMemoryFilesInContext)
            .map { clipped($0.1, limit: 1_500) }
    }

    private static func relevantDiaryExcerpts(
        diaryDirectory: URL,
        terms: Set<String>,
        prefersRecollection: Bool
    ) -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: diaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let files = urls
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(21)

        var rankedBlocks: [(String, Int)] = []
        for url in files {
            guard let content = try? String(
                contentsOf: url,
                encoding: .utf8
            ) else {
                continue
            }
            let blocks = content
                .components(separatedBy: "\n### ")
                .filter { $0.count >= 20 }
            for block in blocks {
                rankedBlocks.append((
                    "### " + stripFrontmatter(block),
                    relevanceScore(text: block, terms: terms)
                ))
            }
        }
        let hits = rankedBlocks
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { clipped($0.0, limit: 1_300) }
        if hits.isEmpty && prefersRecollection {
            return rankedBlocks
                .prefix(2)
                .map { clipped($0.0, limit: 1_300) }
        }
        return hits
    }

    private static func searchTerms(from query: String) -> Set<String> {
        let stopWords: Set<String> = [
            "什么", "怎么", "可以", "主人", "今天", "现在",
            "我们", "这个", "那个", "一个", "还是", "就是"
        ]
        let rawTokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && $0.count <= 80 }
        var terms = Set<String>()
        for token in rawTokens {
            if !stopWords.contains(token) {
                terms.insert(token)
            }
            let characters = Array(token)
            guard characters.count >= 2 else { continue }
            for index in 0..<(characters.count - 1) {
                let pair = String(characters[index...index + 1])
                if !stopWords.contains(pair) {
                    terms.insert(pair)
                }
            }
        }
        return Set(terms.prefix(48))
    }

    private static func containsRecallIntent(_ query: String) -> Bool {
        let terms = [
            "记得", "以前", "上次", "之前", "回忆", "聊过",
            "那天", "曾经", "还记得", "过去", "原来"
        ]
        return terms.contains { query.contains($0) }
    }

    private static func relevanceScore(
        text: String,
        terms: Set<String>
    ) -> Int {
        guard !terms.isEmpty else { return 0 }
        let lowered = text.lowercased()
        return terms.reduce(into: 0) { score, term in
            if lowered.contains(term) {
                score += min(max(term.count, 1), 4)
            }
        }
    }

    private static func synchronizeMemoryNotes(
        memories: [MemoryNode],
        links: [MemoryLink],
        nodesDirectory: URL
    ) throws {
        let existing = try? FileManager.default.contentsOfDirectory(
            at: nodesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let validIDs = Set(memories.map(\.id))
        for url in existing ?? [] {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("M-"),
                  let id = Int64(name.dropFirst(2)),
                  !validIDs.contains(id)
            else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }

        for memory in memories {
            let related = links.compactMap { link -> Int64? in
                guard link.sourceMemoryID == memory.id else { return nil }
                return link.targetMemoryID
            }
            let content = memoryNote(
                memory,
                relatedMemoryIDs: related
            )
            try writeIfChanged(
                content,
                to: nodesDirectory.appendingPathComponent(
                    "M-\(memory.id).md"
                )
            )
        }
    }

    private static func memoryNote(
        _ memory: MemoryNode,
        relatedMemoryIDs: [Int64]
    ) -> String {
        let title = PersonaMarkdownSanitizer.clean(memory.title)
        let source = PersonaMarkdownSanitizer.clean(memory.source)
        let visibleTitle = memory.isSensitive ? "敏感记忆 #\(memory.id)" : title
        let summary = memory.isSensitive
            ? "> 这条记忆被标记为敏感。正文不写入 Markdown 镜像，也不会自动进入模型上下文。"
            : PersonaMarkdownSanitizer.clean(memory.summary)
        let relatedSection = relatedMemoryIDs.isEmpty
            ? "暂无关联记忆。"
            : relatedMemoryIDs
                .map { "- [[M-\($0)]]" }
                .joined(separator: "\n")
        return """
        ---
        id: \(memory.id)
        agent-id: \(memory.agentID)
        kind: \(yamlEscaped(memory.kind))
        source: \(yamlEscaped(source))
        created: \(isoFormatter.string(from: memory.createdAt))
        sensitive: \(memory.isSensitive ? "true" : "false")
        ---

        # \(visibleTitle)

        \(summary)

        ## 关联记忆

        \(relatedSection)
        """
    }

    private static func memoryIndex(
        for agent: AgentProfile,
        memories: [MemoryNode]
    ) -> String {
        let grouped = Dictionary(grouping: memories, by: \.kind)
        let groups = grouped.keys.sorted().map { kind -> String in
            let rows = grouped[kind, default: []]
                .sorted { $0.createdAt > $1.createdAt }
                .map { memory -> String in
                    let title = memory.isSensitive
                        ? "敏感记忆 #\(memory.id)"
                        : PersonaMarkdownSanitizer.clean(memory.title)
                    return "- [[节点/M-\(memory.id)|\(title)]] · "
                        + "\(isoFormatter.string(from: memory.createdAt)) · "
                        + PersonaMarkdownSanitizer.clean(memory.source)
                }
                .joined(separator: "\n")
            return "### \(memoryKindLabel(kind))\n\n\(rows)"
        }.joined(separator: "\n\n")
        return """
        ---
        type: agent-memory-index
        agent-id: \(agent.id)
        title: \(yamlEscaped(agent.name)) 的记忆索引
        ---

        # \(agent.name) 的记忆索引

        > 先读总索引，再按当前话题只打开相关节点。不要一次展开整个记忆库。

        \(memories.isEmpty ? "还没有长期记忆节点。" : groups)
        """
    }

    private static func index(
        for agent: AgentProfile,
        latestDay: String?
    ) -> String {
        let currentMonth = monthFormatter.string(from: Date())
        let diaryLink = latestDay.map {
            "[[\($0)|\($0)]]"
        } ?? "今天还没有对话记录。"
        return """
        ---
        type: agent-index
        agent-id: \(agent.id)
        title: \(yamlEscaped(agent.name)) 的心智库
        updated: \(dayFormatter.string(from: Date()))
        ---

        # \(agent.name) 的心智库

        > \(agent.role)。这里保存可见、可追溯、可遗忘的长期记忆与人格。

        ## 开工顺序

        1. 先读本页确认身份和当前索引。
        2. 再打开 [[人格档案]]，保持人格连续。
        3. 只沿 [[记忆索引]] 找到与当前话题相关的节点。
        4. 需要回顾经历时再读当天日记，不一次展开全部时间线。

        ## 入口

        - 人格：[[人格档案]]
        - 记忆：[[记忆索引]]
        - 本月时间线：[[\(currentMonth)|\(currentMonth)]]
        - 最近日记：\(diaryLink)
        - 维护记录：[[记忆维护|记忆维护]]

        ## 纪律

        - 默认只追加，不覆盖已经发生的事实。
        - 敏感记忆正文不写入自动镜像，也不主动进入模型上下文。
        - 不把 API Key、Token、密码、Cookie 或私钥写入心智库。
        """
    }

    private static func readme(for agent: AgentProfile) -> String {
        """
        # \(agent.name) · Agent Memory Vault

        这是 Philotes 为单个智能体维护的本地 Markdown 心智库。

        - `00-导航/总索引.md`：每次读取的唯一入口。
        - `01-人格/人格档案.md`：当前人格与表达方式。
        - `02-记忆/`：长期记忆索引与独立节点。
        - `03-时间线/`：按月份索引日记。
        - `04-日记/`：与主人共同经历的具体对话。
        - `05-运行记录/`：同步与维护记录。

        不覆盖历史，不保存任何凭据。
        """
    }

    private static func fallbackPersona(for agent: AgentProfile) -> String {
        """
        # \(agent.name) 的人格档案

        - 名字：\(agent.name)
        - 图标：\(agent.emoji)
        - 陪伴关系：\(agent.role)
        """
    }

    private static func memoryKindLabel(_ kind: String) -> String {
        switch kind {
        case "preference":
            return "偏好"
        case "promise":
            return "约定"
        case "fact":
            return "事实"
        case "date":
            return "重要日期"
        default:
            return kind
        }
    }

    private static func refreshMonthlyTimeline(
        for date: Date,
        diaryDirectory: URL,
        timelineDirectory: URL
    ) throws {
        let month = monthFormatter.string(from: date)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let days = files
            .filter {
                $0.lastPathComponent.hasPrefix("\(month)-")
                    && $0.pathExtension == "md"
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { url -> String in
                let day = url.deletingPathExtension().lastPathComponent
                let content = (try? String(
                    contentsOf: url,
                    encoding: .utf8
                )) ?? ""
                let count = content.components(
                    separatedBy: "\n### "
                ).count - 1
                return "- [[\(day)|\(day)]] · \(count) 条记录"
            }
            .joined(separator: "\n")
        let content = """
        ---
        type: agent-timeline
        month: \(month)
        ---

        # \(month)

        > 月份只维护日期索引，具体内容保留在每天的日记里。

        \(days.isEmpty ? "这个月还没有对话记录。" : days)
        """
        try writeIfChanged(
            content,
            to: timelineDirectory.appendingPathComponent("\(month).md")
        )
    }

    private static func appendMaintenanceEvent(
        _ event: String,
        in directory: URL
    ) throws {
        let url = directory.appendingPathComponent("记忆维护.md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try writeIfChanged(
                """
                # 记忆维护

                > 自动维护只追加记录，不修改具体记忆与日记正文。
                """,
                to: url
            )
        }
        let line = "- \(isoFormatter.string(from: Date())) · \(event)"
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !existing.contains(line) {
            try appendText("\n\(line)", to: url)
        }
    }

    private static func latestDiaryDay(in directory: URL) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return files
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
            .last
    }

    private static func categoryFiles(
        _ category: AgentVaultCategory,
        vaultURL: URL
    ) -> [URL] {
        let directory: URL
        switch category {
        case .navigation:
            directory = vaultURL.appendingPathComponent(
                "00-导航",
                isDirectory: true
            )
        case .persona:
            directory = vaultURL.appendingPathComponent(
                "01-人格",
                isDirectory: true
            )
        case .memory:
            directory = vaultURL.appendingPathComponent(
                "02-记忆/节点",
                isDirectory: true
            )
        case .timeline:
            directory = vaultURL.appendingPathComponent(
                "03-时间线",
                isDirectory: true
            )
        case .diary:
            directory = vaultURL.appendingPathComponent(
                "04-日记",
                isDirectory: true
            )
        case .maintenance:
            directory = vaultURL.appendingPathComponent(
                "05-运行记录",
                isDirectory: true
            )
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { $0.pathExtension == "md" }
    }

    private static func contentCount(
        for category: AgentVaultCategory,
        vaultURL: URL,
        fallbackFiles: [URL]
    ) -> Int {
        switch category {
        case .navigation, .persona, .maintenance:
            return min(1, fallbackFiles.count)
        case .memory, .timeline, .diary:
            return fallbackFiles.count
        }
    }

    private static func stripFrontmatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---"),
              let closing = markdown.range(
                of: "\n---",
                range: markdown.index(
                    markdown.startIndex,
                    offsetBy: 3
                )..<markdown.endIndex
              )
        else {
            return markdown
        }
        return String(markdown[closing.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…"
    }

    private static func modificationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        )
        return values?.contentModificationDate ?? .distantPast
    }

    private static func yamlEscaped(_ value: String) -> String {
        "\""
            + value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            + "\""
    }

    private static func writeIfChanged(
        _ content: String,
        to url: URL
    ) throws {
        let current = try? String(contentsOf: url, encoding: .utf8)
        guard current != content else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func appendText(
        _ text: String,
        to url: URL
    ) throws {
        let data = Data(text.utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fileNameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        return formatter
    }()
}

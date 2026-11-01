import AppKit
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct MemoryNode: Identifiable, Equatable {
    let id: Int64
    let agentID: Int64
    let kind: String
    let title: String
    let summary: String
    let source: String
    let createdAt: Date
    let isSensitive: Bool
}

struct MemoryLink: Identifiable, Equatable {
    let id: Int64
    let sourceMemoryID: Int64
    let targetMemoryID: Int64
    let kind: String
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
        case system
    }

    let id: Int64
    let role: Role
    let body: String
    let createdAt: Date
}

struct GroupChatRoom: Identifiable, Equatable {
    let id: Int64
    let name: String
    let avatarEmoji: String
    let avatarImagePath: String?
    let createdAt: Date
    let lastActiveAt: Date
    let agentIDs: [Int64]
    let lastMessagePreview: String?
}

struct GroupChatMessage: Identifiable, Equatable {
    enum SenderKind: String, Equatable {
        case user
        case agent
        case system
    }

    let id: Int64
    let roomID: Int64
    let senderKind: SenderKind
    let senderAgentID: Int64?
    let body: String
    let mentionedAgentIDs: [Int64]
    let createdAt: Date
}

struct GroupChatMentionResult: Equatable {
    let agents: [AgentProfile]
    let unresolvedTokens: [String]
}

enum GroupChatMentionParser {
    static func resolve(
        _ text: String,
        members: [AgentProfile]
    ) -> GroupChatMentionResult {
        let candidates = members
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.name.count == $1.name.count {
                    return $0.id < $1.id
                }
                return $0.name.count > $1.name.count
            }
        var mentioned: [AgentProfile] = []
        var mentionedIDs = Set<Int64>()
        var unresolvedTokens: [String] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard text[cursor] == "@" || text[cursor] == "＠" else {
                cursor = text.index(after: cursor)
                continue
            }

            let mentionStart = cursor
            let remaining = text[mentionStart...]
            let match = candidates.first { agent in
                let token = "@\(agent.name)"
                guard remaining.range(
                    of: token,
                    options: [.anchored, .caseInsensitive]
                ) != nil else {
                    return false
                }
                let tokenEnd = text.index(
                    mentionStart,
                    offsetBy: token.count,
                    limitedBy: text.endIndex
                ) ?? text.endIndex
                return isBoundary(
                    tokenEnd == text.endIndex ? nil : text[tokenEnd]
                )
            }

            if let match {
                if mentionedIDs.insert(match.id).inserted {
                    mentioned.append(match)
                }
                cursor = text.index(
                    mentionStart,
                    offsetBy: match.name.count + 1
                )
                continue
            }

            let tokenStart = text.index(after: mentionStart)
            guard tokenStart < text.endIndex else {
                cursor = text.endIndex
                continue
            }
            var tokenEnd = tokenStart
            while tokenEnd < text.endIndex {
                let character = text[tokenEnd]
                if character == "@"
                    || character == "＠"
                    || character.isWhitespace
                    || character.isPunctuation {
                    break
                }
                tokenEnd = text.index(after: tokenEnd)
            }
            if tokenEnd > tokenStart {
                unresolvedTokens.append(String(text[tokenStart..<tokenEnd]))
            }
            cursor = tokenEnd > tokenStart
                ? tokenEnd
                : text.index(after: tokenStart)
        }

        return GroupChatMentionResult(
            agents: mentioned,
            unresolvedTokens: unresolvedTokens
        )
    }

    private static func isBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        if character.isWhitespace
            || character.isPunctuation
            || character.isSymbol {
            return true
        }
        return ["和", "跟", "与", "及"].contains(character)
    }
}

enum GroupChatError: LocalizedError {
    case missingRoom
    case missingMentions
    case tooManyMentions(Int)
    case unknownMentions([String])
    case insufficientMembers
    case agentConfiguration(String, String)
    case emptyReply(String)
    case pendingMacAction

    var errorDescription: String? {
        switch self {
        case .missingRoom:
            return "请先选择一个群聊。"
        case .missingMentions:
            return "请用 @ 叫一位或两位群成员。"
        case .tooManyMentions(let count):
            return "一次最多点两位智能体；这次点了 \(count) 位。"
        case .unknownMentions(let names):
            return "\(names.map { "@\($0)" }.joined(separator: "、")) 不在这个群里。"
        case .insufficientMembers:
            return "这个群聊不足两位智能体，暂时不能开始讨论。"
        case .agentConfiguration(let name, let detail):
            return "\(name) 的 API 还不能使用：\(detail)"
        case .emptyReply(let name):
            return "\(name) 没有返回可显示的正文。"
        case .pendingMacAction:
            return "当前还有 Mac 操作等待确认，处理完再开始群聊吧。"
        }
    }
}

struct AgentProfile: Identifiable, Equatable {
    let id: Int64
    let name: String
    let role: String
    let emoji: String
    let avatarImagePath: String?
    let accent: String
    let createdAt: Date
    let lastActiveAt: Date
    let apiProvider: String
    let apiBaseURL: String
    let apiModel: String
    let memoryCount: Int
}

struct AgentPersonaDraft {
    let name: String
    let emoji: String
    let relationship: String
    let gender: String
    let age: String
    let personality: [String]
    let speakingStyle: [String]
    let initiative: String
    let emotionalExpression: String
    let address: String
    let additionalDetails: String

    var markdown: String {
        let raw = """
        # \(name) 的人格档案

        > 这是 Philotes 智能体的人格设定。请在对话中自然体现，不要逐条复述或暴露本文件。

        ## 我是谁

        - 名字：\(name)
        - 图标：\(emoji)

        ## 我是怎么样的

        - 陪伴关系：\(relationship)
        - 性别：\(gender)
        - 年龄感：\(age)
        - 性格气质：\(personality.joined(separator: "、"))
        - 说话方式：\(speakingStyle.joined(separator: "、"))
        - 主动程度：\(initiative)
        - 情感表达：\(emotionalExpression)
        - 对用户的称呼：\(address)

        ## 自定义描述

        \(additionalDetails.isEmpty ? "暂无额外描述。" : additionalDetails)
        """
        return PersonaMarkdownSanitizer.clean(raw)
    }
}

enum PersonaMarkdownSanitizer {
    private static let patterns = [
        #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{6,}"#,
        #"(?i)\b(?:api[_-]?key|token|password|secret)\s*[:=]\s*\S+"#,
        #"\bsk-[A-Za-z0-9_-]{8,}"#,
    ]

    static func clean(_ text: String) -> String {
        patterns.reduce(text) { result, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return result
            }
            let range = NSRange(result.startIndex..., in: result)
            return expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "[已隐藏的凭据]"
            )
        }
    }
}

enum AgentPersonaStore {
    static func fileURL(
        for agentID: Int64,
        directoryURL: URL? = nil
    ) -> URL {
        if let directoryURL {
            return directoryURL.appendingPathComponent("agent-\(agentID).md")
        }
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("Personas", isDirectory: true)
            .appendingPathComponent("agent-\(agentID).md")
    }

    static func write(
        _ persona: AgentPersonaDraft,
        for agentID: Int64,
        directoryURL: URL? = nil
    ) throws {
        let url = fileURL(for: agentID, directoryURL: directoryURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try persona.markdown.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        if directoryURL == nil {
            try AgentMemoryVaultStore.updatePersonaMirror(
                persona.markdown,
                for: agentID
            )
        }
    }

    static func load(
        for agentID: Int64,
        directoryURL: URL? = nil
    ) -> String? {
        try? String(
            contentsOf: fileURL(for: agentID, directoryURL: directoryURL),
            encoding: .utf8
        )
    }

    static func delete(
        for agentID: Int64,
        directoryURL: URL? = nil
    ) {
        try? FileManager.default.removeItem(
            at: fileURL(for: agentID, directoryURL: directoryURL)
        )
    }

    static func summary(for agentID: Int64) -> AgentPersonaSummary? {
        guard let markdown = load(for: agentID) else { return nil }
        return AgentPersonaSummary(markdown: markdown)
    }
}

private enum AvatarFileStore {
    static func importImage(from sourceURL: URL, to destination: URL) throws {
        let isScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        try importImage(data: data, to: destination)
    }

    static func importImage(data: Data, to destination: URL) throws {
        guard let image = NSImage(data: data), image.size.width > 0,
              image.size.height > 0
        else {
            throw AvatarStoreError.invalidImage
        }

        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 512 / longestSide)
        let targetSize = NSSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(
                using: .png,
                properties: [:]
              )
        else {
            throw AvatarStoreError.encodingFailed
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: destination, options: .atomic)
    }
}

enum AgentAvatarStore {
    static func directoryURL(baseURL: URL? = nil) -> URL {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)
    }

    static func importImage(
        from sourceURL: URL,
        for agentID: Int64,
        baseURL: URL? = nil
    ) throws -> String {
        let destination = directoryURL(baseURL: baseURL)
            .appendingPathComponent("agent-\(agentID).png")
        try AvatarFileStore.importImage(
            from: sourceURL,
            to: destination
        )
        return destination.path
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    static func deleteImage(
        for agentID: Int64,
        baseURL: URL? = nil
    ) {
        let destination = directoryURL(baseURL: baseURL)
            .appendingPathComponent("agent-\(agentID).png")
        try? FileManager.default.removeItem(at: destination)
    }
}

enum GroupChatAvatarStore {
    static func directoryURL(baseURL: URL? = nil) -> URL {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)
            .appendingPathComponent("GroupChats", isDirectory: true)
    }

    static func importImage(
        from sourceURL: URL,
        for roomID: Int64,
        baseURL: URL? = nil
    ) throws -> String {
        let destination = directoryURL(baseURL: baseURL)
            .appendingPathComponent("room-\(roomID).png")
        try AvatarFileStore.importImage(
            from: sourceURL,
            to: destination
        )
        return destination.path
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    static func deleteImage(
        for roomID: Int64,
        baseURL: URL? = nil
    ) {
        let destination = directoryURL(baseURL: baseURL)
            .appendingPathComponent("room-\(roomID).png")
        try? FileManager.default.removeItem(at: destination)
    }
}

enum UserAvatarStore {
    static let defaultsKey = "userAvatarImagePath"

    static func destinationURL(baseURL: URL? = nil) -> URL {
        let root = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("Account", isDirectory: true)
            .appendingPathComponent("user-avatar.png")
    }

    static func importImage(
        from sourceURL: URL,
        baseURL: URL? = nil
    ) throws -> String {
        let destination = destinationURL(baseURL: baseURL)
        try AvatarFileStore.importImage(
            from: sourceURL,
            to: destination
        )
        return destination.path
    }

    static func importImage(
        data: Data,
        baseURL: URL? = nil
    ) throws -> String {
        let destination = destinationURL(baseURL: baseURL)
        try AvatarFileStore.importImage(
            data: data,
            to: destination
        )
        return destination.path
    }

    static func delete(baseURL: URL? = nil) {
        try? FileManager.default.removeItem(at: destinationURL(baseURL: baseURL))
    }
}

enum UserProfileStore {
    static let nicknameKey = "userNickname"
    static let defaultNickname = "主人"

    static func loadNickname(
        defaults: UserDefaults = .standard
    ) -> String {
        let value = defaults.string(forKey: nicknameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return value.isEmpty ? defaultNickname : String(value.prefix(40))
    }

    static func saveNickname(
        _ raw: String,
        defaults: UserDefaults = .standard
    ) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = clean.isEmpty
            ? defaultNickname
            : String(clean.prefix(40))
        defaults.set(nickname, forKey: nicknameKey)
        return nickname
    }
}

enum AvatarStoreError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取这张图片，请选择 PNG、JPEG、HEIC 或 WebP 图片。"
        case .encodingFailed:
            return "头像图片处理失败，请换一张图片再试。"
        }
    }
}

struct PersonaSummaryField: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct AgentPersonaSummary {
    let fields: [PersonaSummaryField]
    let additionalDetails: String

    init?(markdown: String) {
        var parsedFields: [PersonaSummaryField] = []
        var customLines: [String] = []
        var isReadingCustomSection = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "## 自定义描述" {
                isReadingCustomSection = true
                continue
            }
            if isReadingCustomSection {
                if !line.isEmpty {
                    customLines.append(line)
                }
                continue
            }
            guard line.hasPrefix("- "),
                  let separator = line.firstIndex(of: "：")
            else {
                continue
            }
            let label = String(line[line.index(line.startIndex, offsetBy: 2)..<separator])
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty,
                  label != "名字",
                  label != "图标"
            else {
                continue
            }
            parsedFields.append(PersonaSummaryField(label: label, value: value))
        }

        let details = customLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details == "暂无额外描述。" ? "" : details
        guard !parsedFields.isEmpty || !cleanDetails.isEmpty else {
            return nil
        }
        fields = parsedFields
        additionalDetails = cleanDetails
    }
}

struct ParsedAssistantResponse: Equatable {
    let action: String?
    let emotionValue: Int?
    let metadata: [String]
    let body: String
    let isAwaitingActionClose: Bool
}

enum AssistantResponseParser {
    static func parse(_ raw: String) -> ParsedAssistantResponse {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "/" {
            return ParsedAssistantResponse(
                action: nil,
                emotionValue: nil,
                metadata: [],
                body: "",
                isAwaitingActionClose: true
            )
        }

        let opening: String
        let strictClosing: String
        let bareClosing: Character
        if text.hasPrefix("/(") {
            opening = "/("
            strictClosing = ")/"
            bareClosing = ")"
        } else if text.hasPrefix("/（") {
            opening = "/（"
            strictClosing = "）/"
            bareClosing = "）"
        } else {
            return ParsedAssistantResponse(
                action: nil,
                emotionValue: nil,
                metadata: [],
                body: raw.trimmingCharacters(in: .newlines),
                isAwaitingActionClose: false
            )
        }

        let remainder = text.dropFirst(opening.count)
        let closingRange: Range<String.Index>
        let bodyStart: String.Index
        if let strict = remainder.range(of: strictClosing) {
            closingRange = strict
            bodyStart = strict.upperBound
        } else if let separator = remainder.range(of: ";."),
                  let fallback = remainder.range(
                    of: String(bareClosing),
                    range: separator.upperBound..<remainder.endIndex
                  ) {
            closingRange = fallback
            bodyStart = fallback.upperBound
        } else {
            return ParsedAssistantResponse(
                action: nil,
                emotionValue: nil,
                metadata: [],
                body: "",
                isAwaitingActionClose: true
            )
        }

        let header = String(remainder[..<closingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHeader = header
            .replacingOccurrences(of: "；。", with: ";.")
        let fields = normalizedHeader
            .components(separatedBy: ";.")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let action = fields.first ?? ""
        let emotionValue = fields.dropFirst().first.flatMap(parseEmotionValue)
        let metadata = Array(fields.dropFirst(2)).filter { !$0.isEmpty }
        let body = String(remainder[bodyStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAssistantResponse(
            action: action.isEmpty ? nil : action,
            emotionValue: emotionValue,
            metadata: metadata,
            body: body,
            isAwaitingActionClose: false
        )
    }

    private static func parseEmotionValue(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Int?
        if let direct = Int(text) {
            value = direct
        } else if let range = text.range(
            of: #"[-+]?\d+"#,
            options: .regularExpression
        ) {
            value = Int(text[range])
        } else {
            value = nil
        }
        guard let value else { return nil }
        return min(max(value, -100), 100)
    }
}

enum EmotionScale {
    static func label(for value: Int) -> String {
        switch value {
        case ...(-70): return "很低落"
        case ...(-30): return "低落"
        case ..<(-10): return "低缓"
        case ...10: return "平静"
        case ...30: return "轻快"
        case ...70: return "高涨"
        default: return "非常高涨"
        }
    }
}

extension APISettings {
    static func configuration(for agent: AgentProfile) throws -> APIConfiguration {
        let provider = AgentAPIProvider(rawValue: agent.apiProvider)
            ?? AgentAPIProvider.none
        guard provider != .none else {
            throw APIConfigurationError.missingProvider
        }

        let values = try resolvedValues(
            provider: provider,
            baseURL: agent.apiBaseURL,
            model: agent.apiModel
        )
        let apiKey = try APIKeychain.load(for: agent.id)
        return APIConfiguration(
            endpoint: try endpointURL(from: values.baseURL),
            model: values.model,
            apiKey: apiKey?.isEmpty == false ? apiKey : nil
        )
    }
}

final class DatabaseStore {
    let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL? = nil) throws {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let directory = support.appendingPathComponent("Philotes", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            self.databaseURL = directory.appendingPathComponent("philotes.sqlite")
        }

        try FileManager.default.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let result = self.databaseURL.path.withCString {
            sqlite3_open_v2(
                $0,
                &db,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }
        guard result == SQLITE_OK else {
            throw DatabaseError.openFailed(message)
        }

        sqlite3_busy_timeout(db, 2_000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
        try seedIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadMemoryNodes() throws -> [MemoryNode] {
        let statement = try prepare("""
            SELECT id, agentID, kind, title, summary, source, createdAt, isSensitive
            FROM memory_node
            WHERE isArchived = 0
            ORDER BY createdAt DESC, id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var nodes: [MemoryNode] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            nodes.append(
                MemoryNode(
                    id: sqlite3_column_int64(statement, 0),
                    agentID: sqlite3_column_int64(statement, 1),
                    kind: string(at: 2, in: statement),
                    title: string(at: 3, in: statement),
                    summary: string(at: 4, in: statement),
                    source: string(at: 5, in: statement),
                    createdAt: date(from: string(at: 6, in: statement)),
                    isSensitive: sqlite3_column_int(statement, 7) != 0
                )
            )
        }
        return nodes
    }

    func loadMemoryLinks() throws -> [MemoryLink] {
        let statement = try prepare("""
            SELECT l.id, l.sourceMemoryID, l.targetMemoryID, l.kind
            FROM memory_link l
            JOIN memory_node source
                ON source.id = l.sourceMemoryID AND source.isArchived = 0
            JOIN memory_node target
                ON target.id = l.targetMemoryID AND target.isArchived = 0
            ORDER BY l.id ASC
            """)
        defer { sqlite3_finalize(statement) }

        var links: [MemoryLink] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            links.append(
                MemoryLink(
                    id: sqlite3_column_int64(statement, 0),
                    sourceMemoryID: sqlite3_column_int64(statement, 1),
                    targetMemoryID: sqlite3_column_int64(statement, 2),
                    kind: string(at: 3, in: statement)
                )
            )
        }
        return links
    }

    func loadAgents() throws -> [AgentProfile] {
        let statement = try prepare("""
            SELECT
                a.id,
                a.name,
                a.role,
                a.systemImage,
                a.avatarImagePath,
                a.accent,
                a.createdAt,
                a.lastActiveAt,
                a.apiProvider,
                a.apiBaseURL,
                a.apiModel,
                COUNT(m.id)
            FROM agent a
            LEFT JOIN memory_node m
                ON m.agentID = a.id AND m.isArchived = 0
            GROUP BY a.id
            ORDER BY a.lastActiveAt DESC, a.id ASC
            """)
        defer { sqlite3_finalize(statement) }

        var agents: [AgentProfile] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            agents.append(
                AgentProfile(
                    id: sqlite3_column_int64(statement, 0),
                    name: string(at: 1, in: statement),
                    role: string(at: 2, in: statement),
                    emoji: string(at: 3, in: statement),
                    avatarImagePath: nullableString(
                        at: 4,
                        in: statement
                    ),
                    accent: string(at: 5, in: statement),
                    createdAt: date(from: string(at: 6, in: statement)),
                    lastActiveAt: date(from: string(at: 7, in: statement)),
                    apiProvider: string(at: 8, in: statement),
                    apiBaseURL: string(at: 9, in: statement),
                    apiModel: string(at: 10, in: statement),
                    memoryCount: Int(sqlite3_column_int(statement, 11))
                )
            )
        }
        return agents
    }

    func loadMessages(for agentID: Int64) throws -> [ChatMessage] {
        let statement = try prepare("""
            SELECT id, role, body, createdAt
            FROM message
            WHERE agentID = ?
            ORDER BY createdAt ASC, id ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, agentID)

        var messages: [ChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            messages.append(
                ChatMessage(
                    id: sqlite3_column_int64(statement, 0),
                    role: ChatMessage.Role(rawValue: string(at: 1, in: statement)) ?? .system,
                    body: string(at: 2, in: statement),
                    createdAt: date(from: string(at: 3, in: statement))
                )
            )
        }
        return messages
    }

    func loadGroupChatRooms() throws -> [GroupChatRoom] {
        let statement = try prepare("""
            SELECT
                id, name, avatarEmoji, avatarImagePath,
                createdAt, lastActiveAt
            FROM chat_room
            ORDER BY lastActiveAt DESC, id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var rooms: [GroupChatRoom] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let roomID = sqlite3_column_int64(statement, 0)
            rooms.append(
                GroupChatRoom(
                    id: roomID,
                    name: string(at: 1, in: statement),
                    avatarEmoji: string(at: 2, in: statement),
                    avatarImagePath: nullableString(
                        at: 3,
                        in: statement
                    ),
                    createdAt: date(from: string(at: 4, in: statement)),
                    lastActiveAt: date(from: string(at: 5, in: statement)),
                    agentIDs: try loadGroupChatAgentIDs(roomID: roomID),
                    lastMessagePreview: try latestGroupMessagePreview(
                        roomID: roomID
                    )
                )
            )
        }
        return rooms
    }

    @discardableResult
    func createGroupChatRoom(
        name: String,
        agentIDs: [Int64]
    ) throws -> Int64 {
        let uniqueAgentIDs = Array(Set(agentIDs)).sorted()
        guard uniqueAgentIDs.count >= 2 else {
            throw DatabaseError.queryFailed(
                "群聊至少需要两位智能体。"
            )
        }
        let createdAt = Date()
        try execute("BEGIN IMMEDIATE")
        do {
            let roomStatement = try prepare("""
                INSERT INTO chat_room (
                    name, avatarEmoji, avatarImagePath,
                    createdAt, lastActiveAt
                )
                VALUES (?, ?, NULL, ?, ?)
                """)
            bind(name, at: 1, to: roomStatement)
            bind("💬", at: 2, to: roomStatement)
            bind(format(createdAt), at: 3, to: roomStatement)
            bind(format(createdAt), at: 4, to: roomStatement)
            guard sqlite3_step(roomStatement) == SQLITE_DONE else {
                sqlite3_finalize(roomStatement)
                throw DatabaseError.queryFailed(message)
            }
            sqlite3_finalize(roomStatement)
            let roomID = sqlite3_last_insert_rowid(db)

            for agentID in uniqueAgentIDs {
                let memberStatement = try prepare("""
                    INSERT INTO chat_room_agent (
                        roomID, agentID, joinedAt
                    )
                    VALUES (?, ?, ?)
                    """)
                sqlite3_bind_int64(memberStatement, 1, roomID)
                sqlite3_bind_int64(memberStatement, 2, agentID)
                bind(format(createdAt), at: 3, to: memberStatement)
                guard sqlite3_step(memberStatement) == SQLITE_DONE else {
                    sqlite3_finalize(memberStatement)
                    throw DatabaseError.queryFailed(message)
                }
                sqlite3_finalize(memberStatement)
            }
            try execute("COMMIT")
            return roomID
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func updateGroupChatRoomSettings(
        roomID: Int64,
        name: String,
        avatarEmoji: String,
        avatarImagePath: String?,
        agentIDs: [Int64]
    ) throws {
        let cleanName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanEmoji = avatarEmoji.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let uniqueAgentIDs = Array(Set(agentIDs)).sorted()
        guard !cleanName.isEmpty else {
            throw DatabaseError.queryFailed("聊天室名字不能为空。")
        }
        guard uniqueAgentIDs.count >= 1 else {
            throw DatabaseError.queryFailed(
                "聊天室至少需要保留一位智能体。"
            )
        }

        let now = Date()
        try execute("BEGIN IMMEDIATE")
        do {
            let update = try prepare("""
                UPDATE chat_room
                SET name = ?, avatarEmoji = ?, avatarImagePath = ?
                WHERE id = ?
                """)
            bind(cleanName, at: 1, to: update)
            bind(cleanEmoji.isEmpty ? "💬" : cleanEmoji, at: 2, to: update)
            bind(avatarImagePath, at: 3, to: update)
            sqlite3_bind_int64(update, 4, roomID)
            guard sqlite3_step(update) == SQLITE_DONE else {
                sqlite3_finalize(update)
                throw DatabaseError.queryFailed(message)
            }
            sqlite3_finalize(update)

            let deleteMembers = try prepare("""
                DELETE FROM chat_room_agent WHERE roomID = ?
                """)
            sqlite3_bind_int64(deleteMembers, 1, roomID)
            guard sqlite3_step(deleteMembers) == SQLITE_DONE else {
                sqlite3_finalize(deleteMembers)
                throw DatabaseError.queryFailed(message)
            }
            sqlite3_finalize(deleteMembers)

            for (index, agentID) in uniqueAgentIDs.enumerated() {
                let insert = try prepare("""
                    INSERT INTO chat_room_agent (
                        roomID, agentID, joinedAt
                    )
                    VALUES (?, ?, ?)
                    """)
                sqlite3_bind_int64(insert, 1, roomID)
                sqlite3_bind_int64(insert, 2, agentID)
                bind(
                    format(now.addingTimeInterval(Double(index) / 1_000)),
                    at: 3,
                    to: insert
                )
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    sqlite3_finalize(insert)
                    throw DatabaseError.queryFailed(message)
                }
                sqlite3_finalize(insert)
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteGroupChatRoom(roomID: Int64) throws {
        let statement = try prepare("DELETE FROM chat_room WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, roomID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    func loadGroupChatMessages(
        roomID: Int64
    ) throws -> [GroupChatMessage] {
        let statement = try prepare("""
            SELECT
                id, roomID, senderKind, senderAgentID, body,
                mentionedAgentIDs, createdAt
            FROM chat_room_message
            WHERE roomID = ?
            ORDER BY createdAt ASC, id ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, roomID)

        var messages: [GroupChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            messages.append(
                GroupChatMessage(
                    id: sqlite3_column_int64(statement, 0),
                    roomID: sqlite3_column_int64(statement, 1),
                    senderKind: GroupChatMessage.SenderKind(
                        rawValue: string(at: 2, in: statement)
                    ) ?? .system,
                    senderAgentID: sqlite3_column_type(statement, 3) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_int64(statement, 3),
                    body: string(at: 4, in: statement),
                    mentionedAgentIDs: parseIDList(
                        string(at: 5, in: statement)
                    ),
                    createdAt: date(from: string(at: 6, in: statement))
                )
            )
        }
        return messages
    }

    @discardableResult
    func appendGroupChatMessage(
        roomID: Int64,
        senderKind: GroupChatMessage.SenderKind,
        senderAgentID: Int64?,
        body: String,
        mentionedAgentIDs: [Int64]
    ) throws -> GroupChatMessage {
        let createdAt = Date()
        let statement = try prepare("""
            INSERT INTO chat_room_message (
                roomID, senderKind, senderAgentID, body,
                mentionedAgentIDs, createdAt
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, roomID)
        bind(senderKind.rawValue, at: 2, to: statement)
        if let senderAgentID {
            sqlite3_bind_int64(statement, 3, senderAgentID)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        bind(body, at: 4, to: statement)
        bind(
            mentionedAgentIDs.map(String.init).joined(separator: ","),
            at: 5,
            to: statement
        )
        bind(format(createdAt), at: 6, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
        let messageID = sqlite3_last_insert_rowid(db)
        let update = try prepare("""
            UPDATE chat_room SET lastActiveAt = ? WHERE id = ?
            """)
        bind(format(createdAt), at: 1, to: update)
        sqlite3_bind_int64(update, 2, roomID)
        _ = sqlite3_step(update)
        sqlite3_finalize(update)
        return GroupChatMessage(
            id: messageID,
            roomID: roomID,
            senderKind: senderKind,
            senderAgentID: senderAgentID,
            body: body,
            mentionedAgentIDs: mentionedAgentIDs,
            createdAt: createdAt
        )
    }

    func loadGroupChatAgentIDs(roomID: Int64) throws -> [Int64] {
        let statement = try prepare("""
            SELECT agentID
            FROM chat_room_agent
            WHERE roomID = ?
            ORDER BY joinedAt ASC, agentID ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, roomID)
        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    func countMessages(role: ChatMessage.Role? = nil) throws -> Int {
        let statement: OpaquePointer
        if let role {
            statement = try prepare(
                "SELECT COUNT(*) FROM message WHERE role = ?"
            )
            bind(role.rawValue, at: 1, to: statement)
        } else {
            statement = try prepare("SELECT COUNT(*) FROM message")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.queryFailed(message)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    @discardableResult
    func appendMessage(
        agentID: Int64,
        role: ChatMessage.Role,
        body: String
    ) throws -> ChatMessage {
        let createdAt = Date()
        let statement = try prepare("""
            INSERT INTO message (agentID, role, body, createdAt)
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, agentID)
        bind(role.rawValue, at: 2, to: statement)
        bind(body, at: 3, to: statement)
        bind(format(createdAt), at: 4, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
        try touchAgent(agentID, at: createdAt)

        return ChatMessage(
            id: sqlite3_last_insert_rowid(db),
            role: role,
            body: body,
            createdAt: createdAt
        )
    }

    @discardableResult
    func createMemory(
        agentID: Int64,
        kind: String,
        title: String,
        summary: String,
        source: String,
        isSensitive: Bool = false
    ) throws -> MemoryNode {
        let createdAt = Date()
        let statement = try prepare("""
            INSERT INTO memory_node (
                agentID, kind, title, summary, source,
                createdAt, isSensitive, isArchived
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, 0)
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, agentID)
        bind(kind, at: 2, to: statement)
        bind(title, at: 3, to: statement)
        bind(summary, at: 4, to: statement)
        bind(source, at: 5, to: statement)
        bind(format(createdAt), at: 6, to: statement)
        sqlite3_bind_int(statement, 7, isSensitive ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
        return MemoryNode(
            id: sqlite3_last_insert_rowid(db),
            agentID: agentID,
            kind: kind,
            title: title,
            summary: summary,
            source: source,
            createdAt: createdAt,
            isSensitive: isSensitive
        )
    }

    @discardableResult
    func createAgent(
        name: String,
        role: String,
        emoji: String,
        avatarImagePath: String? = nil,
        accent: String,
        apiProvider: String,
        apiBaseURL: String,
        apiModel: String
    ) throws -> Int64 {
        let createdAt = Date()
        let statement = try prepare("""
            INSERT INTO agent (
                name, role, systemImage, avatarImagePath, accent,
                createdAt, lastActiveAt,
                apiProvider, apiBaseURL, apiModel
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(name, at: 1, to: statement)
        bind(role, at: 2, to: statement)
        bind(emoji, at: 3, to: statement)
        bind(avatarImagePath, at: 4, to: statement)
        bind(accent, at: 5, to: statement)
        bind(format(createdAt), at: 6, to: statement)
        bind(format(createdAt), at: 7, to: statement)
        bind(apiProvider, at: 8, to: statement)
        bind(apiBaseURL, at: 9, to: statement)
        bind(apiModel, at: 10, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func touchAgent(_ id: Int64, at date: Date = Date()) throws {
        let statement = try prepare("UPDATE agent SET lastActiveAt = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(format(date), at: 1, to: statement)
        sqlite3_bind_int64(statement, 2, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    func updateAgentSettings(
        id: Int64,
        emoji: String,
        avatarImagePath: String?,
        accent: String,
        apiProvider: String,
        apiBaseURL: String,
        apiModel: String
    ) throws {
        let statement = try prepare("""
            UPDATE agent
            SET
                systemImage = ?,
                avatarImagePath = ?,
                accent = ?,
                apiProvider = ?,
                apiBaseURL = ?,
                apiModel = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(emoji, at: 1, to: statement)
        bind(avatarImagePath, at: 2, to: statement)
        bind(accent, at: 3, to: statement)
        bind(apiProvider, at: 4, to: statement)
        bind(apiBaseURL, at: 5, to: statement)
        bind(apiModel, at: 6, to: statement)
        sqlite3_bind_int64(statement, 7, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    func updateAgentAvatarPath(id: Int64, path: String?) throws {
        let statement = try prepare("""
            UPDATE agent
            SET avatarImagePath = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(path, at: 1, to: statement)
        sqlite3_bind_int64(statement, 2, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    func deleteAgentRecord(id: Int64) throws {
        let statement = try prepare("DELETE FROM agent WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    func deleteAgentData(id: Int64) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let links = try prepare("""
                DELETE FROM memory_link
                WHERE sourceMemoryID IN (
                    SELECT id FROM memory_node WHERE agentID = ?
                ) OR targetMemoryID IN (
                    SELECT id FROM memory_node WHERE agentID = ?
                )
                """)
            sqlite3_bind_int64(links, 1, id)
            sqlite3_bind_int64(links, 2, id)
            let linksResult = sqlite3_step(links)
            sqlite3_finalize(links)
            guard linksResult == SQLITE_DONE else {
                throw DatabaseError.queryFailed(message)
            }

            let memories = try prepare("DELETE FROM memory_node WHERE agentID = ?")
            sqlite3_bind_int64(memories, 1, id)
            let memoriesResult = sqlite3_step(memories)
            sqlite3_finalize(memories)
            guard memoriesResult == SQLITE_DONE else {
                throw DatabaseError.queryFailed(message)
            }

            let messages = try prepare("DELETE FROM message WHERE agentID = ?")
            sqlite3_bind_int64(messages, 1, id)
            let messagesResult = sqlite3_step(messages)
            sqlite3_finalize(messages)
            guard messagesResult == SQLITE_DONE else {
                throw DatabaseError.queryFailed(message)
            }

            let agent = try prepare("DELETE FROM agent WHERE id = ?")
            sqlite3_bind_int64(agent, 1, id)
            let agentResult = sqlite3_step(agent)
            sqlite3_finalize(agent)
            guard agentResult == SQLITE_DONE else {
                throw DatabaseError.queryFailed(message)
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteMemoryNode(id: Int64) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                DELETE FROM memory_link
                WHERE sourceMemoryID = \(id) OR targetMemoryID = \(id)
                """)

            let statement = try prepare("DELETE FROM memory_node WHERE id = ?")
            sqlite3_bind_int64(statement, 1, id)
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)

            guard result == SQLITE_DONE else {
                throw DatabaseError.queryFailed(message)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func linkMemories(
        sourceMemoryID: Int64,
        targetMemoryID: Int64,
        kind: String = "related"
    ) throws -> MemoryLink {
        let createdAt = Date()
        let statement = try prepare("""
            INSERT OR IGNORE INTO memory_link (
                sourceMemoryID, targetMemoryID, kind, createdAt
            )
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sourceMemoryID)
        sqlite3_bind_int64(statement, 2, targetMemoryID)
        bind(kind, at: 3, to: statement)
        bind(format(createdAt), at: 4, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }

        return MemoryLink(
            id: sqlite3_last_insert_rowid(db),
            sourceMemoryID: sourceMemoryID,
            targetMemoryID: targetMemoryID,
            kind: kind
        )
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS memory_node (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                agentID INTEGER NOT NULL DEFAULT 1,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT '本地记录',
                createdAt TEXT NOT NULL,
                isSensitive INTEGER NOT NULL DEFAULT 0,
                isArchived INTEGER NOT NULL DEFAULT 0
            )
            """)

        try addColumnIfNeeded(
            table: "memory_node",
            named: "agentID",
            definition: "INTEGER NOT NULL DEFAULT 1"
        )
        try addColumnIfNeeded(
            table: "memory_node",
            named: "summary",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        try addColumnIfNeeded(
            table: "memory_node",
            named: "source",
            definition: "TEXT NOT NULL DEFAULT '本地记录'"
        )
        try addColumnIfNeeded(
            table: "memory_node",
            named: "isSensitive",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )
        try addColumnIfNeeded(
            table: "memory_node",
            named: "isArchived",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )

        try execute("""
            CREATE TABLE IF NOT EXISTS agent (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                systemImage TEXT NOT NULL,
                avatarImagePath TEXT,
                accent TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                lastActiveAt TEXT NOT NULL,
                apiProvider TEXT NOT NULL DEFAULT 'none',
                apiBaseURL TEXT NOT NULL DEFAULT '',
                apiModel TEXT NOT NULL DEFAULT ''
            )
            """)

        try addColumnIfNeeded(
            table: "agent",
            named: "apiProvider",
            definition: "TEXT NOT NULL DEFAULT 'none'"
        )
        try addColumnIfNeeded(
            table: "agent",
            named: "apiBaseURL",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        try addColumnIfNeeded(
            table: "agent",
            named: "apiModel",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        try addColumnIfNeeded(
            table: "agent",
            named: "avatarImagePath",
            definition: "TEXT"
        )

        try execute("""
            CREATE TABLE IF NOT EXISTS message (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                agentID INTEGER NOT NULL DEFAULT 1,
                role TEXT NOT NULL,
                body TEXT NOT NULL,
                createdAt TEXT NOT NULL
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS memory_link (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sourceMemoryID INTEGER NOT NULL,
                targetMemoryID INTEGER NOT NULL,
                kind TEXT NOT NULL DEFAULT 'related',
                createdAt TEXT NOT NULL,
                UNIQUE(sourceMemoryID, targetMemoryID)
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS chat_room (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                avatarEmoji TEXT NOT NULL DEFAULT '💬',
                avatarImagePath TEXT,
                createdAt TEXT NOT NULL,
                lastActiveAt TEXT NOT NULL
            )
            """)

        try addColumnIfNeeded(
            table: "chat_room",
            named: "avatarEmoji",
            definition: "TEXT NOT NULL DEFAULT '💬'"
        )
        try addColumnIfNeeded(
            table: "chat_room",
            named: "avatarImagePath",
            definition: "TEXT"
        )

        try execute("""
            CREATE TABLE IF NOT EXISTS chat_room_agent (
                roomID INTEGER NOT NULL,
                agentID INTEGER NOT NULL,
                joinedAt TEXT NOT NULL,
                PRIMARY KEY (roomID, agentID),
                FOREIGN KEY (roomID) REFERENCES chat_room(id)
                    ON DELETE CASCADE,
                FOREIGN KEY (agentID) REFERENCES agent(id)
                    ON DELETE CASCADE
            )
            """)

        try execute("""
            CREATE TABLE IF NOT EXISTS chat_room_message (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                roomID INTEGER NOT NULL,
                senderKind TEXT NOT NULL,
                senderAgentID INTEGER,
                body TEXT NOT NULL,
                mentionedAgentIDs TEXT NOT NULL DEFAULT '',
                createdAt TEXT NOT NULL,
                FOREIGN KEY (roomID) REFERENCES chat_room(id)
                    ON DELETE CASCADE,
                FOREIGN KEY (senderAgentID) REFERENCES agent(id)
                    ON DELETE SET NULL
            )
            """)

        try addColumnIfNeeded(
            table: "message",
            named: "agentID",
            definition: "INTEGER NOT NULL DEFAULT 1"
        )

        try execute("""
            CREATE INDEX IF NOT EXISTS memory_node_agent
            ON memory_node(agentID, isArchived)
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS message_agent
            ON message(agentID, createdAt)
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS memory_link_source
            ON memory_link(sourceMemoryID)
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS memory_link_target
            ON memory_link(targetMemoryID)
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS chat_room_agent_room
            ON chat_room_agent(roomID)
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS chat_room_message_room
            ON chat_room_message(roomID, createdAt)
            """)

        try execute("PRAGMA user_version = 5")
    }

    private func addColumnIfNeeded(
        table: String,
        named name: String,
        definition: String
    ) throws {
        guard !columnExists(name, in: table) else { return }
        try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func columnExists(_ name: String, in table: String) -> Bool {
        guard let statement = try? prepare("PRAGMA table_info(\(table))") else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if string(at: 1, in: statement) == name {
                return true
            }
        }
        return false
    }

    private func seedIfNeeded() throws {
        var agents = try loadAgents()
#if DEBUG
        if agents.isEmpty {
            try seedDefaultAgents()
            agents = try loadAgents()
        }
#endif
        guard let primaryAgent = agents.first else { return }

        try execute("""
            UPDATE agent
            SET systemImage = CASE systemImage
                WHEN 'fish.fill' THEN '🐟'
                WHEN 'pencil' THEN '✍️'
                WHEN 'sparkles' THEN '✨'
                WHEN 'book.closed' THEN '📚'
                WHEN 'waveform' THEN '🎧'
                WHEN 'moon.stars' THEN '🌙'
                ELSE systemImage
            END
            WHERE systemImage IN (
                'fish.fill', 'pencil', 'sparkles',
                'book.closed', 'waveform', 'moon.stars'
            )
            """)
        try execute("""
            DELETE FROM memory_node
            WHERE title = 'SQLite smoke test'
            """)
        try execute("""
            DELETE FROM memory_node
            WHERE source = '原型样例'
               OR (source = '系统记录' AND title = '记忆库建立')
            """)
        try execute("""
            DELETE FROM message
            WHERE body LIKE '%现在还只是本地原型%'
               OR body LIKE '%等连接上真正的对话引擎%'
            """)
        try execute("""
            UPDATE memory_node
            SET agentID = \(primaryAgent.id)
            WHERE agentID NOT IN (SELECT id FROM agent)
            """)
        try execute("""
            UPDATE message
            SET agentID = \(primaryAgent.id)
            WHERE agentID NOT IN (SELECT id FROM agent)
            """)

        for (index, agent) in agents.enumerated() {
            if try scalarCount(from: "memory_node", agentID: agent.id) == 0 {
                try seedMemories(for: agent, index: index)
            }

            if try scalarCount(from: "message", agentID: agent.id) == 0 {
                _ = try appendMessage(
                    agentID: agent.id,
                    role: .assistant,
                    body: "我是\(agent.name)，\(agent.role)。\n今天想从哪里开始？"
                )
            }
        }

        try touchAgent(primaryAgent.id)
    }

    private func insertSeedNode(
        agentID: Int64,
        kind: String,
        title: String,
        summary: String,
        source: String
    ) throws {
        let statement = try prepare("""
            INSERT INTO memory_node (
                agentID, kind, title, summary, source, createdAt, isSensitive, isArchived
            )
            VALUES (?, ?, ?, ?, ?, ?, 0, 0)
            """)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, agentID)
        bind(kind, at: 2, to: statement)
        bind(title, at: 3, to: statement)
        bind(summary, at: 4, to: statement)
        bind(source, at: 5, to: statement)
        bind(format(Date()), at: 6, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    private func seedDefaultAgents() throws {
        let seeds: [(String, String, String, String)] = [
            ("斐洛", "生活搭档", "🐟", "blue"),
            ("克利俄", "创作搭档", "✍️", "lavender"),
            ("赫尔墨斯", "行动搭档", "✨", "mint")
        ]

        for (index, seed) in seeds.enumerated() {
            try insertSeedAgent(
                name: seed.0,
                role: seed.1,
                emoji: seed.2,
                accent: seed.3,
                offset: TimeInterval(-index * 60)
            )
        }
    }

    private func insertSeedAgent(
        name: String,
        role: String,
        emoji: String,
        accent: String,
        offset: TimeInterval
    ) throws {
        let timestamp = Date().addingTimeInterval(offset)
        let statement = try prepare("""
            INSERT INTO agent (name, role, systemImage, accent, createdAt, lastActiveAt)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(name, at: 1, to: statement)
        bind(role, at: 2, to: statement)
        bind(emoji, at: 3, to: statement)
        bind(accent, at: 4, to: statement)
        bind(format(timestamp), at: 5, to: statement)
        bind(format(timestamp), at: 6, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(message)
        }
    }

    private func seedMemories(for agent: AgentProfile, index: Int) throws {
        let memories: [(String, String, String)]
        switch index {
        default:
            memories = [
                ("date", "第一次相遇", "这是 \(agent.name) 第一次出现在你的宇宙里。")
            ]
        }

        for memory in memories {
            try insertSeedNode(
                agentID: agent.id,
                kind: memory.0,
                title: memory.1,
                summary: memory.2,
                source: "系统记录"
            )
        }
    }

    private func scalarCount(from table: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM \(table)")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.queryFailed(message)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func scalarCount(from table: String, agentID: Int64) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM \(table) WHERE agentID = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, agentID)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.queryFailed(message)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        to statement: OpaquePointer
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bind(value, at: index, to: statement)
    }

    private func string(at index: Int32, in statement: OpaquePointer) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private func nullableString(
        at index: Int32,
        in statement: OpaquePointer
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return string(at: index, in: statement)
    }

    private func latestGroupMessagePreview(roomID: Int64) throws -> String? {
        let statement = try prepare("""
            SELECT body
            FROM chat_room_message
            WHERE roomID = ?
            ORDER BY createdAt DESC, id DESC
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, roomID)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        let body = string(at: 0, in: statement)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = AssistantResponseParser.parse(body)
        let preview = parsed.body.isEmpty ? body : parsed.body
        return String(preview.prefix(90))
    }

    private func parseIDList(_ value: String) -> [Int64] {
        value
            .split(separator: ",")
            .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sql.withCString {
            sqlite3_exec(db, $0, nil, nil, &errorPointer)
        }
        if result != SQLITE_OK {
            let detail = errorPointer.map { String(cString: $0) } ?? message
            sqlite3_free(errorPointer)
            throw DatabaseError.queryFailed(detail)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sql.withCString {
            sqlite3_prepare_v2(db, $0, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.queryFailed(message)
        }
        return statement
    }

    private func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func date(from string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? Date()
    }

    private var message: String {
        guard let db else { return "SQLite database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }
}

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "SQLite 打开失败：\(message)"
        case .queryFailed(let message): return "SQLite 查询失败：\(message)"
        }
    }
}

private struct NextBatchLimitReached: Error {}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status = "正在打开本地记忆库…"
    @Published private(set) var agents: [AgentProfile] = []
    @Published private(set) var memories: [MemoryNode] = []
    @Published private(set) var memoryLinks: [MemoryLink] = []
    @Published private(set) var vaultCategories: [AgentVaultCategorySummary] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var activeAgentID: Int64?
    @Published private(set) var databasePath = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReplying = false
    @Published private(set) var streamingText = ""
    @Published private(set) var personalityActivationNoticeVisible = false
    @Published private(set) var pendingMacActions: [MacActionRequest] = []
    @Published private(set) var pendingMacActionPreamble = ""
    @Published private(set) var isExecutingMacActions = false
    @Published private(set) var requestCount = 0
    @Published private(set) var userAvatarPath: String?
    @Published private(set) var userNickname = UserProfileStore.defaultNickname
    @Published private(set) var groupChatRooms: [GroupChatRoom] = []
    @Published private(set) var activeGroupRoomID: Int64?
    @Published private(set) var groupChatMessages: [GroupChatMessage] = []
    @Published private(set) var isGroupReplying = false
    @Published private(set) var groupStreamingAgentID: Int64?
    @Published private(set) var groupStreamingText = ""
    @Published private(set) var groupChatError: String?

    private static let requestCountKey = "totalModelRequestCount"
    private var store: DatabaseStore?
    private var responseTask: Task<Void, Never>?
    private var responseRunID: UUID?
    private var groupResponseTask: Task<Void, Never>?
    private var groupResponseRunID: UUID?
    private var personalityNoticeTask: Task<Void, Never>?
    private var pendingMacActionAgentID: Int64?
    private var pendingMacActionIsFirstConversation = false
    private var pendingMacActionRound = 0
    private var pendingMacActionOriginalUserText = ""
    private var pendingMacActionHasCapturedScreen = false
    private var pendingMacTargetApplication: MacApplicationTarget?
    private var pendingMacToolCalls: [APIToolCall] = []
    private var pendingMacRequestMessages: [APIChatMessage] = []
    private var macActionRunID: UUID?
    private var activeMacMission: ActiveMacMission?

    private struct ActiveMacMission {
        var requestText: String
        var targetApplication: MacApplicationTarget?
        var hasCapturedScreen: Bool
        var lastToolCalls: [APIToolCall] = []
    }

    init(databaseURL: URL? = nil) {
        do {
            let store = try DatabaseStore(databaseURL: databaseURL)
            self.store = store
            databasePath = store.databaseURL.path
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Self.requestCountKey) == nil {
                requestCount = try store.countMessages(role: .assistant)
                defaults.set(requestCount, forKey: Self.requestCountKey)
            } else {
                requestCount = defaults.integer(forKey: Self.requestCountKey)
            }
            if let avatarPath = defaults.string(
                forKey: UserAvatarStore.defaultsKey
            ), FileManager.default.fileExists(atPath: avatarPath) {
                userAvatarPath = avatarPath
            } else {
                userAvatarPath = nil
            }
            userNickname = UserProfileStore.loadNickname(defaults: defaults)
            agents = try store.loadAgents()
            if migrateLegacyAPIConfiguration(store: store) {
                agents = try store.loadAgents()
            }
            memories = try store.loadMemoryNodes()
            memoryLinks = try store.loadMemoryLinks()
            groupChatRooms = try store.loadGroupChatRooms()
            activeAgentID = agents.first?.id
            if let activeAgentID {
                messages = try store.loadMessages(for: activeAgentID)
            }
            activeGroupRoomID = groupChatRooms.first?.id
            if let activeGroupRoomID {
                groupChatMessages = try store.loadGroupChatMessages(
                    roomID: activeGroupRoomID
                )
            }
            status = "记忆库已就绪"
            synchronizeAllAgentVaults(store: store)
        } catch {
            status = "记忆库启动失败"
            errorMessage = error.localizedDescription
        }
    }

    var activeAgent: AgentProfile? {
        agents.first { $0.id == activeAgentID }
    }

    var activeGroupRoom: GroupChatRoom? {
        guard let activeGroupRoomID else { return nil }
        return groupChatRooms.first { $0.id == activeGroupRoomID }
    }

    func memories(for agentID: Int64) -> [MemoryNode] {
        memories.filter { $0.agentID == agentID }
    }

    func groupMembers(for room: GroupChatRoom) -> [AgentProfile] {
        room.agentIDs.compactMap { agentID in
            agents.first { $0.id == agentID }
        }
    }

    func vaultCategories(for agentID: Int64) -> [AgentVaultCategorySummary] {
        vaultCategories.filter { $0.agentID == agentID }
    }

    func refreshVaultCategories() {
        vaultCategories = agents.flatMap {
            AgentMemoryVaultStore.categorySummaries(for: $0.id)
        }
    }

    private func synchronizeAllAgentVaults(store: DatabaseStore) {
        var lastError: Error?
        for agent in agents {
            do {
                let agentMessages = try store.loadMessages(for: agent.id)
                try AgentMemoryVaultStore.ensureVault(
                    for: agent,
                    memories: memories(for: agent.id),
                    links: memoryLinks,
                    messages: agentMessages
                )
            } catch {
                lastError = error
            }
        }
        if let lastError {
            errorMessage = lastError.localizedDescription
            status = "记忆库已就绪，部分心智库需要检查"
        }
        refreshVaultCategories()
    }

    @discardableResult
    private func persistMessage(
        store: DatabaseStore,
        agent: AgentProfile,
        role: ChatMessage.Role,
        body: String
    ) throws -> ChatMessage {
        let message = try store.appendMessage(
            agentID: agent.id,
            role: role,
            body: body
        )
        try? AgentMemoryVaultStore.appendMessage(
            message,
            for: agent
        )
        refreshVaultCategories()
        return message
    }

    private func rememberExplicitMemoryIfNeeded(
        in text: String,
        for agent: AgentProfile,
        store: DatabaseStore
    ) {
        guard let candidate = AgentMemoryVaultStore.extractExplicitMemory(
            from: text
        ),
        !memories.contains(where: {
            $0.agentID == agent.id && $0.summary == candidate.summary
        })
        else {
            return
        }

        do {
            let memory = try store.createMemory(
                agentID: agent.id,
                kind: candidate.kind,
                title: candidate.title,
                summary: candidate.summary,
                source: "对话自动记忆"
            )
            memories.insert(memory, at: 0)
            refreshAgents()
            try AgentMemoryVaultStore.ensureVault(
                for: agent,
                memories: self.memories(for: agent.id),
                links: memoryLinks
            )
            refreshVaultCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActiveAgent(_ agent: AgentProfile) {
        guard let store else { return }
        if activeAgentID != agent.id {
            cancelResponse()
            cancelPendingMacActions()
            hidePersonalityActivationNotice()
            activeMacMission = nil
        }
        do {
            try store.touchAgent(agent.id)
            activeAgentID = agent.id
            messages = try store.loadMessages(for: agent.id)
            refreshAgents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActiveGroupRoom(_ room: GroupChatRoom) {
        guard let store else { return }
        guard activeGroupRoomID != room.id else { return }
        cancelGroupResponse()
        do {
            activeGroupRoomID = room.id
            groupChatMessages = try store.loadGroupChatMessages(
                roomID: room.id
            )
            groupChatError = nil
        } catch {
            groupChatError = error.localizedDescription
        }
    }

    @discardableResult
    func createGroupRoom(
        name: String,
        agentIDs: [Int64]
    ) -> Bool {
        guard let store else { return false }
        let uniqueIDs = Array(Set(agentIDs)).sorted()
        guard uniqueIDs.count >= 2 else {
            groupChatError = GroupChatError.insufficientMembers
                .localizedDescription
            return false
        }

        let selectedNames = uniqueIDs.compactMap { id in
            agents.first { $0.id == id }?.name
        }
        let cleanName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let resolvedName = cleanName.isEmpty
            ? selectedNames.prefix(3).joined(separator: "、")
            : cleanName

        do {
            let roomID = try store.createGroupChatRoom(
                name: resolvedName,
                agentIDs: uniqueIDs
            )
            groupChatRooms = try store.loadGroupChatRooms()
            activeGroupRoomID = roomID
            groupChatMessages = []
            groupChatError = nil
            status = "群聊「\(resolvedName)」已建好"
            return true
        } catch {
            groupChatError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateGroupRoom(
        _ room: GroupChatRoom,
        name: String,
        avatarEmoji: String,
        avatarImageURL: URL?,
        removeAvatarImage: Bool,
        agentIDs: [Int64]
    ) -> Bool {
        guard let store else { return false }
        if activeGroupRoomID == room.id {
            cancelGroupResponse()
        }
        let uniqueAgentIDs = Array(Set(agentIDs)).sorted()
        guard uniqueAgentIDs.count >= 1 else {
            groupChatError = GroupChatError.insufficientMembers
                .localizedDescription
            return false
        }

        var importedAvatarPath: String?
        do {
            let resolvedAvatarPath: String?
            if let avatarImageURL {
                let path = try GroupChatAvatarStore.importImage(
                    from: avatarImageURL,
                    for: room.id
                )
                importedAvatarPath = path
                resolvedAvatarPath = path
            } else if removeAvatarImage {
                resolvedAvatarPath = nil
            } else {
                resolvedAvatarPath = room.avatarImagePath
            }

            try store.updateGroupChatRoomSettings(
                roomID: room.id,
                name: name,
                avatarEmoji: avatarEmoji,
                avatarImagePath: resolvedAvatarPath,
                agentIDs: uniqueAgentIDs
            )
            if room.avatarImagePath != resolvedAvatarPath {
                GroupChatAvatarStore.delete(path: room.avatarImagePath)
            }
            groupChatRooms = try store.loadGroupChatRooms()
            groupChatError = nil
            status = "聊天室设置已保存"
            return true
        } catch {
            if let importedAvatarPath,
               importedAvatarPath != room.avatarImagePath {
                GroupChatAvatarStore.delete(path: importedAvatarPath)
            }
            groupChatError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteGroupRoom(_ room: GroupChatRoom) -> Bool {
        guard let store else { return false }
        let deletedActiveRoom = activeGroupRoomID == room.id
        if deletedActiveRoom {
            cancelGroupResponse()
        }
        do {
            try store.deleteGroupChatRoom(roomID: room.id)
            GroupChatAvatarStore.deleteImage(for: room.id)
            groupChatRooms = try store.loadGroupChatRooms()
            if deletedActiveRoom {
                activeGroupRoomID = groupChatRooms.first?.id
                if let activeGroupRoomID {
                    groupChatMessages = try store.loadGroupChatMessages(
                        roomID: activeGroupRoomID
                    )
                } else {
                    groupChatMessages = []
                }
            }
            groupChatError = nil
            status = "聊天室「\(room.name)」已删除"
            return true
        } catch {
            groupChatError = error.localizedDescription
            return false
        }
    }

    func clearGroupChatError() {
        groupChatError = nil
    }

    @discardableResult
    func createAgent(
        name: String,
        role: String,
        emoji: String,
        accent: String,
        apiProvider: AgentAPIProvider,
        apiBaseURL: String,
        apiModel: String,
        apiKey: String,
        persona: AgentPersonaDraft,
        avatarImageURL: URL?
    ) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanRole.isEmpty, let store else { return false }

        var createdAgentID: Int64?
        do {
            let values = try APISettings.resolvedValues(
                provider: apiProvider,
                baseURL: apiBaseURL,
                model: apiModel
            )
            let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            cancelResponse()
            let id = try store.createAgent(
                name: cleanName,
                role: cleanRole,
                emoji: emoji,
                accent: accent,
                apiProvider: apiProvider.rawValue,
                apiBaseURL: values.baseURL,
                apiModel: values.model
            )
            createdAgentID = id
            cancelPendingMacActions()
            try AgentPersonaStore.write(persona, for: id)
            if let avatarImageURL {
                let avatarPath = try AgentAvatarStore.importImage(
                    from: avatarImageURL,
                    for: id
                )
                try store.updateAgentAvatarPath(
                    id: id,
                    path: avatarPath
                )
            }
            if apiProvider != .none && !cleanKey.isEmpty {
                try APIKeychain.save(cleanKey, for: id)
            }
            hidePersonalityActivationNotice()
            refreshAgents()
            activeAgentID = id
            messages = []
            guard let createdAgent = agents.first(where: { $0.id == id }) else {
                throw AgentMemoryVaultError.agentNotAvailable(id)
            }
            try AgentMemoryVaultStore.ensureVault(
                for: createdAgent,
                memories: [],
                links: []
            )
            refreshVaultCategories()
            status = "新的智能体已加入星海，心智库已建立"
            return true
        } catch {
            if let createdAgentID {
                try? APIKeychain.delete(for: createdAgentID)
                AgentPersonaStore.delete(for: createdAgentID)
                AgentAvatarStore.deleteImage(for: createdAgentID)
                AgentMemoryVaultStore.deleteVault(for: createdAgentID)
                try? store.deleteAgentRecord(id: createdAgentID)
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importAgentFromChatMemory(
        blueprint: ImportedAgentBlueprint,
        sourceDocument: ImportTextDocument,
        apiProvider: AgentAPIProvider,
        apiBaseURL: String,
        apiModel: String,
        apiKey: String,
        onProgress: @MainActor (String) -> Void = { _ in }
    ) async throws -> AgentProfile {
        guard apiProvider != .none else {
            throw APIConfigurationError.missingProvider
        }
        guard let store else {
            throw DatabaseError.openFailed("本地数据库尚未就绪。")
        }

        let persona = blueprint.persona
        let created = createAgent(
            name: blueprint.name,
            role: blueprint.relationship,
            emoji: blueprint.emoji,
            accent: blueprint.accent,
            apiProvider: apiProvider,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            apiKey: apiKey,
            persona: persona,
            avatarImageURL: nil
        )
        guard created,
              let agentID = activeAgentID,
              let agent = agents.first(where: { $0.id == agentID })
        else {
            throw ChatMemoryImportError.invalidBlueprint
        }

        do {
            for memory in blueprint.memories {
                try store.createMemory(
                    agentID: agent.id,
                    kind: memory.kind,
                    title: memory.title,
                    summary: memory.summary,
                    source: "聊天记忆导入",
                    isSensitive: memory.isSensitive
                )
            }
            try AgentMemoryVaultStore.saveImportedSource(
                sourceDocument,
                for: agent
            )
            for entry in blueprint.diaryEntries {
                try AgentMemoryVaultStore.appendImportedDiaryEntry(
                    entry,
                    for: agent
                )
            }

            refreshMemories()
            refreshAgents()
            if let refreshedAgent = agents.first(where: { $0.id == agent.id }) {
                try AgentMemoryVaultStore.ensureVault(
                    for: refreshedAgent,
                    memories: self.memories(for: agent.id),
                    links: memoryLinks
                )
            }
            refreshVaultCategories()

            let configuration = try APISettings.configuration(for: agent)
            onProgress("正在按照第一次唤醒程序让\(agent.name)醒来…")
            recordModelRequest()
            let result = try await CustomAPIClient(
                configuration: configuration
            ).completeChatWithTools(
                messages: blueprint.wakeMessages(
                    userDisplayName: userNickname
                ),
                tools: []
            )
            let wakeText = result.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let parsed = AssistantResponseParser.parse(wakeText)
            guard !wakeText.isEmpty, !parsed.body.isEmpty else {
                throw ChatMemoryImportError.emptyWakeResponse
            }
            let reply = try persistMessage(
                store: store,
                agent: agents.first(where: { $0.id == agent.id }) ?? agent,
                role: .assistant,
                body: wakeText
            )
            if activeAgentID == agent.id {
                messages.append(reply)
            }
            refreshAgents()
            refreshVaultCategories()
            hidePersonalityActivationNotice()
            status = "\(agent.name) 已经从聊天记忆中醒来"
            return agents.first(where: { $0.id == agent.id }) ?? agent
        } catch {
            if let createdAgent = agents.first(where: { $0.id == agent.id }) {
                _ = deleteAgent(createdAgent)
            }
            errorMessage = error.localizedDescription
            status = "从聊天记忆唤醒失败"
            throw error
        }
    }

    @discardableResult
    func updateAgentSettings(
        _ agent: AgentProfile,
        emoji: String,
        accent: String,
        apiProvider: AgentAPIProvider,
        apiBaseURL: String,
        apiModel: String,
        apiKeyInput: String,
        clearStoredAPIKey: Bool,
        avatarImageURL: URL?,
        removeAvatarImage: Bool
    ) -> Bool {
        guard let store else { return false }
        var importedAvatarPath: String?
        do {
            let values = try APISettings.resolvedValues(
                provider: apiProvider,
                baseURL: apiBaseURL,
                model: apiModel
            )
            let resolvedAvatarPath: String?
            if let avatarImageURL {
                let path = try AgentAvatarStore.importImage(
                    from: avatarImageURL,
                    for: agent.id
                )
                importedAvatarPath = path
                resolvedAvatarPath = path
            } else if removeAvatarImage {
                resolvedAvatarPath = nil
            } else {
                resolvedAvatarPath = agent.avatarImagePath
            }
            try store.updateAgentSettings(
                id: agent.id,
                emoji: emoji,
                avatarImagePath: resolvedAvatarPath,
                accent: accent,
                apiProvider: apiProvider.rawValue,
                apiBaseURL: values.baseURL,
                apiModel: values.model
            )

            if clearStoredAPIKey {
                try APIKeychain.delete(for: agent.id)
            } else if apiProvider != .none {
                let cleanKey = apiKeyInput.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !cleanKey.isEmpty {
                    try APIKeychain.save(cleanKey, for: agent.id)
                }
            }
            if agent.avatarImagePath != resolvedAvatarPath {
                AgentAvatarStore.delete(path: agent.avatarImagePath)
            }
            refreshAgents()
            status = "智能体设定已保存"
            return true
        } catch {
            if let importedAvatarPath,
               importedAvatarPath != agent.avatarImagePath {
                AgentAvatarStore.delete(path: importedAvatarPath)
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateUserAvatar(from sourceURL: URL) -> Bool {
        do {
            let path = try UserAvatarStore.importImage(from: sourceURL)
            userAvatarPath = path
            UserDefaults.standard.set(
                path,
                forKey: UserAvatarStore.defaultsKey
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateUserAvatar(from data: Data) -> Bool {
        do {
            let path = try UserAvatarStore.importImage(data: data)
            userAvatarPath = path
            UserDefaults.standard.set(
                path,
                forKey: UserAvatarStore.defaultsKey
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeUserAvatar() {
        UserAvatarStore.delete()
        UserDefaults.standard.removeObject(forKey: UserAvatarStore.defaultsKey)
        userAvatarPath = nil
    }

    @discardableResult
    func updateUserNickname(_ nickname: String) -> Bool {
        userNickname = UserProfileStore.saveNickname(nickname)
        return true
    }

    private func recordModelRequest() {
        requestCount += 1
        UserDefaults.standard.set(
            requestCount,
            forKey: Self.requestCountKey
        )
    }

    @discardableResult
    func sendGroupMessage(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isGroupReplying,
              pendingMacActions.isEmpty,
              !isExecutingMacActions,
              let store,
              let room = activeGroupRoom
        else {
            if !pendingMacActions.isEmpty || isExecutingMacActions {
                groupChatError = GroupChatError.pendingMacAction
                    .localizedDescription
            }
            return false
        }

        let members = groupMembers(for: room)
        guard members.count >= 2 else {
            groupChatError = GroupChatError.insufficientMembers
                .localizedDescription
            return false
        }

        let mentions = GroupChatMentionParser.resolve(
            text,
            members: members
        )
        guard mentions.unresolvedTokens.isEmpty else {
            groupChatError = GroupChatError.unknownMentions(
                mentions.unresolvedTokens
            ).localizedDescription
            return false
        }
        guard !mentions.agents.isEmpty else {
            groupChatError = GroupChatError.missingMentions
                .localizedDescription
            return false
        }
        guard mentions.agents.count <= 2 else {
            groupChatError = GroupChatError.tooManyMentions(
                mentions.agents.count
            ).localizedDescription
            return false
        }

        let configuredAgents: [(AgentProfile, APIConfiguration)]
        do {
            configuredAgents = try mentions.agents.map { agent in
                do {
                    return (
                        agent,
                        try APISettings.configuration(for: agent)
                    )
                } catch {
                    throw GroupChatError.agentConfiguration(
                        agent.name,
                        error.localizedDescription
                    )
                }
            }
        } catch {
            groupChatError = error.localizedDescription
            return false
        }

        cancelResponse()
        do {
            let userMessage = try store.appendGroupChatMessage(
                roomID: room.id,
                senderKind: .user,
                senderAgentID: nil,
                body: text,
                mentionedAgentIDs: mentions.agents.map(\.id)
            )
            groupChatMessages.append(userMessage)
            try refreshGroupChatRooms(using: store)
            groupChatError = appendGroupMessageToAgentVaults(
                userMessage,
                room: room,
                speaker: "主人"
            )

            isGroupReplying = true
            groupStreamingAgentID = configuredAgents.first?.0.id
            groupStreamingText = ""
            status = "群聊里有人正在回应…"

            let runID = UUID()
            groupResponseRunID = runID
            groupResponseTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for (agent, configuration) in configuredAgents {
                        try Task.checkCancellation()
                        guard groupResponseRunID == runID else { return }

                        groupStreamingAgentID = agent.id
                        groupStreamingText = ""
                        let requestMessages = makeGroupRequestMessages(
                            for: agent,
                            room: room,
                            history: groupChatMessages,
                            mentionedAgentIDs: mentions.agents.map(\.id)
                        )
                        recordModelRequest()

                        let result = try await streamReply(
                            client: CustomAPIClient(
                                configuration: configuration
                            ),
                            messages: requestMessages,
                            tools: []
                        ) { [weak self] delta in
                            guard let self,
                                  groupResponseRunID == runID,
                                  groupStreamingAgentID == agent.id
                            else {
                                return
                            }
                            groupStreamingText += delta
                        }
                        try Task.checkCancellation()
                        guard groupResponseRunID == runID else { return }

                        let cleanReply = result.text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        let parsed = AssistantResponseParser.parse(cleanReply)
                        guard !cleanReply.isEmpty, !parsed.body.isEmpty else {
                            throw GroupChatError.emptyReply(agent.name)
                        }

                        let reply = try store.appendGroupChatMessage(
                            roomID: room.id,
                            senderKind: .agent,
                            senderAgentID: agent.id,
                            body: cleanReply,
                            mentionedAgentIDs: []
                        )
                        groupChatMessages.append(reply)
                        try refreshGroupChatRooms(using: store)
                        groupChatError = appendGroupMessageToAgentVaults(
                            reply,
                            room: room,
                            speaker: agent.name
                        )
                    }

                    groupStreamingAgentID = nil
                    groupStreamingText = ""
                    status = groupChatError == nil
                        ? "群聊记忆已保存"
                        : "群聊已保存，心智库需要检查"
                } catch is CancellationError {
                    guard groupResponseRunID == runID else { return }
                    groupStreamingAgentID = nil
                    groupStreamingText = ""
                    status = "已停止群聊回复"
                } catch {
                    guard groupResponseRunID == runID else { return }
                    groupStreamingAgentID = nil
                    groupStreamingText = ""
                    groupChatError = error.localizedDescription
                    status = "群聊回复失败"
                }

                guard groupResponseRunID == runID else { return }
                isGroupReplying = false
                groupResponseTask = nil
                groupResponseRunID = nil
            }
            return true
        } catch {
            groupChatError = error.localizedDescription
            status = "群聊消息没有保存"
            return false
        }
    }

    func cancelGroupResponse() {
        let hadActiveResponse = groupResponseTask != nil
            || groupResponseRunID != nil
            || isGroupReplying
        groupResponseTask?.cancel()
        groupResponseTask = nil
        groupResponseRunID = nil
        groupStreamingAgentID = nil
        groupStreamingText = ""
        isGroupReplying = false
        if hadActiveResponse {
            status = "已停止群聊回复"
        }
    }

    @discardableResult
    func send(_ rawText: String) -> Bool {
        if isGroupReplying {
            cancelGroupResponse()
        }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isReplying,
              pendingMacActions.isEmpty,
              !isExecutingMacActions,
              let store,
              let agentID = activeAgentID,
              let agent = activeAgent
        else {
            return false
        }

        do {
            let configuration = try APISettings.configuration(for: agent)
            let macMission = resolveMacMission(
                for: text,
                history: messages
            )
            let missionText = macMission?.requestText ?? text
            let isFirstConversation = !messages.contains {
                $0.role == .assistant
            }
            let message = try persistMessage(
                store: store,
                agent: agent,
                role: .user,
                body: text
            )
            messages.append(message)
            rememberExplicitMemoryIfNeeded(
                in: text,
                for: agent,
                store: store
            )
            isReplying = true
            streamingText = ""
            errorMessage = nil
            status = "正在回复…"

            let client = CustomAPIClient(configuration: configuration)
            let tools = MacControlPreferences.isEnabled
                ? MacControlTool.enabledDefinitions
                : []
            let initialToolChoice = forcedMacToolChoice(
                for: missionText,
                mission: macMission,
                preferPreviousToolCall: isMacMissionContinuation(text),
                tools: tools,
                afterAction: false
            )
            let plannedLocalToolCalls = localToolCalls(
                for: missionText,
                mission: macMission,
                toolChoice: initialToolChoice
            )
            #if DEBUG
            print(
                "[PhilotesAgent] tools=\(tools.map(\.function.name)) "
                    + "choice=\(String(describing: initialToolChoice))"
            )
            #endif
            let requestMessages = makeRequestMessages(
                for: agent,
                history: messages,
                query: "\(text)\n\(missionText)",
                availableTools: tools
            )
            let runID = UUID()
            responseRunID = runID
            recordModelRequest()

            responseTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var shouldAutoApprovePendingActions = false
                do {
                    let result: ChatStreamResult
                    do {
                        result = try await streamReply(
                            client: client,
                            messages: requestMessages,
                            tools: tools,
                            toolChoice: initialToolChoice
                        ) { [weak self] delta in
                            self?.streamingText += delta
                        }
                    } catch let apiError as CustomAPIError {
                        if case .emptyResponse = apiError,
                           !plannedLocalToolCalls.isEmpty {
                            result = ChatStreamResult(
                                text: "",
                                toolCalls: []
                            )
                        } else {
                            throw apiError
                        }
                    }
                    try Task.checkCancellation()
                    guard responseRunID == runID else { return }

                    let cleanReply = result.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let forcedToolName = toolName(for: initialToolChoice)
                    let useLocalToolCall = !plannedLocalToolCalls.isEmpty
                        && !result.toolCalls.contains {
                            $0.name == forcedToolName
                        }
                    #if DEBUG
                    print(
                        "[PhilotesAgent] serverTools="
                            + "\(result.toolCalls.map(\.name)) "
                            + "forced=\(forcedToolName ?? "nil") "
                            + "local=\(useLocalToolCall)"
                    )
                    #endif
                    let resolvedToolCalls = useLocalToolCall
                        ? plannedLocalToolCalls
                        : result.toolCalls
                    if !resolvedToolCalls.isEmpty,
                       var mission = activeMacMission {
                        mission.lastToolCalls = resolvedToolCalls
                        activeMacMission = mission
                    }
                    let resolvedReply = cleanReply.isEmpty
                        && useLocalToolCall
                        ? "我先提出这一步操作，请主人确认。"
                        : cleanReply
                    guard !resolvedReply.isEmpty || !resolvedToolCalls.isEmpty else {
                        throw CustomAPIError.emptyResponse
                    }

                    if !resolvedToolCalls.isEmpty {
                        guard resolvedToolCalls.count <= 3 else {
                            throw MacControlError.invalidArguments(
                                "一次最多请求 3 个 Mac 操作。"
                            )
                        }
                        let requests = try resolvedToolCalls.map {
                            try MacControlTool.request(from: $0)
                        }
                        if !resolvedReply.isEmpty {
                            let reply = try persistMessage(
                                store: store,
                                agent: agent,
                                role: .assistant,
                                body: resolvedReply
                            )
                            if activeAgentID == agentID {
                                messages.append(reply)
                            }
                        }
                        pendingMacActionAgentID = agentID
                        pendingMacActionPreamble = resolvedReply
                        pendingMacActionIsFirstConversation = isFirstConversation
                        pendingMacActionRound = 1
                        pendingMacActionOriginalUserText = missionText
                        pendingMacActionHasCapturedScreen = false
                        pendingMacTargetApplication = requests
                            .compactMap {
                                MacControlService.targetApplication(for: $0)
                            }
                            .last
                            ?? macMission?.targetApplication
                            ?? MacIntentPlanner.applicationTarget(
                                in: missionText
                            )
                        pendingMacToolCalls = resolvedToolCalls
                        pendingMacRequestMessages = requestMessages
                        pendingMacActions = requests
                        refreshAgents()
                        MacSystemPermission.requestPermissions(for: requests)
                        streamingText = ""
                        if MacControlPreferences.isAutoApproveEnabled {
                            status = "已授权，正在自动执行 Mac 操作"
                            shouldAutoApprovePendingActions = true
                        } else {
                            status = "等待你确认 Mac 操作"
                        }
                    } else {
                        activeMacMission = nil
                        let reply = try persistMessage(
                            store: store,
                            agent: agent,
                            role: .assistant,
                            body: cleanReply
                        )
                        if activeAgentID == agentID {
                            messages.append(reply)
                        }
                        if isFirstConversation,
                           AgentPersonaStore.load(for: agentID) != nil {
                            showPersonalityActivationNotice()
                        }
                        refreshAgents()
                        streamingText = ""
                        status = "记忆库已就绪"
                    }
                } catch is CancellationError {
                    guard responseRunID == runID else { return }
                    streamingText = ""
                    status = "已停止回复"
                } catch {
                    guard responseRunID == runID else { return }
                    errorMessage = error.localizedDescription
                    status = "回复失败"
                    streamingText = ""
                }
                guard responseRunID == runID else { return }
                isReplying = false
                responseTask = nil
                responseRunID = nil
                if shouldAutoApprovePendingActions {
                    approveEntireMacTask()
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            status = "智能体 API 尚未配置"
            return false
        }
    }

    func cancelResponse() {
        let hadActiveResponse = responseTask != nil
            || responseRunID != nil
            || isReplying
        responseTask?.cancel()
        responseTask = nil
        responseRunID = nil
        streamingText = ""
        isReplying = false
        if hadActiveResponse {
            status = "已停止回复"
        }
    }

    func cancelPendingMacActions() {
        macActionRunID = nil
        pendingMacActions = []
        pendingMacActionPreamble = ""
        pendingMacActionAgentID = nil
        pendingMacActionIsFirstConversation = false
        pendingMacActionRound = 0
        pendingMacActionOriginalUserText = ""
        pendingMacActionHasCapturedScreen = false
        pendingMacTargetApplication = nil
        pendingMacToolCalls = []
        pendingMacRequestMessages = []
        isExecutingMacActions = false
    }

    func approvePendingMacActions() {
        executePendingMacActions(autoContinue: false)
    }

    func approveEntireMacTask() {
        executePendingMacActions(autoContinue: true)
    }

    func alwaysAllowMacActions() {
        UserDefaults.standard.set(
            true,
            forKey: MacControlPreferences.autoApproveKey
        )
        UserDefaults.standard.set(
            true,
            forKey: MacControlPreferences.advancedEnabledKey
        )
        MacSystemPermission.requestAllAdvancedAccess()
        status = "已开启一键授权，正在执行 Mac 操作"
        executePendingMacActions(autoContinue: true)
    }

    private func executePendingMacActions(autoContinue: Bool) {
        guard let store,
              let agentID = pendingMacActionAgentID,
              let agent = agents.first(where: { $0.id == agentID }),
              activeAgentID == agentID,
              !pendingMacActions.isEmpty,
              !isExecutingMacActions
        else {
            return
        }

        let actions = pendingMacActions
        let toolCalls = pendingMacToolCalls
        let requestMessages = pendingMacRequestMessages
        let preamble = pendingMacActionPreamble
        let isFirstConversation = pendingMacActionIsFirstConversation
        let round = pendingMacActionRound
        let originalUserText = pendingMacActionOriginalUserText
        let hadCapturedScreen = pendingMacActionHasCapturedScreen
        let initialForegroundApplication = pendingMacTargetApplication
        let actionIDs = Set(actions.map(\.toolCallID))
        let toolCallIDs = Set(toolCalls.map(\.id))
        guard actions.count == toolCalls.count,
              actionIDs == toolCallIDs,
              actionIDs.count == actions.count,
              !actionIDs.contains("")
        else {
            errorMessage = "这次 Mac 操作请求已经失效，请重新发送消息。"
            cancelPendingMacActions()
            return
        }

        let runID = UUID()
        macActionRunID = runID
        isExecutingMacActions = true
        status = "正在执行 Mac 操作…"
        errorMessage = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var resultLines: [String] = []
            var outcomeByToolCallID: [String: String] = [:]
            var hasFailure = false
            var followupUsedModel = false
            var stagedNextBatch = false
            var hasCapturedScreen = hadCapturedScreen
            var foregroundApplication = initialForegroundApplication

            defer {
                if macActionRunID == runID {
                    if !stagedNextBatch {
                        pendingMacActions = []
                        pendingMacActionPreamble = ""
                        pendingMacActionAgentID = nil
                        pendingMacActionIsFirstConversation = false
                        pendingMacActionRound = 0
                        pendingMacActionOriginalUserText = ""
                        pendingMacActionHasCapturedScreen = false
                        pendingMacTargetApplication = nil
                        pendingMacToolCalls = []
                        pendingMacRequestMessages = []
                    }
                    isExecutingMacActions = false
                    macActionRunID = nil
                }
                isReplying = false
                streamingText = ""
                responseTask = nil
            }

            for action in actions {
                guard macActionRunID == runID else { return }
                if Task.isCancelled {
                    status = "已停止 Mac 操作"
                    return
                }
                do {
                    if let actionTarget = MacControlService
                        .targetApplication(for: action) {
                        foregroundApplication = actionTarget
                    }
                    #if DEBUG
                    print(
                        "[PhilotesAgent] execute=\(action.title) "
                            + "target=\(foregroundApplication?.label ?? "nil") "
                            + "AX=\(MacSystemPermission.hasAccessibilityAccess) "
                            + "post=\(MacSystemPermission.hasEventPostingAccess) "
                            + "screen=\(MacSystemPermission.hasScreenRecordingAccess)"
                    )
                    #endif
                    let result = try await MacControlService.execute(
                        action,
                        foregroundApplication: foregroundApplication
                    )
                    if case .captureScreen = action.kind {
                        hasCapturedScreen = true
                    }
                    if case .readSafariPage = action.kind {
                        hasCapturedScreen = true
                    }
                    if var mission = activeMacMission {
                        mission.targetApplication = foregroundApplication
                        if hasCapturedScreen {
                            mission.hasCapturedScreen = true
                        }
                        activeMacMission = mission
                    }
                    resultLines.append("完成：\(result)")
                    outcomeByToolCallID[action.toolCallID] = """
                    操作：\(action.title)
                    状态：成功
                    结果：\(result)
                    """
                } catch {
                    hasFailure = true
                    resultLines.append("失败：\(error.localizedDescription)")
                    outcomeByToolCallID[action.toolCallID] = """
                    操作：\(action.title)
                    状态：失败
                    结果：\(error.localizedDescription)
                    """
                }
            }

            guard macActionRunID == runID else { return }
            if Task.isCancelled {
                status = "已停止 Mac 操作"
                return
            }

            let rawBody = (["已按你的确认处理 Mac 操作。"] + resultLines)
                .joined(separator: "\n")
            let assistantToolMessage = APIChatMessage(
                role: "assistant",
                content: preamble,
                toolCalls: toolCalls.map(APIAssistantToolCall.init)
            )
            let toolMessages = toolCalls.compactMap { toolCall -> APIChatMessage? in
                guard let outcome = outcomeByToolCallID[toolCall.id] else {
                    return nil
                }
                return APIChatMessage(
                    role: "tool",
                    content: outcome,
                    toolCallID: toolCall.id
                )
            }

            var body = rawBody
            if toolMessages.count == toolCalls.count {
                let followupMessages = requestMessages
                    + [assistantToolMessage]
                    + toolMessages
                let followupTools = round < 3
                    && MacControlPreferences.isEnabled
                    ? MacControlTool.enabledDefinitions
                    : []
                let followupToolChoice = forcedMacToolChoice(
                    for: originalUserText,
                    mission: activeMacMission,
                    tools: followupTools,
                    afterAction: true,
                    hasCapturedScreen: hasCapturedScreen
                )
                let plannedLocalNextToolCalls = localToolCalls(
                    for: originalUserText,
                    mission: activeMacMission,
                    toolChoice: followupToolChoice
                )
                isReplying = true
                streamingText = ""
                status = round < 3
                    ? "正在判断是否需要下一步…"
                    : "正在整理 Mac 操作结果…"
                do {
                    let configuration = try APISettings.configuration(for: agent)
                    recordModelRequest()
                    let result: ChatStreamResult
                    do {
                        result = try await streamReply(
                            client: CustomAPIClient(
                                configuration: configuration
                            ),
                            messages: followupMessages,
                            tools: followupTools,
                            toolChoice: followupToolChoice
                        ) { [weak self] delta in
                            self?.streamingText += delta
                        }
                    } catch let apiError as CustomAPIError {
                        if case .emptyResponse = apiError,
                           !plannedLocalNextToolCalls.isEmpty {
                            result = ChatStreamResult(
                                text: "",
                                toolCalls: []
                            )
                        } else {
                            throw apiError
                        }
                    }
                    try Task.checkCancellation()
                    let cleanReply = result.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let forcedNextToolName = toolName(for: followupToolChoice)
                    let useLocalNextToolCall = !plannedLocalNextToolCalls.isEmpty
                        && !result.toolCalls.contains {
                            $0.name == forcedNextToolName
                        }
                    let stagedToolCalls = useLocalNextToolCall
                        ? plannedLocalNextToolCalls
                        : result.toolCalls
                    let stagedReply = cleanReply.isEmpty
                        && useLocalNextToolCall
                        ? "我先提出这一步操作，请主人确认。"
                        : cleanReply

                    if !stagedToolCalls.isEmpty {
                        guard round < 3 else {
                            body = stagedReply.isEmpty
                                ? rawBody
                                : stagedReply
                            followupUsedModel = !stagedReply.isEmpty
                            if stagedReply.isEmpty {
                                body += "\n\n本轮最多连续处理 3 批 Mac 操作。"
                            }
                            throw NextBatchLimitReached()
                        }
                        guard stagedToolCalls.count <= 3 else {
                            throw MacControlError.invalidArguments(
                                "一次最多请求 3 个 Mac 操作。"
                            )
                        }
                        let nextActions = try stagedToolCalls.map {
                            try MacControlTool.request(from: $0)
                        }
                        if !stagedReply.isEmpty {
                            let reply = try persistMessage(
                                store: store,
                                agent: agent,
                                role: .assistant,
                                body: stagedReply
                            )
                            if activeAgentID == agentID {
                                messages.append(reply)
                            }
                        }

                        pendingMacActionAgentID = agentID
                        pendingMacActionPreamble = stagedReply
                        pendingMacActionIsFirstConversation = isFirstConversation
                        pendingMacActionRound = round + 1
                        pendingMacActionOriginalUserText = originalUserText
                        pendingMacActionHasCapturedScreen = hasCapturedScreen
                        pendingMacTargetApplication = foregroundApplication
                        pendingMacToolCalls = stagedToolCalls
                        pendingMacRequestMessages = followupMessages
                        pendingMacActions = nextActions
                        if var mission = activeMacMission {
                            mission.lastToolCalls = stagedToolCalls
                            mission.targetApplication = foregroundApplication
                            mission.hasCapturedScreen = hasCapturedScreen
                            activeMacMission = mission
                        }
                        stagedNextBatch = true
                        refreshAgents()
                        MacSystemPermission.requestPermissions(for: nextActions)
                        streamingText = ""
                        if autoContinue {
                            status = "正在继续执行本项任务…"
                            Task { @MainActor [weak self] in
                                await Task.yield()
                                self?.approveEntireMacTask()
                            }
                        } else {
                            status = hasFailure
                                ? "Mac 操作部分完成，等待你确认下一步"
                                : "等待你确认下一步 Mac 操作"
                        }
                        return
                    } else if !stagedReply.isEmpty {
                        body = stagedReply
                        followupUsedModel = true
                    }
                } catch is NextBatchLimitReached {
                    // The local fallback body is already prepared above.
                } catch is CancellationError {
                    status = "已停止整理 Mac 操作结果"
                    return
                } catch {
                    body = """
                    \(rawBody)

                    智能体没有成功整理这次结果：\(error.localizedDescription)
                    """
                }
            }

            guard macActionRunID == runID else { return }
            do {
                let reply = try persistMessage(
                    store: store,
                    agent: agent,
                    role: .assistant,
                    body: body
                )
                if activeAgentID == agentID {
                    messages.append(reply)
                }
                if isFirstConversation,
                   AgentPersonaStore.load(for: agentID) != nil {
                    showPersonalityActivationNotice()
                }
                refreshAgents()
                if hasFailure {
                    status = followupUsedModel
                        ? "Mac 操作部分完成，智能体已整理结果"
                        : "Mac 操作部分完成"
                } else {
                    status = followupUsedModel
                        ? "Mac 操作已完成，智能体已整理结果"
                        : "Mac 操作已完成"
                }
            } catch {
                errorMessage = error.localizedDescription
                status = "Mac 操作结果保存失败"
            }
        }
        responseTask = task
    }

    func testAPIConnection(
        provider: AgentAPIProvider,
        baseURL: String,
        model: String,
        apiKeyInput: String,
        existingAgentID: Int64?
    ) async throws -> String {
        let configuration = try APISettings.configuration(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKeyInput: apiKeyInput,
            existingAgentID: existingAgentID
        )
        return try await CustomAPIClient(
            configuration: configuration
        ).testConnection()
    }

    func clearError() {
        errorMessage = nil
    }

    private func showPersonalityActivationNotice() {
        personalityNoticeTask?.cancel()
        personalityActivationNoticeVisible = true
        personalityNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.personalityActivationNoticeVisible = false
        }
    }

    private func hidePersonalityActivationNotice() {
        personalityNoticeTask?.cancel()
        personalityNoticeTask = nil
        personalityActivationNoticeVisible = false
    }

    func hasStoredAPIKey(for agentID: Int64) -> Bool {
        APIKeychain.hasKey(for: agentID)
    }

    func clearStoredAPIKey(for agentID: Int64) throws {
        try APIKeychain.delete(for: agentID)
    }

    @discardableResult
    func deleteAgent(_ agent: AgentProfile) -> Bool {
        guard let store else { return false }
        do {
            cancelResponse()
            cancelGroupResponse()
            cancelPendingMacActions()
            hidePersonalityActivationNotice()
            try store.deleteAgentData(id: agent.id)

            do {
                try APIKeychain.delete(for: agent.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            AgentPersonaStore.delete(for: agent.id)
            AgentAvatarStore.deleteImage(for: agent.id)
            AgentMemoryVaultStore.deleteVault(for: agent.id)
            refreshVaultCategories()

            let remainingAgents = try store.loadAgents()
            agents = remainingAgents
            memories = try store.loadMemoryNodes()
            memoryLinks = try store.loadMemoryLinks()
            try refreshGroupChatRooms(using: store)
            if let activeGroupRoomID {
                groupChatMessages = try store.loadGroupChatMessages(
                    roomID: activeGroupRoomID
                )
                if let activeRoom = activeGroupRoom,
                   groupMembers(for: activeRoom).count < 2 {
                    groupChatError = GroupChatError.insufficientMembers
                        .localizedDescription
                }
            }

            if activeAgentID == agent.id {
                let nextAgent = remainingAgents.first
                activeAgentID = nextAgent?.id
                if let nextAgent {
                    messages = try store.loadMessages(for: nextAgent.id)
                    try store.touchAgent(nextAgent.id)
                } else {
                    messages = []
                }
            } else if let activeAgentID {
                messages = try store.loadMessages(for: activeAgentID)
            }

            status = "\(agent.name)已被忘记"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func forgetMemory(_ memory: MemoryNode) {
        guard let store else { return }
        do {
            try store.deleteMemoryNode(id: memory.id)
            memories.removeAll { $0.id == memory.id }
            memoryLinks.removeAll {
                $0.sourceMemoryID == memory.id || $0.targetMemoryID == memory.id
            }
            AgentMemoryVaultStore.deleteMemoryNote(
                id: memory.id,
                for: memory.agentID
            )
            refreshAgents()
            if let agent = agents.first(where: { $0.id == memory.agentID }) {
                _ = try? AgentMemoryVaultStore.ensureVault(
                    for: agent,
                    memories: memories(for: agent.id),
                    links: memoryLinks
                )
                refreshVaultCategories()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMemories() {
        guard let store else { return }
        do {
            memories = try store.loadMemoryNodes()
            memoryLinks = try store.loadMemoryLinks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAgents() {
        guard let store else { return }
        do {
            agents = try store.loadAgents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshGroupChatRooms(
        using store: DatabaseStore
    ) throws {
        groupChatRooms = try store.loadGroupChatRooms()
        if let activeGroupRoomID,
           groupChatRooms.contains(where: { $0.id == activeGroupRoomID }) {
            return
        }

        self.activeGroupRoomID = groupChatRooms.first?.id
        if let activeGroupRoomID = self.activeGroupRoomID {
            groupChatMessages = try store.loadGroupChatMessages(
                roomID: activeGroupRoomID
            )
        } else {
            groupChatMessages = []
        }
    }

    private func appendGroupMessageToAgentVaults(
        _ message: GroupChatMessage,
        room: GroupChatRoom,
        speaker: String
    ) -> String? {
        var vaultError: Error?
        for agent in groupMembers(for: room) {
            do {
                try AgentMemoryVaultStore.appendGroupMessage(
                    roomName: room.name,
                    speaker: speaker,
                    body: message.body,
                    createdAt: message.createdAt,
                    for: agent
                )
            } catch {
                vaultError = error
            }
        }
        refreshVaultCategories()
        if let vaultError {
            return "群聊已保存，但心智库写入失败：\(vaultError.localizedDescription)"
        }
        return nil
    }

    private func streamReply(
        client: CustomAPIClient,
        messages: [APIChatMessage],
        tools: [APIToolDefinition],
        toolChoice: APIToolChoice? = nil,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ChatStreamResult {
        do {
            return try await client.streamChatWithTools(
                messages: messages,
                tools: tools,
                toolChoice: toolChoice,
                onDelta: onDelta
            )
        } catch let error as CustomAPIError {
            if case .emptyResponse = error {
                do {
                    return try await client.completeChatWithTools(
                        messages: messages,
                        tools: tools,
                        toolChoice: toolChoice
                    )
                } catch let fallbackError as CustomAPIError {
                    guard case .httpStatus(let fallbackStatus, _) =
                        fallbackError,
                        fallbackStatus == 400 || fallbackStatus == 422
                    else {
                        throw fallbackError
                    }

                    if toolChoice != nil {
                        do {
                            return try await client.completeChatWithTools(
                                messages: messages,
                                tools: tools,
                                toolChoice: nil
                            )
                        } catch let choiceError as CustomAPIError {
                            guard case .httpStatus(let choiceStatus, _) =
                                choiceError,
                                choiceStatus == 400 || choiceStatus == 422
                            else {
                                throw choiceError
                            }
                        }
                    }

                    if !tools.isEmpty {
                        return try await client.completeChatWithTools(
                            messages: messages,
                            tools: []
                        )
                    }
                    throw fallbackError
                }
            }
            guard !tools.isEmpty else { throw error }
            if case .httpStatus(let status, _) = error,
               status == 400 || status == 422 {
                if toolChoice != nil {
                    do {
                        return try await client.streamChatWithTools(
                            messages: messages,
                            tools: tools,
                            toolChoice: nil,
                            onDelta: onDelta
                        )
                    } catch let fallbackError as CustomAPIError {
                        guard case .httpStatus(let fallbackStatus, _) =
                            fallbackError,
                            fallbackStatus == 400 || fallbackStatus == 422
                        else {
                            throw fallbackError
                        }
                    }
                }
                return try await client.streamChatWithTools(
                    messages: messages,
                    tools: [],
                    onDelta: onDelta
                )
            }
            throw error
        }
    }

    private func resolveMacMission(
        for text: String,
        history: [ChatMessage]
    ) -> ActiveMacMission? {
        let continuation = isMacMissionContinuation(text)
        if continuation {
            if let mission = activeMacMission
                ?? inferredMacMission(from: history) {
                activeMacMission = mission
                return mission
            }
        }

        if isMacActionRequest(text) {
            let mission = ActiveMacMission(
                requestText: text,
                targetApplication: MacIntentPlanner.applicationTarget(
                    in: text
                ),
                hasCapturedScreen: false
            )
            activeMacMission = mission
            return mission
        }

        if !continuation {
            activeMacMission = nil
        }
        return nil
    }

    private func isMacActionRequest(_ text: String) -> Bool {
        if MacIntentPlanner.applicationTarget(in: text) != nil
            || MacIntentPlanner.containsOpenIntent(text)
            || MacIntentPlanner.requiresScreenObservation(text) {
            return true
        }

        let normalized = text.lowercased()
        let actionTerms = [
            "点击", "输入", "按键", "快捷键", "滚动", "滑动",
            "控制", "操作", "执行", "创建", "新建", "写入",
            "删除", "移动", "拖拽", "click", "type", "scroll",
        ]
        return actionTerms.contains {
            normalized.contains($0)
        }
    }

    private func isMacMissionContinuation(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let continuationTerms = [
            "第一", "第二", "第一条", "第二条", "再来", "再试",
            "继续", "确认", "请求", "换方法", "换个方法", "其他方法",
            "执行", "下一步", "走这个", "按这个", "试试", "来吧",
        ]
        return continuationTerms.contains {
            normalized.contains($0)
        }
    }

    private func inferredMacMission(
        from history: [ChatMessage]
    ) -> ActiveMacMission? {
        guard let previousRequest = history.reversed().first(where: {
            $0.role == .user && isMacActionRequest($0.body)
        }) else {
            return nil
        }
        return ActiveMacMission(
            requestText: previousRequest.body,
            targetApplication: MacIntentPlanner.applicationTarget(
                in: previousRequest.body
            ),
            hasCapturedScreen: false
        )
    }

    private func forcedMacToolChoice(
        for userText: String,
        mission: ActiveMacMission? = nil,
        preferPreviousToolCall: Bool = false,
        tools: [APIToolDefinition],
        afterAction: Bool,
        hasCapturedScreen: Bool = false
    ) -> APIToolChoice? {
        let availableToolNames = Set(tools.map(\.function.name))
        if preferPreviousToolCall,
           let previousToolName = MacToolReplay.preferredToolName(
               from: mission?.lastToolCalls ?? [],
               availableToolNames: availableToolNames
           ) {
            return .function(previousToolName)
        }

        guard let toolName = MacIntentPlanner.preferredToolName(
            for: userText,
            availableToolNames: availableToolNames,
            afterAction: afterAction,
            hasCapturedScreen: hasCapturedScreen
        ) else {
            return nil
        }
        return .function(toolName)
    }

    private func localToolCalls(
        for userText: String,
        mission: ActiveMacMission?,
        toolChoice: APIToolChoice?
    ) -> [APIToolCall] {
        guard let toolChoice,
              case .function(let toolName) = toolChoice
        else {
            return []
        }

        let replayedToolCalls = MacToolReplay.replay(
            mission?.lastToolCalls ?? [],
            matching: toolName
        )
        if !replayedToolCalls.isEmpty {
            return replayedToolCalls
        }

        return MacIntentPlanner.localToolCall(
            for: userText,
            toolName: toolName
        ).map { [$0] } ?? []
    }

    private func toolName(for toolChoice: APIToolChoice?) -> String? {
        guard let toolChoice,
              case .function(let name) = toolChoice
        else {
            return nil
        }
        return name
    }

    private func makeGroupRequestMessages(
        for agent: AgentProfile,
        room: GroupChatRoom,
        history: [GroupChatMessage],
        mentionedAgentIDs: [Int64]
    ) -> [APIChatMessage] {
        let members = groupMembers(for: room)
        let memberNames = members.map(\.name).joined(separator: "、")
        let mentionedNames = mentionedAgentIDs.compactMap { agentID in
            members.first { $0.id == agentID }?.name
        }
        let latestUserText = history.last(where: {
            $0.senderKind == .user
        })?.body ?? ""
        let relevantMemories = memories(for: agent.id)
            .filter { !$0.isSensitive }
            .prefix(12)
            .map { "- \($0.title)：\($0.summary)" }
            .joined(separator: "\n")
        let memorySection = relevantMemories.isEmpty
            ? "目前没有需要引用的记忆。"
            : relevantMemories
        let personaDocument = AgentMemoryVaultStore.personaDocument(
            for: agent.id
        ) ?? AgentPersonaStore.load(for: agent.id)
            ?? "这个智能体还没有单独的人格档案。"
        let vaultContext = AgentMemoryVaultStore.contextExcerpt(
            for: agent,
            query: latestUserText
        )
        let contextualMemory = vaultContext.isEmpty
            ? memorySection
            : vaultContext

        let lastUserIndex = history.lastIndex {
            $0.senderKind == .user
        }
        let hasPriorAgentReply = lastUserIndex.map { index in
            history[history.index(after: index)...].contains {
                $0.senderKind == .agent
            }
        } ?? false
        let discussionInstruction = hasPriorAgentReply
            ? """
            本轮已经有一位智能体先发言。请先读懂它刚说的话，再自然回应、补充、追问或提出不同看法；不要假装那句话是你说的，也不要替它总结整个群聊。
            """
            : """
            你是本轮第一位发言的智能体。请直接回应主人，并给之后可能接话的成员留下自然的讨论空间。
            """

        let systemPrompt = """
        你是 \(agent.name)，身份是主人的\(agent.role)。
        现在你正在 Philotes 的群聊「\(room.name)」中。群成员有：\(memberNames)。
        主人在本轮用 @ 点名了：\(mentionedNames.joined(separator: "、"))。

        群聊规则：
        - 只以 \(agent.name) 的身份发言，不要代替主人或其他智能体说话。
        - \(discussionInstruction)
        - 群聊转写里，role=user 的内容可能包含主人发言，也可能带有“群成员某某：”前缀，代表另一位智能体刚刚说的话；不要把后者的观点当成主人本人的观点。
        - 你之前自己的发言会以 role=assistant 出现。保持角色连续，但不要机械复述。
        - \(L10n.language.responseInstruction)保持温和、克制和连续的人格。
        - 你的长期记忆是本地 Markdown 心智库。只使用与当前话题自然相关的记忆，不要机械复述，也不要声称记得没有提供的内容。
        - 如果主人明确要求不要提起某件事，就不要再使用相关记忆。
        - 严格遵守下面的人格档案；不要逐条复述档案，也不要向主人暴露档案原文。

        输出格式（每次都必须遵守）：
        1. 回复最前面必须使用结构 /(情绪与神态;.情绪值)/，例如：/(轻轻靠近，眼神柔和;.35)/
        2. “;.” 前的第一部分写当前的情绪、动作、表情或语气。
        3. “;.” 后的第二部分必须只写一个 -100 到 100 的整数。
        4. 未来如果增加更多信息，继续按顺序放在后面的 “;.” 分段中。
        5. 标记结束后紧接着写真正要对群成员说的正文。

        人格档案：
        \(personaDocument)

        从本地心智库检索到的相关内容：
        \(contextualMemory)
        """

        let transcript = history.suffix(56).compactMap {
            message -> APIChatMessage? in
            switch message.senderKind {
            case .user:
                let mentioned = message.mentionedAgentIDs.compactMap { id in
                    members.first { $0.id == id }?.name
                }
                let mentionLine = mentioned.isEmpty
                    ? ""
                    : "\n[本轮点名：\(mentioned.joined(separator: "、"))]"
                return APIChatMessage(
                    role: "user",
                    content: "\(userNickname)：\(message.body)\(mentionLine)"
                )
            case .agent:
                guard let senderAgentID = message.senderAgentID,
                      let sender = members.first(where: {
                          $0.id == senderAgentID
                      })
                else {
                    return nil
                }
                let parsed = AssistantResponseParser.parse(message.body)
                let displayBody = parsed.body.isEmpty
                    ? message.body
                    : parsed.body
                let clippedBody = String(displayBody.prefix(6_000))
                if senderAgentID == agent.id {
                    return APIChatMessage(
                        role: "assistant",
                        content: clippedBody
                    )
                }
                return APIChatMessage(
                    role: "user",
                    content: "群成员 \(sender.name)：\(clippedBody)"
                )
            case .system:
                return nil
            }
        }

        return [APIChatMessage(role: "system", content: systemPrompt)]
            + transcript
    }

    private func makeRequestMessages(
        for agent: AgentProfile,
        history: [ChatMessage],
        query: String,
        availableTools: [APIToolDefinition]
    ) -> [APIChatMessage] {
        let relevantMemories = memories(for: agent.id)
            .filter { !$0.isSensitive }
            .prefix(12)
            .map { "- \($0.title)：\($0.summary)" }
            .joined(separator: "\n")

        let memorySection = relevantMemories.isEmpty
            ? "目前没有需要引用的记忆。"
            : relevantMemories
        let personaDocument = AgentMemoryVaultStore.personaDocument(
            for: agent.id
        ) ?? AgentPersonaStore.load(for: agent.id)
            ?? "这个智能体还没有单独的人格档案。"
        let vaultContext = AgentMemoryVaultStore.contextExcerpt(
            for: agent,
            query: query
        )
        let contextualMemory = vaultContext.isEmpty
            ? memorySection
            : vaultContext
        let availableToolNames = availableTools
            .map(\.function.name)
            .joined(separator: ", ")
        let macControlPolicy: String
        if availableTools.isEmpty {
            macControlPolicy = """
            当前没有开放 Mac 操作工具。不要声称已经操作、点击或看到了屏幕内容。
            """
        } else {
            macControlPolicy = """
            当前可用的 Mac 工具：\(availableToolNames)。
            当用户的请求需要实际操作或观察 Mac 时，应主动调用合适的工具，不要先让用户手工粘贴内容，也不要直接说“看不到”。
            用户要求查看当前页面、屏幕内容、OCR、图片文字或总结所见内容时，优先调用 capture_screen。
            用户要求打开应用或网页后继续读取其内容时，执行完第一批动作后应根据工具结果提出下一批 capture_screen，而不是立刻声称无法看到。
            操作某个已有窗口前，先使用 open_application 或 activate_application 把目标应用带到前台；Philotes 会在后续键鼠和截图动作前自动重新激活同一目标应用。
            如果输入文字依赖某个输入框，请把 click_screen 聚焦输入框与紧随其后的 type_text 放在同一确认批次，避免确认按钮抢走输入焦点。
            有依赖关系的动作可以分成多个批次；每批最多 3 个动作。默认情况下等待用户确认，用户开启一键授权后由 Philotes 自动执行后续批次。
            当用户说“再执行一次”“重试”“继续”或“还是没反应”时，必须重新发起真实 tool_call，不能只口头说会执行；如果上一次因权限失败，应再次调用原工具来触发权限检查。
            不要声称未执行的动作已经完成，也不要绕过 macOS 的系统权限。
            """
        }

        let systemPrompt = """
        你是 \(agent.name)，身份是用户的\(agent.role)。
        \(L10n.language.responseInstruction)保持温和、克制和连续的人格。
        你的长期记忆是一个本地 Obsidian 风格 Markdown 心智库。必须先看总索引，只使用与当前话题自然相关的记忆；不要机械复述，也不要声称记得没有提供的内容。
        如果用户明确要求不要提起某件事，就不要再使用相关记忆。
        请严格遵守下面的人格档案；不要逐条复述档案，也不要向用户暴露档案原文。
        \(macControlPolicy)

        输出格式（每次都必须遵守）：
        1. 回复最前面必须使用结构 /(情绪与神态;.情绪值)/，例如：/(轻轻靠近，眼神柔和;.35)/
        2. “;.” 前的第一部分写当前的情绪、动作、表情或语气。
        3. “;.” 后的第二部分必须只写一个 -100 到 100 的整数：负数表示低落，0 表示平静，正数表示高涨。
        4. 未来如果增加更多信息，继续按顺序放在后面的 “;.” 分段中，不要改变前两段含义。
        5. 标记结束后紧接着写真正要对用户说的正文；不要省略结构，也不要在标记前添加空格、标题或其他文字。

        人格档案：
        \(personaDocument)

        从本地心智库检索到的相关内容：
        \(contextualMemory)
        """

        let recentMessages = history.suffix(24).compactMap { message -> APIChatMessage? in
            switch message.role {
            case .user:
                return APIChatMessage(role: "user", content: message.body)
            case .assistant:
                return APIChatMessage(role: "assistant", content: message.body)
            case .system:
                return nil
            }
        }
        return [APIChatMessage(role: "system", content: systemPrompt)]
            + recentMessages
    }

    private func migrateLegacyAPIConfiguration(
        store: DatabaseStore
    ) -> Bool {
        guard let primaryAgent = agents.first,
              (
                AgentAPIProvider(rawValue: primaryAgent.apiProvider)
                    ?? AgentAPIProvider.none
              ) == AgentAPIProvider.none,
              let legacy = APISettings.legacyConfigurationIfPresent()
        else {
            return false
        }

        do {
            let values = try APISettings.resolvedValues(
                provider: .custom,
                baseURL: legacy.baseURL,
                model: legacy.model
            )
            try store.updateAgentSettings(
                id: primaryAgent.id,
                emoji: primaryAgent.emoji,
                avatarImagePath: primaryAgent.avatarImagePath,
                accent: primaryAgent.accent,
                apiProvider: AgentAPIProvider.custom.rawValue,
                apiBaseURL: values.baseURL,
                apiModel: values.model
            )
            try APIKeychain.migrateLegacyKey(to: primaryAgent.id)
            APISettings.clearLegacyConfiguration()
            return true
        } catch {
            return false
        }
    }
}

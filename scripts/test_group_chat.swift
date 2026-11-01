import AppKit
import Foundation

extension Notification.Name {
    static let philotesNewConversation = Notification.Name(
        "PhilotesNewConversationTest"
    )
}

@main
struct GroupChatSmokeTest {
    static func main() throws {
        try testMentionParser()
        try testRoomPersistence()
        print("PASS group chat mentions, room persistence, and shared diary memory")
    }

    private static func testMentionParser() throws {
        let link = makeAgent(id: 1, name: "Link")
        let linker = makeAgent(id: 2, name: "Linker")
        let sasa = makeAgent(id: 3, name: "sasa")
        let members = [link, linker, sasa]

        let ordered = GroupChatMentionParser.resolve(
            "@sasa 和 @Link，先聊这个",
            members: members
        )
        try expect(
            ordered.agents.map(\.id) == [sasa.id, link.id],
            "@ mention order mismatch"
        )
        try expect(
            ordered.unresolvedTokens.isEmpty,
            "known mentions should resolve"
        )

        let longestName = GroupChatMentionParser.resolve(
            "@Linker 和 @Link",
            members: members
        )
        try expect(
            longestName.agents.map(\.id) == [linker.id, link.id],
            "longest member name should win"
        )

        let prefixIsNotAMention = GroupChatMentionParser.resolve(
            "@Lin",
            members: members
        )
        try expect(
            prefixIsNotAMention.agents.isEmpty
                && prefixIsNotAMention.unresolvedTokens == ["Lin"],
            "partial name should remain unresolved"
        )

        let unknown = GroupChatMentionParser.resolve(
            "@Link @Mars",
            members: members
        )
        try expect(
            unknown.agents.map(\.id) == [link.id]
                && unknown.unresolvedTokens == ["Mars"],
            "unknown mention mismatch"
        )

        let duplicate = GroupChatMentionParser.resolve(
            "@Link @Link @sasa",
            members: members
        )
        try expect(
            duplicate.agents.map(\.id) == [link.id, sasa.id],
            "duplicate mention should only speak once"
        )
    }

    private static func testRoomPersistence() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "philotes-group-chat-\(UUID().uuidString).sqlite"
            )
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }

        let store = try DatabaseStore(databaseURL: databaseURL)
        let firstID = try store.createAgent(
            name: "Link",
            role: "生活搭档",
            emoji: "🐟",
            accent: "blue",
            apiProvider: AgentAPIProvider.none.rawValue,
            apiBaseURL: "",
            apiModel: ""
        )
        let secondID = try store.createAgent(
            name: "sasa",
            role: "创作搭档",
            emoji: "✍️",
            accent: "lavender",
            apiProvider: AgentAPIProvider.none.rawValue,
            apiBaseURL: "",
            apiModel: ""
        )
        let thirdID = try store.createAgent(
            name: "小蓝鲸",
            role: "行动搭档",
            emoji: "🐋",
            accent: "mint",
            apiProvider: AgentAPIProvider.none.rawValue,
            apiBaseURL: "",
            apiModel: ""
        )

        let roomID = try store.createGroupChatRoom(
            name: "夜航桌",
            agentIDs: [secondID, firstID, thirdID]
        )
        var rooms = try store.loadGroupChatRooms()
        let room = try unwrap(rooms.first { $0.id == roomID })
        try expect(room.name == "夜航桌", "room name mismatch")
        try expect(room.avatarEmoji == "💬", "default room avatar mismatch")
        try expect(room.avatarImagePath == nil, "room image should start empty")
        try expect(
            Set(room.agentIDs) == Set([firstID, secondID, thirdID]),
            "room member persistence mismatch"
        )

        let userMessage = try store.appendGroupChatMessage(
            roomID: roomID,
            senderKind: .user,
            senderAgentID: nil,
            body: "@sasa @Link 你们聊聊今晚看什么",
            mentionedAgentIDs: [secondID, firstID]
        )
        let firstReply = try store.appendGroupChatMessage(
            roomID: roomID,
            senderKind: .agent,
            senderAgentID: secondID,
            body: "/(认真想了片刻;.18)/先看一部安静的纪录片吧。",
            mentionedAgentIDs: []
        )
        let secondReply = try store.appendGroupChatMessage(
            roomID: roomID,
            senderKind: .agent,
            senderAgentID: firstID,
            body: "/(笑着接话;.24)/那我想接着补一部短片。",
            mentionedAgentIDs: []
        )

        let messages = try store.loadGroupChatMessages(roomID: roomID)
        try expect(
            messages.map(\.id) == [
                userMessage.id,
                firstReply.id,
                secondReply.id,
            ],
            "group message order mismatch"
        )
        try expect(
            messages[0].mentionedAgentIDs == [secondID, firstID],
            "mention order should be persisted"
        )
        try expect(
            messages[1].senderAgentID == secondID
                && messages[2].senderAgentID == firstID,
            "agent sender persistence mismatch"
        )

        rooms = try store.loadGroupChatRooms()
        try expect(
            rooms.first { $0.id == roomID }?.lastMessagePreview?
                .contains("短片") == true,
            "room preview should use the latest message"
        )

        try store.updateGroupChatRoomSettings(
            roomID: roomID,
            name: "夜航桌 · 夜班",
            avatarEmoji: "🌙",
            avatarImagePath: "/tmp/philotes-room-avatar.png",
            agentIDs: [firstID, secondID, thirdID]
        )
        rooms = try store.loadGroupChatRooms()
        let editedRoom = try unwrap(rooms.first { $0.id == roomID })
        try expect(
            editedRoom.name == "夜航桌 · 夜班",
            "room rename mismatch"
        )
        try expect(
            editedRoom.avatarEmoji == "🌙"
                && editedRoom.avatarImagePath
                    == "/tmp/philotes-room-avatar.png",
            "room avatar settings mismatch"
        )

        let agents = try store.loadAgents()
        let firstAgent = try unwrap(agents.first { $0.id == firstID })
        let memoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "philotes-group-vault-\(UUID().uuidString)"
            )
        defer {
            try? FileManager.default.removeItem(at: memoryRoot)
        }
        try AgentMemoryVaultStore.appendGroupMessage(
            roomName: room.name,
            speaker: "sasa",
            body: firstReply.body,
            createdAt: firstReply.createdAt,
            for: firstAgent,
            baseURL: memoryRoot
        )

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: firstReply.createdAt)
        let diaryURL = AgentMemoryVaultStore.vaultDirectoryURL(
            for: firstID,
            baseURL: memoryRoot
        )
        .appendingPathComponent("04-日记/\(day).md")
        let diary = try String(contentsOf: diaryURL, encoding: .utf8)
        try expect(
            diary.contains("群聊「夜航桌」 · sasa")
                && diary.contains("先看一部安静的纪录片吧"),
            "group message should enter shared agent diary"
        )

        try store.deleteAgentData(id: secondID)
        rooms = try store.loadGroupChatRooms()
        let updatedRoom = try unwrap(rooms.first { $0.id == roomID })
        try expect(
            updatedRoom.agentIDs == [firstID, thirdID].sorted(),
            "deleted agent should leave the room"
        )

        try store.updateGroupChatRoomSettings(
            roomID: roomID,
            name: editedRoom.name,
            avatarEmoji: editedRoom.avatarEmoji,
            avatarImagePath: editedRoom.avatarImagePath,
            agentIDs: [firstID]
        )
        rooms = try store.loadGroupChatRooms()
        try expect(
            rooms.first { $0.id == roomID }?.agentIDs == [firstID],
            "single member should remain after kicking from settings"
        )

        try store.deleteGroupChatRoom(roomID: roomID)
        let roomsAfterDeletion = try store.loadGroupChatRooms()
        let messagesAfterDeletion = try store.loadGroupChatMessages(
            roomID: roomID
        )
        try expect(
            roomsAfterDeletion.isEmpty,
            "deleted room should disappear"
        )
        try expect(
            messagesAfterDeletion.isEmpty,
            "deleted room messages should cascade"
        )
    }

    private static func makeAgent(
        id: Int64,
        name: String
    ) -> AgentProfile {
        AgentProfile(
            id: id,
            name: name,
            role: "测试",
            emoji: "✨",
            avatarImagePath: nil,
            accent: "blue",
            createdAt: Date(),
            lastActiveAt: Date(),
            apiProvider: AgentAPIProvider.none.rawValue,
            apiBaseURL: "",
            apiModel: "",
            memoryCount: 0
        )
    }
}

private struct GroupChatTestFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw GroupChatTestFailure(message: message)
    }
}

private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else {
        throw GroupChatTestFailure(message: "unexpected nil")
    }
    return value
}

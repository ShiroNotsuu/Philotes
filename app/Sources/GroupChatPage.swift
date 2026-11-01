import AppKit
import SwiftUI

struct GroupChatPage: View {
    @ObservedObject var model: AppModel
    @State private var isShowingCreator = false
    @State private var editingRoom: GroupChatRoom?
    @State private var roomPendingDeletion: GroupChatRoom?
    @State private var draft = ""
    @State private var scrollRestoreTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    private var activeRoom: GroupChatRoom? {
        model.activeGroupRoom
    }

    private var activeMembers: [AgentProfile] {
        guard let activeRoom else { return [] }
        return model.groupMembers(for: activeRoom)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "GROUP CHAT",
                title: "群聊",
                subtitle: "把智能体放进同一个房间。@ 谁，谁就开口。"
            ) {
                Button {
                    isShowingCreator = true
                } label: {
                    Label("创建群聊", systemImage: "plus")
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            PhilotesTheme.primaryText,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(model.agents.count < 2)
                .help(
                    model.agents.count < 2
                        ? "至少需要两位智能体才能建群"
                        : "创建群聊"
                )
            }

            Divider()
                .overlay(PhilotesTheme.border)

            if model.groupChatRooms.isEmpty {
                emptyGroups
            } else {
                HStack(spacing: 0) {
                    roomRail
                        .frame(width: 244)

                    Rectangle()
                        .fill(PhilotesTheme.border)
                        .frame(width: 1)

                    groupWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(PhilotesTheme.canvas)
        .sheet(isPresented: $isShowingCreator) {
            CreateGroupChatSheet(
                model: model,
                isPresented: $isShowingCreator
            )
        }
        .sheet(item: $editingRoom) { room in
            GroupChatSettingsSheet(
                room: room,
                model: model,
                onClose: {
                    editingRoom = nil
                }
            )
        }
        .alert(
            "删除「\(roomPendingDeletion?.name ?? "群聊")」？",
            isPresented: Binding(
                get: { roomPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        roomPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("取消", role: .cancel) {
                roomPendingDeletion = nil
            }
            Button("删除聊天室", role: .destructive) {
                guard let room = roomPendingDeletion else { return }
                _ = model.deleteGroupRoom(room)
                roomPendingDeletion = nil
            }
        } message: {
            Text("聊天室里的全部消息会一起删除，且无法撤销。")
        }
        .onAppear {
            if model.activeGroupRoomID == nil,
               let firstRoom = model.groupChatRooms.first {
                model.setActiveGroupRoom(firstRoom)
            }
            composerFocused = true
        }
        .onChange(of: model.activeGroupRoomID) {
            draft = ""
            model.clearGroupChatError()
            composerFocused = true
        }
        .onDisappear {
            scrollRestoreTask?.cancel()
            scrollRestoreTask = nil
        }
    }

    private var roomRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("房间")
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(PhilotesTheme.tertiaryText)

                Spacer()

                Button {
                    isShowingCreator = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(model.agents.count < 2)
                .help("创建群聊")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(model.groupChatRooms) { room in
                        GroupRoomRow(
                            room: room,
                            members: model.groupMembers(for: room),
                            isSelected: model.activeGroupRoomID == room.id
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                model.setActiveGroupRoom(room)
                            }
                        } onDelete: {
                            roomPendingDeletion = room
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Image(systemName: "at")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PhilotesTheme.blue)
                Text("每轮 @ 一位或两位成员")
                    .font(
                        .system(
                            size: 8,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PhilotesTheme.border)
                    .frame(height: 1)
            }
        }
        .background(PhilotesTheme.sidebar.opacity(0.48))
    }

    @ViewBuilder
    private var groupWorkspace: some View {
        if let room = activeRoom {
            VStack(spacing: 0) {
                conversationHeader(room)

                Divider()
                    .overlay(PhilotesTheme.border)

                conversation
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                Text("选择或创建一个群聊")
                    .font(
                        .system(
                            size: 13,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversationHeader(_ room: GroupChatRoom) -> some View {
        HStack(spacing: 12) {
            GroupChatRoomAvatar(
                room: room,
                members: activeMembers,
                size: 38
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.primaryText)

                HStack(spacing: 6) {
                    ForEach(activeMembers) { agent in
                        HStack(spacing: 4) {
                            AgentGlyph(
                                emoji: agent.emoji,
                                size: 7,
                                imagePath: agent.avatarImagePath
                            )
                            Text(agent.name)
                                .lineLimit(1)
                        }
                        .font(
                            .system(
                                size: 8,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            agent.accentColor.opacity(0.09),
                            in: Capsule()
                        )
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                StatusDot(
                    color: activeMembers.count >= 2
                        ? PhilotesTheme.mint
                        : PhilotesTheme.coral
                )
                Text(
                    activeMembers.count >= 2
                        ? "\(activeMembers.count) 位成员"
                        : "需要至少两位成员"
                )
            }
            .font(
                .system(
                    size: 9,
                    weight: .medium,
                    design: .rounded
                )
            )
            .foregroundStyle(PhilotesTheme.tertiaryText)

            Button {
                editingRoom = room
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        PhilotesTheme.surface,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(PhilotesTheme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.philotesInteractive)
            .help("聊天室设置")
            .accessibilityLabel("聊天室设置")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    groupOpening

                    ForEach(model.groupChatMessages) { message in
                        GroupMessageRow(
                            message: message,
                            members: model.agents,
                            userAvatarPath: model.userAvatarPath
                        )
                        .id(message.id)
                    }

                    if model.isGroupReplying {
                        streamingMessage
                            .id("groupStreaming")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("groupBottom")
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                restoreBottom(using: proxy, animated: false)
            }
            .onChange(of: model.activeGroupRoomID) {
                restoreBottom(using: proxy, animated: false)
            }
            .onChange(of: model.groupChatMessages.count) {
                guard model.groupChatMessages.last != nil else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("groupBottom", anchor: .bottom)
                }
            }
            .onChange(of: model.groupStreamingText) {
                guard model.isGroupReplying else { return }
                proxy.scrollTo("groupStreaming", anchor: .bottom)
            }
            .onChange(of: model.isGroupReplying) {
                guard model.isGroupReplying else { return }
                withAnimation(.easeOut(duration: 0.20)) {
                    proxy.scrollTo("groupStreaming", anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
        }
    }

    private var groupOpening: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "同一张桌子")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.lavender)
                    .padding(.top, 2)

                Text(
                    "点名一位智能体，就听它回答；点名两位，就让后一位接着前一位说下去。"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.tertiaryText)
                .lineSpacing(3)
            }
        }
        .padding(.bottom, 2)
    }

    private var streamingMessage: some View {
        let agent = activeMembers.first {
            $0.id == model.groupStreamingAgentID
        }
        let parsed = AssistantResponseParser.parse(
            model.groupStreamingText
        )

        return HStack(alignment: .top, spacing: 11) {
            GroupAgentAvatar(agent: agent)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(
                        agent?.name ?? L10n.string("智能体")
                    )
                        .foregroundStyle(PhilotesTheme.secondaryText)
                    Text("正在说话")
                        .foregroundStyle(PhilotesTheme.blue)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(PhilotesTheme.blue.opacity(0.65))
                                .frame(width: 3, height: 3)
                                .opacity(0.45 + Double(index) * 0.2)
                        }
                    }
                }
                .font(
                    .system(
                        size: 9,
                        weight: .medium,
                        design: .rounded
                    )
                )

                if let action = parsed.action, !action.isEmpty {
                    AssistantActionPrompt(text: action, compact: true)
                }

                if parsed.body.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(PhilotesTheme.secondaryText)
                                .frame(width: 4, height: 4)
                                .opacity(0.45 + Double(index) * 0.18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        PhilotesTheme.surface,
                        in: Capsule()
                    )
                } else {
                    Text(parsed.body + "▍")
                        .font(
                            .system(
                                size: 13,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .lineSpacing(4)
                        .foregroundStyle(
                            PhilotesTheme.primaryText.opacity(0.82)
                        )
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            PhilotesTheme.surface,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .stroke(PhilotesTheme.border, lineWidth: 1)
                        }
                }
            }

            Spacer(minLength: 96)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !mentionSuggestions.isEmpty {
                mentionSuggestionBar
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    activeMembers.count >= 2
                        ? "说点什么，用 @ 叫一位或两位成员…"
                        : "这个群聊需要至少两位智能体",
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(
                    .system(
                        size: 13,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.primaryText)
                .lineLimit(1...6)
                .focused($composerFocused)
                .onSubmit(sendDraft)
                .disabled(activeMembers.count < 2)

                Button(action: composerAction) {
                    Image(
                        systemName: model.isGroupReplying
                            ? "stop.fill"
                            : "arrow.up"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        model.isGroupReplying || canSend
                            ? .black
                            : PhilotesTheme.tertiaryText
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        model.isGroupReplying
                            ? PhilotesTheme.coral
                            : canSend
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.surfaceRaised,
                        in: Circle()
                    )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(!canSend && !model.isGroupReplying)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(
                    model.isGroupReplying ? "停止群聊回复" : "发送群聊消息"
                )
            }
            .padding(.leading, 15)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(
                PhilotesTheme.surface,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(
                        model.groupChatError == nil
                            ? PhilotesTheme.borderStrong
                            : PhilotesTheme.coral.opacity(0.45),
                        lineWidth: 1
                    )
            }

            HStack(spacing: 8) {
                if let error = model.groupChatError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(PhilotesTheme.coral)
                    Text(error)
                        .lineLimit(2)
                        .foregroundStyle(PhilotesTheme.coral)
                } else {
                    Label(
                        "群聊按顺序发言",
                        systemImage: "person.2.wave.2"
                    )
                    Text("·")
                    Text("后发言者会读到前一位的回复")
                }

                Spacer()

                Text("⌘↩ 发送")
            }
            .font(
                .system(
                    size: 8,
                    weight: .regular,
                    design: .rounded
                )
            )
            .foregroundStyle(PhilotesTheme.tertiaryText)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 28)
        .padding(.top, 11)
        .padding(.bottom, 17)
        .frame(maxWidth: 820)
        .background(PhilotesTheme.canvas.opacity(0.98))
        .animation(.easeOut(duration: 0.16), value: mentionSuggestions)
    }

    private var mentionSuggestionBar: some View {
        HStack(spacing: 6) {
            Text("叫谁来")
                .font(
                    .system(
                        size: 8,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.tertiaryText)
                .padding(.leading, 3)

            ForEach(mentionSuggestions.prefix(4)) { agent in
                Button {
                    insertMention(agent)
                } label: {
                    HStack(spacing: 5) {
                        AgentGlyph(
                            emoji: agent.emoji,
                            size: 7,
                            imagePath: agent.avatarImagePath
                        )
                        Text("@\(agent.name)")
                    }
                    .font(
                        .system(
                            size: 9,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        agent.accentColor.opacity(0.09),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                agent.accentColor.opacity(0.18),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.philotesInteractive)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var mentionQuery: String? {
        guard let atIndex = draft.lastIndex(of: "@") else {
            return nil
        }
        let suffix = draft[draft.index(after: atIndex)...]
        guard !suffix.contains(where: {
            $0.isWhitespace || $0.isNewline
        }) else {
            return nil
        }
        return String(suffix)
    }

    private var mentionSuggestions: [AgentProfile] {
        guard let query = mentionQuery else { return [] }
        if query.isEmpty {
            return activeMembers
        }
        return activeMembers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var canSend: Bool {
        activeMembers.count >= 2
            && !draft.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !model.isGroupReplying
            && model.pendingMacActions.isEmpty
            && !model.isExecutingMacActions
    }

    private func insertMention(_ agent: AgentProfile) {
        if let atIndex = draft.lastIndex(of: "@") {
            draft.replaceSubrange(
                atIndex..<draft.endIndex,
                with: "@\(agent.name) "
            )
        } else {
            if !draft.isEmpty, draft.last?.isWhitespace != true {
                draft += " "
            }
            draft += "@\(agent.name) "
        }
        composerFocused = true
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = draft
        guard model.sendGroupMessage(text) else {
            composerFocused = true
            return
        }
        draft = ""
        composerFocused = true
    }

    private func composerAction() {
        if model.isGroupReplying {
            model.cancelGroupResponse()
        } else {
            sendDraft()
        }
    }

    private func restoreBottom(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        scrollRestoreTask?.cancel()
        scrollRestoreTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.20)) {
                    proxy.scrollTo("groupBottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("groupBottom", anchor: .bottom)
            }

            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            proxy.scrollTo("groupBottom", anchor: .bottom)
        }
    }

    private var emptyGroups: some View {
        VStack(spacing: 17) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PhilotesTheme.blue.opacity(0.18),
                                PhilotesTheme.lavender.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 74, height: 74)

                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(PhilotesTheme.blue)
            }

            VStack(spacing: 6) {
                Text("还没有群聊")
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text("选两位智能体坐在一起，之后的每一句话都会留进它们共同的心智记忆。")
                    .font(
                        .system(
                            size: 10,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button {
                isShowingCreator = true
            } label: {
                Label("创建第一个群聊", systemImage: "plus")
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        PhilotesTheme.primaryText,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
            }
            .buttonStyle(.philotesInteractive)
            .disabled(model.agents.count < 2)

            if model.agents.count < 2 {
                Text(
                    L10n.format(
                        "还需要至少 %lld 位智能体",
                        Int64(2 - model.agents.count)
                    )
                )
                    .font(
                        .system(
                            size: 9,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.coral)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GroupRoomRow: View {
    let room: GroupChatRoom
    let members: [AgentProfile]
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    GroupChatRoomAvatar(
                        room: room,
                        members: members,
                        size: 25
                    )

                    Text(room.name)
                        .font(
                            .system(
                                size: 11,
                                weight: isSelected ? .semibold : .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(members.count)")
                        .font(
                            .system(
                                size: 8,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Text(roomPreview)
                    .font(
                        .system(
                            size: 8,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? PhilotesTheme.surfaceRaised
                    : isHovering
                        ? PhilotesTheme.surface.opacity(0.68)
                        : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(PhilotesTheme.borderStrong, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.philotesInteractive)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除聊天室", systemImage: "trash")
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var roomPreview: String {
        guard let preview = room.lastMessagePreview else {
            return "还没有消息"
        }
        let parsed = AssistantResponseParser.parse(preview)
        return parsed.body.isEmpty ? preview : parsed.body
    }
}

private struct GroupMessageRow: View {
    let message: GroupChatMessage
    let members: [AgentProfile]
    let userAvatarPath: String?

    private var sender: AgentProfile? {
        guard let senderAgentID = message.senderAgentID else {
            return nil
        }
        return members.first { $0.id == senderAgentID }
    }

    private var mentionedMembers: [AgentProfile] {
        message.mentionedAgentIDs.compactMap { id in
            members.first { $0.id == id }
        }
    }

    var body: some View {
        switch message.senderKind {
        case .system:
            systemMessage
        case .user:
            userMessage
        case .agent:
            agentMessage
        }
    }

    private var systemMessage: some View {
        Text(message.body)
            .font(
                .system(
                    size: 9,
                    weight: .regular,
                    design: .rounded
                )
            )
            .foregroundStyle(PhilotesTheme.tertiaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                PhilotesTheme.surface.opacity(0.72),
                in: Capsule()
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var userMessage: some View {
        HStack(alignment: .top, spacing: 11) {
            Spacer(minLength: 96)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 7) {
                    Text(message.createdAt.philotesTime)
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                    if !mentionedMembers.isEmpty {
                        Text(
                            mentionedMembers.map { "@\($0.name)" }
                                .joined(separator: " ")
                        )
                        .foregroundStyle(PhilotesTheme.blue)
                    }
                    Text("主人")
                        .foregroundStyle(PhilotesTheme.secondaryText)
                }
                .font(
                    .system(
                        size: 9,
                        weight: .medium,
                        design: .rounded
                    )
                )

                Text(message.body)
                    .font(
                        .system(
                            size: 13,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .foregroundStyle(PhilotesTheme.primaryText)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        PhilotesTheme.blue.opacity(0.16),
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                        .stroke(
                            PhilotesTheme.blue.opacity(0.16),
                            lineWidth: 1
                        )
                    }
            }

            UserAvatarView(imagePath: userAvatarPath, size: 28)
                .padding(.top, 17)
        }
    }

    private var agentMessage: some View {
        let parsed = AssistantResponseParser.parse(message.body)
        let agent = sender

        return HStack(alignment: .top, spacing: 11) {
            GroupAgentAvatar(agent: agent)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(
                        agent?.name
                            ?? L10n.string("已离开的智能体")
                    )
                        .foregroundStyle(PhilotesTheme.secondaryText)
                    if let role = agent?.role, !role.isEmpty {
                        Text(role)
                            .foregroundStyle(
                                agent?.accentColor.opacity(0.72)
                                    ?? PhilotesTheme.tertiaryText
                            )
                    }
                    Text(message.createdAt.philotesTime)
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                .font(
                    .system(
                        size: 9,
                        weight: .medium,
                        design: .rounded
                    )
                )

                if let action = parsed.action, !action.isEmpty {
                    AssistantActionPrompt(text: action)
                }

                if !parsed.body.isEmpty {
                    Text(parsed.body)
                        .font(
                            .system(
                                size: 13,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(
                            PhilotesTheme.primaryText.opacity(0.82)
                        )
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            PhilotesTheme.surface,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .stroke(PhilotesTheme.border, lineWidth: 1)
                        }
                }
            }

            Spacer(minLength: 96)
        }
    }
}

private struct GroupAgentAvatar: View {
    let agent: AgentProfile?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    (agent?.accentColor ?? PhilotesTheme.blue)
                        .opacity(0.13)
                )
                .frame(width: 30, height: 30)

            AgentGlyph(
                emoji: agent?.emoji ?? "·",
                size: 13,
                imagePath: agent?.avatarImagePath
            )
        }
        .padding(.top, 17)
    }
}

private struct GroupChatRoomAvatar: View {
    let room: GroupChatRoom
    let members: [AgentProfile]
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.30,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        PhilotesTheme.blue.opacity(0.22),
                        PhilotesTheme.lavender.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)

            if let imagePath = room.avatarImagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: size * 0.30,
                            style: .continuous
                        )
                    )
            } else {
                Text(roomAvatarEmoji)
                    .font(.system(size: size * 0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: size * 0.30,
                style: .continuous
            )
            .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityLabel("聊天室头像")
    }

    private var roomAvatarEmoji: String {
        if !room.avatarEmoji.isEmpty {
            return room.avatarEmoji
        }
        return members.first?.emoji ?? "💬"
    }
}

private struct GroupChatSettingsSheet: View {
    let room: GroupChatRoom
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    @State private var name: String
    @State private var selectedEmoji: String
    @State private var avatarImage: NSImage?
    @State private var avatarSourceURL: URL?
    @State private var removeAvatarImage: Bool
    @State private var selectedAgentIDs: Set<Int64>
    @State private var actionErrorMessage = ""
    @State private var isConfirmingDelete = false

    private let emojis = [
        "💬", "👥", "🌙", "🐟", "✨", "🌿", "🎧", "📚",
        "🪐", "🫧", "🔥", "🍵", "🦊", "🧭", "💫", "🎨",
    ]

    init(
        room: GroupChatRoom,
        model: AppModel,
        onClose: @escaping () -> Void
    ) {
        self.room = room
        self.model = model
        self.onClose = onClose
        _name = State(initialValue: room.name)
        _selectedEmoji = State(initialValue: room.avatarEmoji)
        _avatarImage = State(
            initialValue: room.avatarImagePath.flatMap {
                NSImage(contentsOfFile: $0)
            }
        )
        _avatarSourceURL = State(initialValue: nil)
        _removeAvatarImage = State(initialValue: false)
        _selectedAgentIDs = State(
            initialValue: Set(room.agentIDs)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AvatarPreview(
                    image: avatarImage,
                    emoji: selectedEmoji,
                    color: PhilotesTheme.blue,
                    size: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("聊天室设置")
                        .font(
                            .system(
                                size: 22,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(
                        L10n.format(
                            "%lld 位成员 · 共同记忆",
                            Int64(selectedAgentIDs.count)
                        )
                    )
                        .font(
                            .system(
                                size: 10,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: Circle()
                        )
                }
                .buttonStyle(.philotesInteractive)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 24)
            .padding(.top, 23)
            .padding(.bottom, 18)

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    avatarSection
                    roomNameSection
                    membersSection

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("删除聊天室")
                                    .font(
                                        .system(
                                            size: 10,
                                            weight: .semibold,
                                            design: .rounded
                                        )
                                    )
                                Text("同时删除房间里的全部消息")
                                    .font(
                                        .system(
                                            size: 8,
                                            weight: .regular,
                                            design: .rounded
                                        )
                                    )
                                    .foregroundStyle(
                                        PhilotesTheme.coral.opacity(0.68)
                                    )
                            }
                            Spacer()
                        }
                        .foregroundStyle(PhilotesTheme.coral)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(
                            PhilotesTheme.coral.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    PhilotesTheme.coral.opacity(0.20),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.philotesInteractive)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            Divider()
                .overlay(PhilotesTheme.border)

            HStack {
                if !actionErrorMessage.isEmpty {
                    Text(L10n.string(actionErrorMessage))
                        .font(
                            .system(
                                size: 9,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.coral)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        Image(
                            systemName: selectedAgentIDs.count >= 1
                                ? "checkmark.circle.fill"
                                : "exclamationmark.circle.fill"
                        )
                        Text(
                            selectedAgentIDs.count >= 1
                                ? "至少保留一位智能体"
                                : "聊天室不能没有成员"
                        )
                    }
                    .font(
                        .system(
                            size: 8,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        selectedAgentIDs.count >= 1
                            ? PhilotesTheme.tertiaryText
                            : PhilotesTheme.coral
                    )
                }

                Spacer()

                Button("取消", action: onClose)
                    .buttonStyle(.philotesInteractive)
                    .foregroundStyle(PhilotesTheme.secondaryText)

                Button(action: save) {
                    Text("保存设置")
                        .font(
                            .system(
                                size: 10,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .frame(height: 31)
                        .background(
                            canSave
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
        }
        .frame(width: 560, height: 680)
        .background(PhilotesTheme.sidebar)
        .preferredColorScheme(.dark)
        .alert(
            "删除「\(room.name)」？",
            isPresented: $isConfirmingDelete
        ) {
            Button("取消", role: .cancel) {}
            Button("删除聊天室", role: .destructive) {
                deleteRoom()
            }
        } message: {
            Text("聊天室里的全部消息会一起删除，且无法撤销。")
        }
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(title: "聊天室头像")

            AvatarImageEditor(
                image: $avatarImage,
                sourceURL: $avatarSourceURL,
                removeExistingImage: $removeAvatarImage,
                color: PhilotesTheme.blue
            )

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(34), spacing: 8),
                    count: 8
                ),
                spacing: 8
            ) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        avatarImage = nil
                        avatarSourceURL = nil
                        removeAvatarImage = true
                    } label: {
                        Text(emoji)
                            .font(.system(size: 17))
                            .frame(width: 34, height: 34)
                            .background(
                                selectedEmoji == emoji
                                    ? PhilotesTheme.blue.opacity(0.16)
                                    : PhilotesTheme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay {
                                if selectedEmoji == emoji {
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(
                                            PhilotesTheme.blue.opacity(0.55),
                                            lineWidth: 1
                                        )
                                }
                            }
                    }
                    .buttonStyle(.philotesInteractive)
                }
            }
        }
    }

    private var roomNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "聊天室名字")

            TextField("给这个房间起个名字", text: $name)
                .textFieldStyle(.plain)
                .font(
                    .system(
                        size: 12,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    PhilotesTheme.surface,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionEyebrow(title: "成员与邀请")
                Spacer()
                Text(
                    L10n.format(
                        "%lld 位成员",
                        Int64(selectedAgentIDs.count)
                    )
                )
                    .font(
                        .system(
                            size: 8,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            VStack(spacing: 6) {
                ForEach(model.agents) { agent in
                    memberRow(agent)
                }
            }
        }
    }

    private func memberRow(_ agent: AgentProfile) -> some View {
        let isSelected = selectedAgentIDs.contains(agent.id)
        let canRemove = selectedAgentIDs.count > 1

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(agent.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                AgentGlyph(
                    emoji: agent.emoji,
                    size: 13,
                    imagePath: agent.avatarImagePath
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(agent.role)
                    .font(
                        .system(
                            size: 8,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            Spacer()

            Button {
                if isSelected {
                    guard canRemove else { return }
                    selectedAgentIDs.remove(agent.id)
                } else {
                    selectedAgentIDs.insert(agent.id)
                }
                actionErrorMessage = ""
            } label: {
                Label(
                    isSelected ? "移出" : "邀请",
                    systemImage: isSelected
                        ? "minus.circle"
                        : "plus.circle"
                )
                .font(
                    .system(
                        size: 8,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    isSelected
                        ? PhilotesTheme.coral
                        : PhilotesTheme.blue
                )
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(
                    (
                        isSelected
                            ? PhilotesTheme.coral
                            : PhilotesTheme.blue
                    ).opacity(0.08),
                    in: Capsule()
                )
            }
            .buttonStyle(.philotesInteractive)
            .disabled(isSelected && !canRemove)
            .help(
                isSelected && !canRemove
                    ? "聊天室至少需要保留一位成员"
                    : (
                        isSelected
                            ? "移出聊天室"
                            : "邀请进入聊天室"
                    )
            )
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(
            isSelected
                ? PhilotesTheme.surfaceRaised
                : PhilotesTheme.surface.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                        ? PhilotesTheme.borderStrong
                        : PhilotesTheme.border,
                    lineWidth: 1
                )
        }
    }

    private var canSave: Bool {
        selectedAgentIDs.count >= 1
            && !name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    private func save() {
        guard canSave else { return }
        if model.updateGroupRoom(
            room,
            name: name,
            avatarEmoji: selectedEmoji,
            avatarImageURL: avatarSourceURL,
            removeAvatarImage: removeAvatarImage,
            agentIDs: Array(selectedAgentIDs)
        ) {
            onClose()
        } else {
            actionErrorMessage = model.groupChatError
                ?? "聊天室设置保存失败。"
        }
    }

    private func deleteRoom() {
        if model.deleteGroupRoom(room) {
            onClose()
        } else {
            actionErrorMessage = model.groupChatError
                ?? "聊天室删除失败。"
        }
    }
}

private struct CreateGroupChatSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedAgentIDs = Set<Int64>()
    @State private var validationMessage: String?

    private var selectedAgents: [AgentProfile] {
        model.agents.filter { selectedAgentIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CREATE A ROOM")
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .tracking(1.5)
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                    Text("一起坐一会儿")
                        .font(
                            .system(
                                size: 26,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("至少选择两位智能体。之后的群聊里，用 @ 决定谁开口。")
                        .font(
                            .system(
                                size: 11,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.secondaryText)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.philotesInteractive)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 26)
            .padding(.top, 25)
            .padding(.bottom, 20)

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(title: "房间名字")

                        TextField(
                            "留空就用成员名字命名",
                            text: $name
                        )
                        .textFieldStyle(.plain)
                        .font(
                            .system(
                                size: 13,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(
                            PhilotesTheme.surface,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    PhilotesTheme.border,
                                    lineWidth: 1
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionEyebrow(title: "席位")
                            Spacer()
                            Text(
                                L10n.format(
                                    "%lld 位已选择",
                                    Int64(selectedAgentIDs.count)
                                )
                            )
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .medium,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(
                                    selectedAgentIDs.count >= 2
                                        ? PhilotesTheme.mint
                                        : PhilotesTheme.tertiaryText
                                )
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: 180,
                                        maximum: 260
                                    ),
                                    spacing: 10
                                ),
                            ],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(model.agents) { agent in
                                AgentSeatButton(
                                    agent: agent,
                                    isSelected: selectedAgentIDs.contains(
                                        agent.id
                                    )
                                ) {
                                    if selectedAgentIDs.contains(agent.id) {
                                        selectedAgentIDs.remove(agent.id)
                                    } else {
                                        selectedAgentIDs.insert(agent.id)
                                    }
                                    validationMessage = nil
                                }
                            }
                        }
                    }

                    if let validationMessage {
                        Label(
                            validationMessage,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.coral)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }

            Divider()
                .overlay(PhilotesTheme.border)

            HStack(spacing: 10) {
                HStack(spacing: -4) {
                    ForEach(Array(selectedAgents.prefix(5))) { agent in
                        ZStack {
                            Circle()
                                .fill(PhilotesTheme.surfaceRaised)
                                .frame(width: 25, height: 25)
                            AgentGlyph(
                                emoji: agent.emoji,
                                size: 10,
                                imagePath: agent.avatarImagePath
                            )
                        }
                    }
                }

                Text(
                    selectedAgentIDs.count < 2
                        ? "再选 \(2 - selectedAgentIDs.count) 位就能建群"
                        : "舞台已经坐好了"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.tertiaryText)

                Spacer()

                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(
                    .system(
                        size: 10,
                        weight: .medium,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.secondaryText)

                Button(action: createRoom) {
                    Text("创建群聊")
                        .font(
                            .system(
                                size: 10,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            selectedAgentIDs.count >= 2
                                ? .black
                                : PhilotesTheme.tertiaryText
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 31)
                        .background(
                            selectedAgentIDs.count >= 2
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(selectedAgentIDs.count < 2)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .frame(width: 620, height: 590)
        .background(PhilotesTheme.canvas)
        .preferredColorScheme(.dark)
    }

    private func createRoom() {
        guard selectedAgentIDs.count >= 2 else {
            validationMessage = "至少选择两位智能体。"
            return
        }
        guard model.createGroupRoom(
            name: name,
            agentIDs: Array(selectedAgentIDs)
        ) else {
            validationMessage = model.groupChatError ?? "群聊没有创建成功。"
            return
        }
        isPresented = false
    }
}

private struct AgentSeatButton: View {
    let agent: AgentProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(agent.accentColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    AgentGlyph(
                        emoji: agent.emoji,
                        size: 14,
                        imagePath: agent.avatarImagePath
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(agent.role)
                        .font(
                            .system(
                                size: 8,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? agent.accentColor
                        : PhilotesTheme.tertiaryText
                )
            }
            .padding(.horizontal, 11)
            .frame(height: 54)
            .background(
                isSelected
                    ? PhilotesTheme.surfaceRaised
                    : PhilotesTheme.surface.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isSelected
                            ? agent.accentColor.opacity(0.28)
                            : PhilotesTheme.border,
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.philotesInteractive)
    }
}

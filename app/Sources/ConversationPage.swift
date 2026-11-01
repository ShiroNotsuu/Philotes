import SwiftUI

struct ConversationPage: View {
    @ObservedObject var model: AppModel
    var onClose: (() -> Void)?
    var onAgentDeleted: (() -> Void)?
    @State private var draft = ""
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var selectedSearchMessageID: Int64?
    @State private var isShowingAgentSettings = false
    @State private var isShowingForgetConfirmation = false
    @State private var scrollRestoreTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: model.activeAgent?.role.uppercased() ?? "PHILOTES",
                title: model.activeAgent?.name
                    ?? L10n.string("对话"),
                subtitle: "记得此刻，也记得那些没有被特别强调的小事。",
                localizesTitle: false
            ) {
                HStack(spacing: 8) {
                    if isSearchExpanded {
                        searchField
                            .transition(
                                .move(edge: .trailing)
                                    .combined(with: .opacity)
                            )
                    }

                    ToolbarIconButton(
                        systemName: "magnifyingglass",
                        label: isSearchExpanded ? "收起搜索" : "搜索聊天与记忆",
                        action: toggleSearch
                    )

                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(PhilotesTheme.surface)
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(PhilotesTheme.border, lineWidth: 1)

                        Menu {
                            Button {
                                isShowingAgentSettings = true
                            } label: {
                                Label("智能体设置", systemImage: "slider.horizontal.3")
                            }

                            Divider()

                            Button(role: .destructive) {
                                isShowingForgetConfirmation = true
                            } label: {
                                Label("忘记我", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PhilotesTheme.secondaryText)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    .frame(width: 32, height: 32)
                    .disabled(model.activeAgent == nil)
                    .help("更多")
                    .accessibilityLabel("更多")

                    if let onClose {
                        ToolbarIconButton(
                            systemName: "arrow.down.right.and.arrow.up.left",
                            label: "收起对话",
                            action: onClose
                        )
                    }
                }
                .animation(.easeOut(duration: 0.20), value: isSearchExpanded)
            }

            Divider()
                .overlay(PhilotesTheme.border)

            if isSearchExpanded && !normalizedSearchQuery.isEmpty {
                searchResultsPanel
                Divider()
                    .overlay(PhilotesTheme.border)
            }

            HStack(spacing: 0) {
                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(PhilotesTheme.border)
                    .frame(width: 1)

                contextRail
                    .frame(width: 278)
            }
        }
        .background(PhilotesTheme.canvas)
        .onAppear {
            composerFocused = true
        }
        .onChange(of: model.activeAgentID) {
            isSearchExpanded = false
            searchText = ""
            selectedSearchMessageID = nil
        }
        .sheet(isPresented: $isShowingAgentSettings) {
            if let agent = model.activeAgent {
                AgentSettingsSheet(agent: agent, model: model) {
                    isShowingAgentSettings = false
                }
            }
        }
        .alert(
            "忘记\(model.activeAgent?.name ?? "这个智能体")？",
            isPresented: $isShowingForgetConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("删除智能体", role: .destructive) {
                forgetActiveAgent()
            }
        } message: {
            Text("这会删除它的全部聊天、记忆、人格文件和 API 密钥，且无法撤销。")
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    conversationOpening

                    ForEach(model.messages) { message in
                        MessageRow(
                            message: message,
                            agentName: model.activeAgent?.name ?? "智能体",
                            agentEmoji: model.activeAgent?.emoji ?? "✨",
                            agentAvatarPath: model.activeAgent?.avatarImagePath,
                            agentColor: model.activeAgent?.accentColor ?? PhilotesTheme.blue
                        )
                            .id(message.id)
                    }

                    if !model.pendingMacActions.isEmpty {
                        MacActionApprovalCard(
                            actions: model.pendingMacActions,
                            isExecuting: model.isExecutingMacActions,
                            onApproveEntireTask: model.approveEntireMacTask,
                            onAlwaysAllow: model.alwaysAllowMacActions,
                            onApprove: model.approvePendingMacActions,
                            onCancel: model.cancelPendingMacActions
                        )
                        .id("macActions")
                    }

                    if model.isReplying {
                        if !hasStreamingDisplayableBody {
                            TypingIndicator()
                                .id("typing")
                        } else {
                            MessageRow(
                                message: ChatMessage(
                                    id: -1,
                                    role: .assistant,
                                    body: model.streamingText,
                                    createdAt: Date()
                                ),
                                agentName: model.activeAgent?.name ?? "智能体",
                                agentEmoji: model.activeAgent?.emoji ?? "✨",
                                agentAvatarPath: model.activeAgent?.avatarImagePath,
                                agentColor: model.activeAgent?.accentColor ?? PhilotesTheme.blue,
                                isStreaming: true
                            )
                            .id("streaming")
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("conversationBottom")
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)
                .padding(.bottom, 18)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                restoreLatestMessage(using: proxy, animated: false)
            }
            .onDisappear {
                scrollRestoreTask?.cancel()
                scrollRestoreTask = nil
            }
            .onChange(of: model.activeAgentID) {
                restoreLatestMessage(using: proxy, animated: false)
            }
            .onChange(of: model.messages.count) {
                guard let lastID = model.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: model.isReplying) {
                guard model.isReplying else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
            .onChange(of: model.streamingText) {
                guard model.isReplying else { return }
                proxy.scrollTo(
                    hasStreamingDisplayableBody ? "streaming" : "typing",
                    anchor: .bottom
                )
            }
            .onChange(of: selectedSearchMessageID) {
                guard let selectedSearchMessageID else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    proxy.scrollTo(selectedSearchMessageID, anchor: .center)
                }
            }
            .onChange(of: model.pendingMacActions.count) {
                guard !model.pendingMacActions.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("macActions", anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
        }
    }

    private func restoreLatestMessage(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        scrollRestoreTask?.cancel()
        scrollRestoreTask = Task { @MainActor in
            // LazyVStack needs one layout pass before the bottom anchor exists.
            await Task.yield()
            guard !Task.isCancelled else { return }

            if animated {
                withAnimation(.easeOut(duration: 0.20)) {
                    proxy.scrollTo("conversationBottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("conversationBottom", anchor: .bottom)
            }

            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            proxy.scrollTo("conversationBottom", anchor: .bottom)
        }
    }

    private var conversationOpening: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: "今天")

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    PhilotesTheme.blue.opacity(0.26),
                                    PhilotesTheme.lavender.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)

                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PhilotesTheme.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        L10n.format(
                            "和%@的日常",
                            model.activeAgent?.name
                                ?? L10n.string("斐洛")
                        )
                    )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("消息保存在这台 Mac")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var composer: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("和\(model.activeAgent?.name ?? "智能体")说点什么…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .onSubmit(sendDraft)

                Button(action: composerAction) {
                    Image(systemName: model.isReplying ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            model.isReplying || canSend
                                ? .black
                                : PhilotesTheme.tertiaryText
                        )
                        .frame(width: 30, height: 30)
                        .background(
                            model.isReplying
                                ? PhilotesTheme.coral
                                : canSend
                                    ? PhilotesTheme.primaryText
                                    : PhilotesTheme.surfaceRaised,
                            in: Circle()
                        )
                }
                .buttonStyle(.philotesInteractive)
                .disabled(!canSend && !model.isReplying)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(model.isReplying ? "停止生成" : "发送消息")
            }
            .padding(.leading, 15)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(PhilotesTheme.borderStrong, lineWidth: 1)
            }

            HStack {
                Label("本地记忆 · 自定义 API", systemImage: "network")
                Spacer()
                Text("⌘↩ 发送")
            }
            .font(.system(size: 9, weight: .regular, design: .rounded))
            .foregroundStyle(PhilotesTheme.tertiaryText)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 34)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: 760)
        .background(PhilotesTheme.canvas.opacity(0.97))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PhilotesTheme.tertiaryText)

            TextField("搜索聊天与记忆", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.primaryText)
                .focused($searchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isSearchExpanded = false
                }
                searchText = ""
                searchFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭搜索")
        }
        .padding(.horizontal, 10)
        .frame(width: 250, height: 32)
        .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingMessages: [ChatMessage] {
        guard !normalizedSearchQuery.isEmpty else { return [] }
        return model.messages.filter {
            $0.body.localizedCaseInsensitiveContains(normalizedSearchQuery)
        }
    }

    private var matchingMemories: [MemoryNode] {
        guard let agentID = model.activeAgentID,
              !normalizedSearchQuery.isEmpty
        else {
            return []
        }
        return model.memories(for: agentID).filter {
            $0.title.localizedCaseInsensitiveContains(normalizedSearchQuery)
                || $0.summary.localizedCaseInsensitiveContains(normalizedSearchQuery)
                || $0.source.localizedCaseInsensitiveContains(normalizedSearchQuery)
        }
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("搜索结果")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text("“\(normalizedSearchQuery)”")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .lineLimit(1)
                Spacer()
                Text(
                    L10n.format(
                        "%lld 项",
                        Int64(
                            matchingMessages.count
                                + matchingMemories.count
                        )
                    )
                )
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            HStack(alignment: .top, spacing: 18) {
                searchMessagesColumn
                Rectangle()
                    .fill(PhilotesTheme.border)
                    .frame(width: 1)
                searchMemoriesColumn
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 12)
        .background(PhilotesTheme.canvas)
    }

    private var searchMessagesColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("聊天记录", systemImage: "bubble.left.and.bubble.right")
                Spacer()
                Text("\(matchingMessages.count)")
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(PhilotesTheme.secondaryText)

            if matchingMessages.isEmpty {
                Text("没有匹配的聊天记录")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(matchingMessages.prefix(6)) { message in
                            Button {
                                selectedSearchMessageID = message.id
                                withAnimation(.easeOut(duration: 0.16)) {
                                    isSearchExpanded = false
                                }
                                searchText = ""
                                searchFocused = false
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(message.role == .user ? "你" : "AI")
                                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.tertiaryText)
                                        .frame(width: 18, alignment: .leading)
                                    Text(searchPreview(for: message))
                                        .font(.system(size: 9, weight: .regular, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.secondaryText)
                                        .lineLimit(2)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.philotesInteractive)
                        }
                    }
                }
                .frame(maxHeight: 104)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var searchMemoriesColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("记忆内容", systemImage: "sparkles")
                Spacer()
                Text("\(matchingMemories.count)")
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(PhilotesTheme.secondaryText)

            if matchingMemories.isEmpty {
                Text("没有匹配的记忆")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(matchingMemories.prefix(6)) { memory in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(memory.accentColor.opacity(0.8))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(memory.title)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.primaryText)
                                        .lineLimit(1)
                                    Text(memory.summary)
                                        .font(.system(size: 8, weight: .regular, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.tertiaryText)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 104)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var contextRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                agentProfileCard
                emotionCurveCard

                PhilotesCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionEyebrow(title: "可能相关")
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PhilotesTheme.blue)
                        }

                        ForEach(relatedMemories.prefix(3)) { memory in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(color(for: memory.kind).opacity(0.85))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(memory.title)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.primaryText)
                                        .lineLimit(1)
                                    Text(memory.summary)
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                        .foregroundStyle(PhilotesTheme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                        }

                        if relatedMemories.isEmpty {
                            Text("还没有记忆。聊过的事会从这里慢慢长出来。")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(PhilotesTheme.tertiaryText)
                        }
                    }
                }

                if let memory = relatedMemories.first {
                    PhilotesCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionEyebrow(title: "记忆来源")

                            Text(memory.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(PhilotesTheme.primaryText)

                            HStack {
                                Text(memory.source)
                                Spacer()
                                Text(memory.createdAt.philotesShortDate)
                            }
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                        }
                    }
                }

                HStack(spacing: 7) {
                    StatusDot(color: model.errorMessage == nil ? PhilotesTheme.mint : PhilotesTheme.coral)
                    Text(L10n.string(model.status))
                        .lineLimit(2)
                }
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.tertiaryText)
                .padding(.horizontal, 4)
            }
            .padding(22)
        }
        .background(PhilotesTheme.canvas)
    }

    private var canSend: Bool {
        model.activeAgentID != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isReplying
            && model.pendingMacActions.isEmpty
            && !model.isExecutingMacActions
    }

    private var relatedMemories: [MemoryNode] {
        guard let activeAgentID = model.activeAgentID else { return [] }
        return model.memories(for: activeAgentID)
    }

    private var parsedStreamingResponse: ParsedAssistantResponse {
        AssistantResponseParser.parse(model.streamingText)
    }

    private var hasStreamingDisplayableBody: Bool {
        !model.streamingText.isEmpty
            && !parsedStreamingResponse.body.isEmpty
    }

    private var activeProvider: AgentAPIProvider {
        guard let agent = model.activeAgent else {
            return AgentAPIProvider.none
        }
        return AgentAPIProvider(rawValue: agent.apiProvider)
            ?? AgentAPIProvider.none
    }

    private var personaSummary: AgentPersonaSummary? {
        guard let agentID = model.activeAgentID else { return nil }
        return AgentPersonaStore.summary(for: agentID)
    }

    private var agentProfileCard: some View {
        PhilotesCard {
            VStack(alignment: .leading, spacing: 12) {
                if let agent = model.activeAgent {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(agent.accentColor.opacity(0.14))
                                .frame(width: 38, height: 38)
                            AgentGlyph(
                                emoji: agent.emoji,
                                size: 17,
                                imagePath: agent.avatarImagePath
                            )
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(PhilotesTheme.primaryText)
                            Text(
                                agent.apiModel.isEmpty
                                    ? agent.role
                                    : "\(agent.role) · \(agent.apiModel)"
                            )
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundStyle(PhilotesTheme.tertiaryText)
                        }

                        Spacer()

                        Text(activeProvider.badgeTitle)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(agent.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(agent.accentColor.opacity(0.09), in: Capsule())
                    }

                    SettingsDivider()

                    if let summary = personaSummary {
                        ForEach(Array(summary.fields.prefix(8))) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.label)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(PhilotesTheme.tertiaryText)
                                    .frame(width: 58, alignment: .leading)
                                Text(field.value)
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundStyle(PhilotesTheme.secondaryText)
                                    .lineLimit(3)
                            }
                        }

                        if !summary.additionalDetails.isEmpty {
                            Divider()
                                .overlay(PhilotesTheme.border)
                            VStack(alignment: .leading, spacing: 4) {
                                SectionEyebrow(title: "自定义描述")
                                Text(summary.additionalDetails)
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundStyle(PhilotesTheme.secondaryText)
                                    .lineLimit(6)
                            }
                        }
                    } else {
                        Text("这个智能体还没有独立的人格档案。")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }
                }
            }
        }
    }

    private var emotionSamples: [EmotionSample] {
        Array(
            model.messages.compactMap { message -> EmotionSample? in
                guard message.role == .assistant else { return nil }
                let parsed = AssistantResponseParser.parse(message.body)
                guard let value = parsed.emotionValue else { return nil }
                return EmotionSample(id: message.id, value: value)
            }
            .suffix(18)
        )
    }

    private var averageEmotionText: String {
        guard !emotionSamples.isEmpty else { return "等待第一次采样" }
        let average = Int(
            (
                Double(emotionSamples.reduce(0) { $0 + $1.value })
                    / Double(emotionSamples.count)
            ).rounded()
        )
        let signed = average > 0 ? "+\(average)" : "\(average)"
        return "平均 \(signed) · \(EmotionScale.label(for: average))"
    }

    private var emotionCurveCard: some View {
        PhilotesCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionEyebrow(title: "情绪曲线")
                    Spacer()
                    Text(averageEmotionText)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                if emotionSamples.isEmpty {
                    Text("每次成功对话会记录一个情绪值。")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                } else {
                    EmotionCurveView(samples: emotionSamples)
                }
            }
        }
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = draft
        guard model.send(text) else { return }
        draft = ""
        composerFocused = true
    }

    private func composerAction() {
        if model.isReplying {
            model.cancelResponse()
        } else {
            sendDraft()
        }
    }

    private func toggleSearch() {
        let willExpand = !isSearchExpanded
        withAnimation(.easeOut(duration: 0.20)) {
            isSearchExpanded = willExpand
        }
        if !willExpand {
            searchText = ""
            searchFocused = false
            return
        }
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private func searchPreview(for message: ChatMessage) -> String {
        if message.role == .user {
            return message.body
        }
        let parsed = AssistantResponseParser.parse(message.body)
        return [parsed.action, parsed.body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func forgetActiveAgent() {
        guard let agent = model.activeAgent,
              model.deleteAgent(agent)
        else {
            return
        }
        isSearchExpanded = false
        searchText = ""
        selectedSearchMessageID = nil
        onAgentDeleted?()
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "date": PhilotesTheme.blue
        case "boundary": PhilotesTheme.coral
        case "principle": PhilotesTheme.lavender
        default: PhilotesTheme.mint
        }
    }
}

struct MacActionApprovalCard: View {
    let actions: [MacActionRequest]
    let isExecuting: Bool
    var compact = false
    var onApproveEntireTask: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(PhilotesTheme.blue.opacity(0.14))
                        .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("需要你确认 Mac 操作")
                        .font(
                            .system(
                                size: compact ? 10 : 12,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(
                        compact
                            ? "允许一次，或让当前任务不再询问。"
                            : "本任务全部允许会连续执行后续批次；始终允许可在设置中随时关闭。"
                    )
                        .font(
                            .system(
                                size: compact ? 8 : 9,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
            }

            VStack(spacing: 6) {
                ForEach(actions) { action in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: compact ? 9 : 10, weight: .medium))
                            .foregroundStyle(PhilotesTheme.secondaryText)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(
                                    .system(
                                        size: compact ? 9 : 10,
                                        weight: .medium,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(PhilotesTheme.primaryText)
                                .lineLimit(1)
                            Text(action.detail)
                                .font(
                                    .system(
                                        size: compact ? 8 : 9,
                                        weight: .regular,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(PhilotesTheme.tertiaryText)
                                .lineLimit(compact ? 3 : 6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        PhilotesTheme.surfaceRaised.opacity(0.64),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }

            HStack {
                if isExecuting {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在执行…")
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    Spacer()
                } else {
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.philotesInteractive)
                    .foregroundStyle(PhilotesTheme.secondaryText)

                    Spacer()

                    Button {
                        onApprove()
                    } label: {
                        Text("允许一次")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.black)
                            .padding(.horizontal, 11)
                            .frame(height: 27)
                            .background(
                                PhilotesTheme.primaryText,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.philotesInteractive)

                    if let onApproveEntireTask {
                        Button {
                            onApproveEntireTask()
                        } label: {
                            Text("本任务全部允许")
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(.black)
                                .padding(.horizontal, 11)
                                .frame(height: 27)
                                .background(
                                    PhilotesTheme.blue,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.philotesInteractive)
                    }

                    if let onAlwaysAllow {
                        Button {
                            onAlwaysAllow()
                        } label: {
                            Text("始终允许")
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(.black)
                                .padding(.horizontal, 11)
                                .frame(height: 27)
                                .background(
                                    PhilotesTheme.mint,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.philotesInteractive)
                        .help("以后自动执行智能体动作；可在设置中关闭")
                    }
                }
            }
        }
        .padding(compact ? 11 : 14)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(PhilotesTheme.blue.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
    }
}

struct PersonalityActivatedToast: View {
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(PhilotesTheme.mint.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.mint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("人格已激活")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text("它会带着这份设定继续认识你")
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            PhilotesTheme.surfaceRaised.opacity(0.96),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(PhilotesTheme.mint.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

struct AssistantActionPrompt: View {
    let text: String
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 8 : 9, weight: .semibold))
                .foregroundStyle(PhilotesTheme.lavender)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text("情绪与神态")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                Text(text)
                    .font(.system(size: compact ? 8 : 9, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .lineLimit(compact ? 2 : 4)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            PhilotesTheme.surfaceRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    PhilotesTheme.lavender.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        }
    }
}

private struct EmotionSample: Identifiable {
    let id: Int64
    let value: Int
}

private struct EmotionCurveView: View {
    let samples: [EmotionSample]

    var body: some View {
        VStack(spacing: 5) {
            Canvas { context, size in
                let horizontalInset: CGFloat = 3
                let width = max(1, size.width - horizontalInset * 2)
                let height = max(1, size.height)

                for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    var grid = Path()
                    let y = height * fraction
                    grid.move(to: CGPoint(x: horizontalInset, y: y))
                    grid.addLine(to: CGPoint(x: size.width - horizontalInset, y: y))
                    context.stroke(
                        grid,
                        with: .color(.white.opacity(fraction == 0.5 ? 0.10 : 0.04)),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: fraction == 0.5 ? [3, 3] : []
                        )
                    )
                }

                guard !samples.isEmpty else { return }
                let maxIndex = max(1, samples.count - 1)
                let points = samples.enumerated().map { index, sample in
                    let x = samples.count == 1
                        ? horizontalInset + width / 2
                        : horizontalInset
                            + CGFloat(index) / CGFloat(maxIndex) * width
                    let y = (CGFloat(100 - sample.value) / 200) * height
                    return CGPoint(x: x, y: y)
                }

                if points.count > 1,
                   let firstPoint = points.first,
                   let lastPoint = points.last {
                    var curve = Path()
                    curve.move(to: firstPoint)
                    for index in 1..<points.count {
                        let previous = points[index - 1]
                        let current = points[index]
                        let middleX = (previous.x + current.x) / 2
                        curve.addCurve(
                            to: current,
                            control1: CGPoint(x: middleX, y: previous.y),
                            control2: CGPoint(x: middleX, y: current.y)
                        )
                    }

                    var area = curve
                    area.addLine(to: CGPoint(x: lastPoint.x, y: height))
                    area.addLine(to: CGPoint(x: firstPoint.x, y: height))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [
                                PhilotesTheme.blue.opacity(0.17),
                                PhilotesTheme.blue.opacity(0.01),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: height)
                        )
                    )
                    context.stroke(
                        curve,
                        with: .color(PhilotesTheme.blue.opacity(0.88)),
                        style: StrokeStyle(
                            lineWidth: 1.6,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                for (index, point) in points.enumerated() {
                    let value = samples[index].value
                    let radius: CGFloat = index == points.count - 1 ? 3.2 : 2.2
                    let dot = Path(
                        ellipseIn: CGRect(
                            x: point.x - radius,
                            y: point.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    )
                    context.fill(dot, with: .color(color(for: value)))
                }
            }
            .frame(height: 68)
            .background(
                PhilotesTheme.surfaceRaised.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }

            HStack {
                Text("-100 低落")
                Spacer()
                Text("0 平静")
                Spacer()
                Text("+100 高涨")
            }
            .font(.system(size: 7, weight: .regular, design: .rounded))
            .foregroundStyle(PhilotesTheme.tertiaryText)
        }
    }

    private func color(for value: Int) -> Color {
        switch value {
        case ...(-30): PhilotesTheme.coral
        case ..<10: PhilotesTheme.lavender
        case ...30: PhilotesTheme.blue
        default: PhilotesTheme.mint
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let agentName: String
    let agentEmoji: String
    let agentAvatarPath: String?
    let agentColor: Color
    var isStreaming = false

    private var isUser: Bool {
        message.role == .user
    }

    private var parsedResponse: ParsedAssistantResponse {
        isUser
            ? ParsedAssistantResponse(
                action: nil,
                emotionValue: nil,
                metadata: [],
                body: message.body,
                isAwaitingActionClose: false
            )
            : AssistantResponseParser.parse(message.body)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 88)
            } else {
                avatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if isUser {
                        Text(message.createdAt.philotesTime)
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }

                    Text(isUser ? "你" : agentName)
                        .foregroundStyle(PhilotesTheme.secondaryText)

                    if !isUser {
                        Text(message.createdAt.philotesTime)
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))

                if !isUser, let action = parsedResponse.action {
                    AssistantActionPrompt(text: action)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isUser || !parsedResponse.body.isEmpty {
                    Text(
                        isStreaming
                            ? parsedResponse.body + "▍"
                            : parsedResponse.body
                    )
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(
                            isUser
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.primaryText.opacity(0.82)
                        )
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            isUser
                                ? PhilotesTheme.blue.opacity(0.16)
                                : PhilotesTheme.surface,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(
                                    isUser
                                        ? PhilotesTheme.blue.opacity(0.16)
                                        : PhilotesTheme.border,
                                    lineWidth: 1
                                )
                        }
                }
            }

            if !isUser {
                Spacer(minLength: 88)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            PhilotesTheme.blue.opacity(0.20),
                            PhilotesTheme.lavender.opacity(0.11)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)

            AgentGlyph(
                emoji: agentEmoji,
                size: 13,
                imagePath: agentAvatarPath
            )
        }
        .padding(.top, 17)
    }
}

private struct TypingIndicator: View {
    var body: some View {
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
        .background(PhilotesTheme.surface, in: Capsule())
        .padding(.leading, 42)
    }
}


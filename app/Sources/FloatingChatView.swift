import SwiftUI

struct FloatingChatView: View {
    @ObservedObject var model: AppModel
    let onExpand: () -> Void

    @State private var isHovering = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false

    private var isExpanded: Bool {
        isHovering || !draft.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Rectangle()
                    .fill(PhilotesTheme.border)
                    .frame(height: 1)

                messagePreview
                composer
            }
        }
        .frame(width: isExpanded ? 430 : 342, height: isExpanded ? 366 : 58)
        .background(
            isExpanded ? PhilotesTheme.surface : PhilotesTheme.surface.opacity(0.96),
            in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? 18 : 16, style: .continuous)
                .stroke(
                    isExpanded ? PhilotesTheme.borderStrong : PhilotesTheme.border,
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.42), radius: 24, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering in
            withAnimation(panelAnimation) {
                isHovering = hovering
            }
            if hovering {
                NotificationCenter.default.post(
                    name: .philotesDismissConstellationPreview,
                    object: nil
                )
            }
        }
        .animation(panelAnimation, value: isExpanded)
        .accessibilityIdentifier("floatingChat")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((model.activeAgent?.accentColor ?? PhilotesTheme.blue).opacity(0.14))
                    .frame(width: 34, height: 34)
                AgentGlyph(
                    emoji: model.activeAgent?.emoji ?? "✨",
                    size: 15,
                    imagePath: model.activeAgent?.avatarImagePath
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(
                        model.activeAgent?.name
                            ?? L10n.string("没有智能体")
                    )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)

                    Circle()
                        .fill(PhilotesTheme.mint)
                        .frame(width: 5, height: 5)
                }

                Text(
                    isExpanded
                        ? (model.activeAgent?.role ?? "创建一个智能体")
                        : lastMessagePreview
                )
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.tertiaryText)
                .lineLimit(1)
            }

            Spacer()

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.philotesInteractive)
            .help("展开到整页")
            .accessibilityLabel("展开到整页")
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var messagePreview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.messages.suffix(7)) { message in
                    messageView(message)
                }

                if !model.pendingMacActions.isEmpty {
                    MacActionApprovalCard(
                        actions: model.pendingMacActions,
                        isExecuting: model.isExecutingMacActions,
                        compact: true,
                        onApproveEntireTask: model.approveEntireMacTask,
                        onAlwaysAllow: model.alwaysAllowMacActions,
                        onApprove: model.approvePendingMacActions,
                        onCancel: model.cancelPendingMacActions
                    )
                }

                if model.isReplying {
                    let parsed = AssistantResponseParser.parse(model.streamingText)
                    if model.streamingText.isEmpty || parsed.body.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(PhilotesTheme.tertiaryText)
                                    .frame(width: 3, height: 3)
                                    .opacity(0.5 + Double(index) * 0.16)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            if let action = parsed.action {
                                AssistantActionPrompt(text: action, compact: true)
                            }
                            messageBubble(
                                text: parsed.body + "▍",
                                isUser: false
                            )
                        }
                    }
                }

                if model.messages.isEmpty && !model.isReplying {
                    Text("还没有对话。先说一句就好。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                }
            }
            .padding(14)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                L10n.format(
                    "和%@说点什么…",
                    model.activeAgent?.name
                        ?? L10n.string("智能体")
                ),
                text: $draft,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.primaryText)
                .lineLimit(1...3)
                .focused($inputFocused)
                .onSubmit(send)

            Button(action: composerAction) {
                Image(systemName: model.isReplying ? "stop.fill" : "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        model.isReplying || canSend
                            ? .black
                            : PhilotesTheme.tertiaryText
                    )
                    .frame(width: 27, height: 27)
                    .background(
                        model.isReplying
                            ? PhilotesTheme.coral
                            : canSend
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.surface,
                        in: Circle()
                    )
            }
            .buttonStyle(.philotesInteractive)
            .disabled(!canSend && !model.isReplying)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
        .padding(12)
    }

    private var canSend: Bool {
        model.activeAgentID != nil
            && !model.isReplying
            && model.pendingMacActions.isEmpty
            && !model.isExecutingMacActions
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var panelAnimation: Animation {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .easeOut(duration: 0.22)
    }

    private var lastMessagePreview: String {
        let raw: String
        if model.isReplying {
            raw = model.streamingText.isEmpty
                ? "正在回复…"
                : model.streamingText
        } else {
            raw = model.messages.last?.body
                ?? "悬停展开，和最近的智能体聊聊"
        }
        let parsed = AssistantResponseParser.parse(raw)
        let preview = [parsed.action, parsed.body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return (preview.isEmpty ? raw : preview)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        guard model.send(text) else { return }
        draft = ""
        inputFocused = true
    }

    private func composerAction() {
        if model.isReplying {
            model.cancelResponse()
        } else {
            send()
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        if message.role == .user {
            messageBubble(text: message.body, isUser: true)
        } else {
            let parsed = AssistantResponseParser.parse(message.body)
            VStack(alignment: .leading, spacing: 4) {
                if let action = parsed.action {
                    AssistantActionPrompt(text: action, compact: true)
                }
                if !parsed.body.isEmpty {
                    messageBubble(text: parsed.body, isUser: false)
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(text: String, isUser: Bool) -> some View {
        HStack {
            if isUser {
                Spacer(minLength: 54)
            }

            Text(text)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(
                    isUser
                        ? PhilotesTheme.primaryText
                        : PhilotesTheme.secondaryText
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isUser
                        ? PhilotesTheme.blue.opacity(0.14)
                        : PhilotesTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            if !isUser {
                Spacer(minLength: 54)
            }
        }
    }
}

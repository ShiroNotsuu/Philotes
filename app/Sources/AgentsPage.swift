import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentsPage: View {
    @ObservedObject var model: AppModel
    let onOpenChat: () -> Void
    @State private var showingCreator = false
    @State private var showingMemoryImporter = false
    @State private var editingAgent: AgentProfile?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "AGENTS",
                title: "智能体",
                subtitle: "与你一起生活、创作和行动的智能体。"
            ) {
                HStack(spacing: 9) {
                    Button {
                        showingMemoryImporter = true
                    } label: {
                        Label(
                            "从聊天记忆导入智能体",
                            systemImage: "arrow.down.doc"
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(PhilotesTheme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.philotesInteractive)
                    .accessibilityIdentifier("agents.importMemory")

                    Button {
                        showingCreator = true
                    } label: {
                        Label("创建智能体", systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(PhilotesTheme.primaryText, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.philotesInteractive)
                    .accessibilityIdentifier("agents.create")
                }
            }

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentAgentBanner

                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)
                        ],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(model.agents) { agent in
                            AgentCard(
                                agent: agent,
                                isActive: agent.id == model.activeAgentID,
                                memoryNodes: model.memories(for: agent.id),
                                onEdit: {
                                    editingAgent = agent
                                }
                            ) {
                                model.setActiveAgent(agent)
                                onOpenChat()
                            }
                        }

                        CreateAgentCard {
                            showingCreator = true
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .frame(maxWidth: 1_080, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PhilotesTheme.canvas)
        .sheet(isPresented: $showingCreator) {
            CreateAgentSheet(model: model, isPresented: $showingCreator)
        }
        .sheet(isPresented: $showingMemoryImporter) {
            ImportMemoryAgentSheet(
                model: model,
                isPresented: $showingMemoryImporter
            ) {
                onOpenChat()
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentSettingsSheet(agent: agent, model: model) {
                editingAgent = nil
            }
        }
    }

    @ViewBuilder
    private var currentAgentBanner: some View {
        if let activeAgent = model.activeAgent {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(activeAgent.accentColor.opacity(0.12))
                        .frame(width: 46, height: 46)
                    AgentGlyph(
                        emoji: activeAgent.emoji,
                        size: 20,
                        imagePath: activeAgent.avatarImagePath
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text("当前聊天")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                        Circle()
                            .fill(PhilotesTheme.mint)
                            .frame(width: 5, height: 5)
                    }

                    Text(activeAgent.name)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)

                    Text(
                        "\(activeAgent.role) · "
                            + "\(model.memories(for: activeAgent.id).count) 条记忆 · "
                            + (
                                AgentAPIProvider(rawValue: activeAgent.apiProvider)
                                    ?? AgentAPIProvider.none
                            ).badgeTitle
                    )
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Button(action: onOpenChat) {
                    Label("打开对话", systemImage: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.philotesInteractive)
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        activeAgent.accentColor.opacity(0.07),
                        PhilotesTheme.surface
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
        }
    }
}

private struct AgentCard: View {
    let agent: AgentProfile
    let isActive: Bool
    let memoryNodes: [MemoryNode]
    let onEdit: () -> Void
    let onChat: () -> Void

    @State private var isHovering = false

    private var apiProvider: AgentAPIProvider {
        AgentAPIProvider(rawValue: agent.apiProvider)
            ?? AgentAPIProvider.none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    agent.accentColor.opacity(0.22),
                                    agent.accentColor.opacity(0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)

                    AgentGlyph(
                        emoji: agent.emoji,
                        size: 20,
                        imagePath: agent.avatarImagePath
                    )
                }

                Spacer()

                if isActive {
                    Label("当前", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(agent.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(agent.accentColor.opacity(0.09), in: Capsule())
                }

                Menu {
                    Button("更改智能体设定") {
                        onEdit()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(agent.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(agent.role)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)

                Label(apiProvider.badgeTitle, systemImage: "network")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        apiProvider == .none
                            ? PhilotesTheme.tertiaryText
                            : agent.accentColor
                    )
            }

            HStack(spacing: 12) {
                Label(
                    L10n.format(
                        "%lld 记忆",
                        Int64(agent.memoryCount)
                    ),
                    systemImage: "sparkles"
                )
                Label(agent.lastActiveAt.philotesShortDate, systemImage: "clock")
            }
            .font(.system(size: 9, weight: .regular, design: .rounded))
            .foregroundStyle(PhilotesTheme.tertiaryText)

            HStack(spacing: 4) {
                ForEach(memoryNodes.prefix(7)) { memory in
                    Circle()
                        .fill(memory.accentColor.opacity(0.75))
                        .frame(width: 5, height: 5)
                }
                Spacer()
                Text(agent.lastActiveAt.philotesShortDate)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            Button(action: onChat) {
                HStack {
                    Text(isActive ? "继续聊天" : "切换并聊天")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .padding(.horizontal, 11)
                .frame(height: 31)
                .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.philotesInteractive)
        }
        .padding(18)
        .background(
            isHovering ? PhilotesTheme.surfaceRaised : PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(
                    isActive ? agent.accentColor.opacity(0.20) : PhilotesTheme.border,
                    lineWidth: 1
                )
        }
        .onHover { isHovering = $0 }
        .offset(y: isHovering ? -2 : 0)
        .shadow(
            color: isHovering ? .black.opacity(0.24) : .clear,
            radius: 10,
            y: 5
        )
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

private struct CreateAgentCard: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .frame(width: 42, height: 42)
                    .background(PhilotesTheme.surfaceRaised, in: Circle())

                Text("创建新的智能体")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)

                Text("名字、符号与独立的模型连接")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 218)
            .background(PhilotesTheme.surface.opacity(0.42), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(
                        isHovering ? PhilotesTheme.borderStrong : PhilotesTheme.border,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
            }
            .scaleEffect(isHovering ? 1.008 : 1)
        }
        .buttonStyle(.philotesInteractive)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

private struct CreateAgentSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var name = ""
    @State private var selectedEmoji = "✨"
    @State private var selectedAccent = "blue"
    @State private var avatarImage: NSImage?
    @State private var avatarSourceURL: URL?
    @State private var removeAvatarImage = false
    @State private var apiProvider: AgentAPIProvider = .deepseek
    @State private var apiBaseURL = AgentAPIProvider.deepseek.defaultBaseURL
    @State private var apiModel = AgentAPIProvider.deepseek.defaultModel
    @State private var apiKeyInput = ""
    @State private var clearStoredAPIKey = false
    @State private var actionErrorMessage = ""
    @State private var relationshipSelections: Set<String> = ["生活搭档"]
    @State private var customRelationship = ""
    @State private var genderSelections: Set<String> = ["不限定"]
    @State private var customGender = ""
    @State private var ageSelections: Set<String> = ["青年感"]
    @State private var customAge = ""
    @State private var personalitySelections: Set<String> = ["温柔", "敏锐"]
    @State private var customPersonality = ""
    @State private var speakingStyleSelections: Set<String> = ["自然"]
    @State private var customSpeakingStyle = ""
    @State private var initiativeSelections: Set<String> = ["平衡"]
    @State private var customInitiative = ""
    @State private var emotionalExpressionSelections: Set<String> = ["自然"]
    @State private var customEmotionalExpression = ""
    @State private var addressSelections: Set<String> = ["主人"]
    @State private var customAddress = ""
    @State private var additionalDetails = ""
    @State private var showsAdvancedPersona = false

    private let emojis = [
        "✨", "🐟", "🌙", "🌿", "🔥", "🎧", "📚", "✍️",
        "🪐", "🛰️", "🫧", "🦊", "🐈", "🍵", "🧭", "💫",
    ]
    private let accents = ["blue", "lavender", "mint", "coral"]
    private let relationshipOptions = [
        "生活搭档", "创作搭档", "行动搭档", "学习伙伴", "情绪知己",
    ]
    private let genderOptions = ["女性", "男性", "非二元", "不限定"]
    private let ageOptions = ["少年感", "青年感", "成熟", "不设年龄"]
    private let personalityOptions = [
        "温柔", "理性", "活泼", "安静", "敏锐", "俏皮", "坚定", "浪漫",
    ]
    private let speakingStyleOptions = [
        "简洁", "细腻", "幽默", "直接", "含蓄", "有诗意",
    ]
    private let initiativeOptions = ["克制", "平衡", "主动", "随你"]
    private let emotionalExpressionOptions = ["含蓄", "自然", "热烈", "稳定"]
    private let addressOptions = ["主人", "你", "名字"]
    private let customPersonaChoice = "__custom__"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("创建智能体")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(
                        L10n.format(
                            "第 %lld 步，共 3 步",
                            Int64(step + 1)
                        )
                    )
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(PhilotesTheme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.philotesInteractive)
            }

            ZStack(alignment: .top) {
                stepContent
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.22), value: step)

            if !actionErrorMessage.isEmpty {
                Text(L10n.string(actionErrorMessage))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.coral)
                    .lineLimit(2)
            }

            HStack {
                if step > 0 {
                    Button {
                        withAnimation {
                            step -= 1
                        }
                        actionErrorMessage = ""
                    } label: {
                        Label("上一步", systemImage: "chevron.left")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(PhilotesTheme.secondaryText)
                    }
                    .buttonStyle(.philotesInteractive)
                } else {
                    Button("取消") {
                        close()
                    }
                    .buttonStyle(.philotesInteractive)
                    .foregroundStyle(PhilotesTheme.secondaryText)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(
                                index == step
                                    ? selectedColor
                                    : PhilotesTheme.tertiaryText.opacity(0.22)
                            )
                            .frame(width: index == step ? 18 : 6, height: 6)
                    }
                }

                Spacer()

                Button {
                    if step < 2 {
                        withAnimation {
                            step += 1
                        }
                        actionErrorMessage = ""
                    } else {
                        createAgent()
                    }
                } label: {
                    Label(
                        step < 2 ? "下一步" : "激活人格",
                        systemImage: step < 2 ? "arrow.right" : "sparkles"
                    )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(PhilotesTheme.primaryText, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.philotesInteractive)
                .disabled(!canAdvance)
            }
        }
        .padding(24)
        .frame(width: 580, height: 640)
        .background(PhilotesTheme.sidebar)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            identityStep
        case 1:
            thinkingStep
        default:
            personaStep
        }
    }

    private var identityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepHero(
                    title: "我是谁",
                    subtitle: "先给这个存在一个名字，再选一个能代表它的图标。"
                )

                HStack(spacing: 16) {
                    AvatarPreview(
                        image: avatarImage,
                        emoji: selectedEmoji,
                        color: selectedColor,
                        size: 68
                    )

                    LabeledField(
                        title: "名字",
                        placeholder: "例如：斐洛",
                        text: $name
                    )
                }

                VStack(alignment: .leading, spacing: 9) {
                    SectionEyebrow(title: "图标")
                    Text("选择 Emoji，或上传一张本地图片作为头像。")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)

                    AvatarImageEditor(
                        image: $avatarImage,
                        sourceURL: $avatarSourceURL,
                        removeExistingImage: $removeAvatarImage,
                        color: selectedColor
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
                                            ? selectedColor.opacity(0.16)
                                            : PhilotesTheme.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                                    .overlay {
                                        if selectedEmoji == emoji {
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(
                                                    selectedColor.opacity(0.55),
                                                    lineWidth: 1
                                                )
                                        }
                                    }
                            }
                            .buttonStyle(.philotesInteractive)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    SectionEyebrow(title: "星系颜色")
                    HStack(spacing: 10) {
                        ForEach(accents, id: \.self) { accent in
                            Button {
                                selectedAccent = accent
                            } label: {
                                Circle()
                                    .fill(color(for: accent))
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if selectedAccent == accent {
                                            Circle()
                                                .stroke(.white, lineWidth: 2)
                                                .padding(3)
                                        }
                                    }
                            }
                            .buttonStyle(.philotesInteractive)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private var thinkingStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepHero(
                    title: "谁来帮助我思考",
                    subtitle: "为这个智能体选择独立的 API；也可以暂时不配置。"
                )

                AgentAPIConfigurationEditor(
                    model: model,
                    provider: $apiProvider,
                    baseURL: $apiBaseURL,
                    modelName: $apiModel,
                    apiKeyInput: $apiKeyInput,
                    clearStoredAPIKey: $clearStoredAPIKey,
                    existingAgentID: nil
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private var personaStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StepHero(
                    title: "我是怎么样的",
                    subtitle: "选择最接近它的描述；找不到合适的，就点“自定义”用自然语言告诉我。"
                )

                PersonaChoiceField(
                    title: "陪伴关系",
                    prompt: "它更像哪一种长期关系？",
                    options: relationshipOptions,
                    allowsMultiple: false,
                    selections: $relationshipSelections,
                    customText: $customRelationship
                )

                PersonaChoiceField(
                    title: "性别",
                    prompt: "这是一个表达设定，不限制它如何称呼自己。",
                    options: genderOptions,
                    allowsMultiple: false,
                    selections: $genderSelections,
                    customText: $customGender
                )

                PersonaChoiceField(
                    title: "年龄感",
                    prompt: "选择它带来的年龄气质，而不是严格数字。",
                    options: ageOptions,
                    allowsMultiple: false,
                    selections: $ageSelections,
                    customText: $customAge
                )

                PersonaChoiceField(
                    title: "性格气质",
                    prompt: "可以多选，也可以补充自己的描述。",
                    options: personalityOptions,
                    allowsMultiple: true,
                    selections: $personalitySelections,
                    customText: $customPersonality
                )

                PersonaChoiceField(
                    title: "说话方式",
                    prompt: "它会怎样把话交到你手里？",
                    options: speakingStyleOptions,
                    allowsMultiple: true,
                    selections: $speakingStyleSelections,
                    customText: $customSpeakingStyle
                )

                DisclosureGroup(isExpanded: $showsAdvancedPersona) {
                    VStack(alignment: .leading, spacing: 12) {
                        PersonaChoiceField(
                            title: "主动程度",
                            prompt: "它多久会主动靠近你一次？",
                            options: initiativeOptions,
                            allowsMultiple: false,
                            selections: $initiativeSelections,
                            customText: $customInitiative
                        )

                        PersonaChoiceField(
                            title: "情感表达",
                            prompt: "它表达关心时更偏向哪种方式？",
                            options: emotionalExpressionOptions,
                            allowsMultiple: false,
                            selections: $emotionalExpressionSelections,
                            customText: $customEmotionalExpression
                        )

                        PersonaChoiceField(
                            title: "对你的称呼",
                            prompt: "它平时最自然会怎么叫你？",
                            options: addressOptions,
                            allowsMultiple: false,
                            selections: $addressSelections,
                            customText: $customAddress
                        )
                    }
                    .padding(.top, 16)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("更多细节")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(PhilotesTheme.primaryText)
                            Text("主动程度、情感表达与称呼")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundStyle(PhilotesTheme.tertiaryText)
                        }
                        Spacer()
                    }
                }
                .tint(PhilotesTheme.secondaryText)
                .padding(14)
                .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow(title: "补充人格细节")
                    Text("还可以用自然语言描述它的经历、喜好、边界感或任何重要的事。")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                    PersonaNaturalLanguageEditor(
                        text: $additionalDetails,
                        placeholder: "例如：它表面安静，但对熟悉的人会突然冒出很冷的笑话……"
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            guard apiProvider != .none else { return true }
            return (try? APISettings.resolvedValues(
                provider: apiProvider,
                baseURL: apiBaseURL,
                model: apiModel
            )) != nil
        default:
            if relationshipSelections.contains(customPersonaChoice) {
                return !customRelationship.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
            return !resolvedRelationship.isEmpty
        }
    }

    private var resolvedRelationship: String {
        if relationshipSelections.contains(customPersonaChoice) {
            return customRelationship.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        return relationshipOptions.first {
            relationshipSelections.contains($0)
        } ?? ""
    }

    private func selectedLabels(
        options: [String],
        selections: Set<String>,
        customText: String
    ) -> [String] {
        var labels = options.filter { selections.contains($0) }
        let cleanCustom = customText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if selections.contains(customPersonaChoice), !cleanCustom.isEmpty {
            labels.append("自定义：\(cleanCustom)")
        }
        return labels.isEmpty ? ["未指定"] : labels
    }

    private func selectedValue(
        options: [String],
        selections: Set<String>,
        customText: String
    ) -> String {
        if selections.contains(customPersonaChoice) {
            let cleanCustom = customText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !cleanCustom.isEmpty {
                return cleanCustom
            }
        }
        return options.first { selections.contains($0) } ?? "未指定"
    }

    private func createAgent() {
        let persona = AgentPersonaDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: selectedEmoji,
            relationship: resolvedRelationship,
            gender: selectedValue(
                options: genderOptions,
                selections: genderSelections,
                customText: customGender
            ),
            age: selectedValue(
                options: ageOptions,
                selections: ageSelections,
                customText: customAge
            ),
            personality: selectedLabels(
                options: personalityOptions,
                selections: personalitySelections,
                customText: customPersonality
            ),
            speakingStyle: selectedLabels(
                options: speakingStyleOptions,
                selections: speakingStyleSelections,
                customText: customSpeakingStyle
            ),
            initiative: selectedValue(
                options: initiativeOptions,
                selections: initiativeSelections,
                customText: customInitiative
            ),
            emotionalExpression: selectedValue(
                options: emotionalExpressionOptions,
                selections: emotionalExpressionSelections,
                customText: customEmotionalExpression
            ),
            address: selectedValue(
                options: addressOptions,
                selections: addressSelections,
                customText: customAddress
            ),
            additionalDetails: additionalDetails.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )

        if model.createAgent(
            name: persona.name,
            role: persona.relationship,
            emoji: persona.emoji,
            accent: selectedAccent,
            apiProvider: apiProvider,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            apiKey: apiKeyInput,
            persona: persona,
            avatarImageURL: avatarSourceURL
        ) {
            close()
        } else {
            actionErrorMessage = model.errorMessage ?? "智能体创建失败。"
        }
    }

    private var selectedColor: Color {
        color(for: selectedAccent)
    }

    private func color(for accent: String) -> Color {
        switch accent {
        case "lavender": PhilotesTheme.lavender
        case "mint": PhilotesTheme.mint
        case "coral": PhilotesTheme.coral
        default: PhilotesTheme.blue
        }
    }

    private func close() {
        isPresented = false
        dismiss()
    }
}

struct AvatarPreview: View {
    let image: NSImage?
    let emoji: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: size, height: size)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                AgentGlyph(emoji: emoji, size: size * 0.42)
            }
        }
        .overlay {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct AvatarImageEditor: View {
    @Binding var image: NSImage?
    @Binding var sourceURL: URL?
    @Binding var removeExistingImage: Bool
    let color: Color

    @State private var isChoosingImage = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    isChoosingImage = true
                } label: {
                    Label(
                        image == nil ? "上传图片" : "更换图片",
                        systemImage: "photo"
                    )
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        PhilotesTheme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.philotesInteractive)

                if image != nil {
                    Button {
                        image = nil
                        sourceURL = nil
                        removeExistingImage = true
                        errorMessage = nil
                    } label: {
                        Text("改用 Emoji")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(color)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(color.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.philotesInteractive)
                }
            }

            if let errorMessage {
                Text(L10n.string(errorMessage))
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.coral)
            }
        }
        .fileImporter(
            isPresented: $isChoosingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let loaded = NSImage(contentsOf: url) else {
                    throw AvatarStoreError.invalidImage
                }
                image = loaded
                sourceURL = url
                removeExistingImage = false
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StepHero: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PhilotesTheme.primaryText)
            Text(L10n.string(subtitle))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(PhilotesTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

private struct PersonaChoiceField: View {
    let title: String
    let prompt: String
    let options: [String]
    let allowsMultiple: Bool
    @Binding var selections: Set<String>
    @Binding var customText: String
    var showsCustomOption = true
    var accentColor = PhilotesTheme.blue

    private let customChoice = "__custom__"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(prompt)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            PersonaFlowLayout(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    choiceButton(
                        title: option,
                        isSelected: selections.contains(option)
                    ) {
                        toggle(option)
                    }
                }

                if showsCustomOption {
                    choiceButton(
                        title: "自定义…",
                        isSelected: selections.contains(customChoice)
                    ) {
                        toggleCustom()
                    }
                }
            }

            if showsCustomOption && selections.contains(customChoice) {
                PersonaNaturalLanguageEditor(
                    text: $customText,
                    placeholder: "用自然语言描述你想要的设定…"
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.18), value: selections)
    }

    private func choiceButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(L10n.string(title))
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(
                isSelected
                    ? PhilotesTheme.primaryText
                    : PhilotesTheme.secondaryText
            )
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(
                isSelected
                    ? accentColor.opacity(0.15)
                    : PhilotesTheme.surfaceRaised,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? accentColor.opacity(0.42)
                            : PhilotesTheme.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.philotesInteractive)
    }

    private func toggle(_ option: String) {
        if allowsMultiple {
            if selections.contains(option) {
                selections.remove(option)
            } else {
                selections.insert(option)
            }
        } else {
            selections = [option]
        }
    }

    private func toggleCustom() {
        if selections.contains(customChoice) {
            selections.remove(customChoice)
            if !allowsMultiple {
                selections = []
            }
            customText = ""
        } else if allowsMultiple {
            selections.insert(customChoice)
        } else {
            selections = [customChoice]
        }
    }
}

private struct PersonaFlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            contentWidth = max(contentWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(
            width: proposal.width ?? contentWidth,
            height: y + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct PersonaNaturalLanguageEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 78)
                .background(
                    PhilotesTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct AgentSettingsSheet: View {
    let agent: AgentProfile
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEmoji: String
    @State private var selectedAccent: String
    @State private var avatarImage: NSImage?
    @State private var avatarSourceURL: URL?
    @State private var removeAvatarImage: Bool
    @State private var apiProvider: AgentAPIProvider
    @State private var apiBaseURL: String
    @State private var apiModel: String
    @State private var apiKeyInput = ""
    @State private var clearStoredAPIKey = false
    @State private var actionErrorMessage = ""

    private let emojis = [
        "✨", "🐟", "🌙", "🌿", "🔥", "🎧", "📚", "✍️",
        "🪐", "🛰️", "🫧", "🦊", "🐈", "🍵", "🧭", "💫",
    ]
    private let accents = ["blue", "lavender", "mint", "coral"]

    init(
        agent: AgentProfile,
        model: AppModel,
        onClose: @escaping () -> Void
    ) {
        self.agent = agent
        self.model = model
        self.onClose = onClose
        _selectedEmoji = State(initialValue: agent.emoji)
        _selectedAccent = State(initialValue: agent.accent)
        _avatarImage = State(
            initialValue: agent.avatarImagePath.flatMap {
                NSImage(contentsOfFile: $0)
            }
        )
        _avatarSourceURL = State(initialValue: nil)
        _removeAvatarImage = State(initialValue: false)
        _apiProvider = State(
            initialValue: AgentAPIProvider(rawValue: agent.apiProvider)
                ?? AgentAPIProvider.none
        )
        _apiBaseURL = State(initialValue: agent.apiBaseURL)
        _apiModel = State(initialValue: agent.apiModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                AvatarPreview(
                    image: avatarImage,
                    emoji: selectedEmoji,
                    color: selectedColor,
                    size: 52
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("智能体设定")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("\(agent.name) · \(agent.role)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(PhilotesTheme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.philotesInteractive)
            }

            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionEyebrow(title: "头像")
                        AvatarImageEditor(
                            image: $avatarImage,
                            sourceURL: $avatarSourceURL,
                            removeExistingImage: $removeAvatarImage,
                            color: selectedColor
                        )
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 8),
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
                                                ? selectedColor.opacity(0.16)
                                                : PhilotesTheme.surfaceRaised,
                                            in: RoundedRectangle(cornerRadius: 9)
                                        )
                                        .overlay {
                                            if selectedEmoji == emoji {
                                                RoundedRectangle(cornerRadius: 9)
                                                    .stroke(selectedColor.opacity(0.55), lineWidth: 1)
                                            }
                                        }
                                }
                                .buttonStyle(.philotesInteractive)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        SectionEyebrow(title: "颜色")
                        HStack(spacing: 10) {
                            ForEach(accents, id: \.self) { accent in
                                Button {
                                    selectedAccent = accent
                                } label: {
                                    Circle()
                                        .fill(color(for: accent))
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            if selectedAccent == accent {
                                                Circle()
                                                    .stroke(.white, lineWidth: 2)
                                                    .padding(3)
                                            }
                                        }
                                }
                                .buttonStyle(.philotesInteractive)
                            }
                        }
                    }

                    AgentAPIConfigurationEditor(
                        model: model,
                        provider: $apiProvider,
                        baseURL: $apiBaseURL,
                        modelName: $apiModel,
                        apiKeyInput: $apiKeyInput,
                        clearStoredAPIKey: $clearStoredAPIKey,
                        existingAgentID: agent.id
                    )
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 480)

            if !actionErrorMessage.isEmpty {
                Text(L10n.string(actionErrorMessage))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.coral)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Button("取消") {
                    close()
                }
                .buttonStyle(.philotesInteractive)
                .foregroundStyle(PhilotesTheme.secondaryText)

                Button {
                    if model.updateAgentSettings(
                        agent,
                        emoji: selectedEmoji,
                        accent: selectedAccent,
                        apiProvider: apiProvider,
                        apiBaseURL: apiBaseURL,
                        apiModel: apiModel,
                        apiKeyInput: apiKeyInput,
                        clearStoredAPIKey: clearStoredAPIKey,
                        avatarImageURL: avatarSourceURL,
                        removeAvatarImage: removeAvatarImage
                    ) {
                        close()
                    } else {
                        actionErrorMessage = model.errorMessage ?? "智能体设定保存失败。"
                    }
                } label: {
                    Text("保存")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(PhilotesTheme.primaryText, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.philotesInteractive)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(PhilotesTheme.sidebar)
        .preferredColorScheme(.dark)
    }

    private var selectedColor: Color {
        color(for: selectedAccent)
    }

    private func close() {
        onClose()
        dismiss()
    }

    private func color(for accent: String) -> Color {
        switch accent {
        case "lavender": PhilotesTheme.lavender
        case "mint": PhilotesTheme.mint
        case "coral": PhilotesTheme.coral
        default: PhilotesTheme.blue
        }
    }
}

private struct LabeledField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: title)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }
        }
    }
}

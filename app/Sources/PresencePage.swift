import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AccountPage: View {
    @ObservedObject var model: AppModel
    @State private var isEditingProfile = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "ACCOUNT",
                title: "账户",
                subtitle: "查看我的账户和使用情况"
            ) {
                Button {
                    isEditingProfile = true
                } label: {
                    Label("编辑资料", systemImage: "pencil")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            PhilotesTheme.surface,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(PhilotesTheme.border, lineWidth: 1)
                        }
                    }
                .buttonStyle(.philotesInteractive)
                .accessibilityIdentifier("account.editProfile")
            }

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    accountHero
                    usageGrid
                    serverAccountCard
                    agentsCard
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .frame(maxWidth: 1_080, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PhilotesTheme.canvas)
        .sheet(isPresented: $isEditingProfile) {
            ProfileSettingsSheet(model: model)
        }
    }

    private var accountHero: some View {
        HStack(spacing: 24) {
            UserAvatarView(
                imagePath: model.userAvatarPath,
                size: 82
            )
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(
                color: PhilotesTheme.lavender.opacity(0.18),
                radius: 16
            )

            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(title: "本地账户")
                Text(model.userNickname)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                HStack(spacing: 8) {
                    StatusDot(
                        color: model.errorMessage == nil
                            ? PhilotesTheme.mint
                            : PhilotesTheme.coral
                    )
                    Text(
                        model.errorMessage == nil
                            ? "本地数据已连接"
                            : "本地数据需要检查"
                    )
                    Text("·")
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                    Text("账户服务尚未连接")
                }
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.secondaryText)

            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("本机")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                Text(L10n.string(model.status))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    PhilotesTheme.lavender.opacity(0.09),
                    PhilotesTheme.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private var usageGrid: some View {
        HStack(spacing: 14) {
            accountMetric(
                icon: "arrow.up.right",
                value: "\(model.requestCount)",
                title: "模型请求",
                detail: "本机累计"
            )
            accountMetric(
                icon: "person.2",
                value: "\(model.agents.count)",
                title: "智能体",
                detail: "当前宇宙"
            )
            accountMetric(
                icon: "sparkles",
                value: "\(model.memories.count)",
                title: "记忆节点",
                detail: "本地数据库"
            )
        }
    }

    private func accountMetric(
        icon: String,
        value: String,
        title: String,
        detail: String
    ) -> some View {
        PhilotesCard(padding: 18) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PhilotesTheme.blue)
                    .frame(width: 34, height: 34)
                    .background(
                        PhilotesTheme.blue.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(
                            .system(
                                size: 20,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(L10n.string(title))
                        .font(
                            .system(
                                size: 10,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.secondaryText)
                    Text(L10n.string(detail))
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
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var serverAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("账户信息")
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("连接服务端后显示真实的账户与同步数据。")
                        .font(
                            .system(
                                size: 9,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                Spacer()
                Text("待连接")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(PhilotesTheme.surfaceRaised, in: Capsule())
            }

            VStack(spacing: 0) {
                accountPlaceholderRow(
                    icon: "person.text.rectangle",
                    title: "显示名称",
                    value: "等待登录"
                )
                Divider().overlay(PhilotesTheme.border)
                accountPlaceholderRow(
                    icon: "envelope",
                    title: "邮箱",
                    value: "等待登录"
                )
                Divider().overlay(PhilotesTheme.border)
                accountPlaceholderRow(
                    icon: "number",
                    title: "账户编号",
                    value: "等待服务端"
                )
                Divider().overlay(PhilotesTheme.border)
                accountPlaceholderRow(
                    icon: "icloud",
                    title: "云端同步",
                    value: "尚未启用"
                )
            }
            .background(
                PhilotesTheme.surfaceRaised.opacity(0.46),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
        }
        .padding(20)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private func accountPlaceholderRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    PhilotesTheme.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            Text(L10n.string(title))
                .font(
                    .system(
                        size: 11,
                        weight: .medium,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.secondaryText)
            Spacer()
            Text(value)
                .font(
                    .system(
                        size: 9,
                        weight: .regular,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.tertiaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var agentsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("我的智能体")
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(
                        L10n.format(
                            "%lld 个本地智能体；头像与名称会同步到账户界面。",
                            Int64(model.agents.count)
                        )
                    )
                        .font(
                            .system(
                                size: 9,
                                weight: .regular,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                Spacer()
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(model.agents) { agent in
                    Button {
                        model.setActiveAgent(agent)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(agent.accentColor.opacity(0.13))
                                    .frame(width: 42, height: 42)
                                AgentGlyph(
                                    emoji: agent.emoji,
                                    size: 18,
                                    imagePath: agent.avatarImagePath
                                )
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.name)
                                    .font(
                                        .system(
                                            size: 12,
                                            weight: .semibold,
                                            design: .rounded
                                        )
                                    )
                                    .foregroundStyle(PhilotesTheme.primaryText)
                                Text(agent.role)
                                    .font(
                                        .system(
                                            size: 9,
                                            weight: .regular,
                                            design: .rounded
                                        )
                                    )
                                    .foregroundStyle(PhilotesTheme.tertiaryText)
                            }

                            Spacer()

                            if model.activeAgentID == agent.id {
                                Circle()
                                    .fill(PhilotesTheme.mint)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(12)
                        .background(
                            agent.accentColor.opacity(
                                model.activeAgentID == agent.id ? 0.08 : 0.035
                            ),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(
                                    model.activeAgentID == agent.id
                                        ? agent.accentColor.opacity(0.25)
                                        : PhilotesTheme.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.philotesInteractive)
                }
            }
        }
        .padding(20)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }
}

private struct ProfileSettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var selectedAvatarData: Data?
    @State private var selectedAvatarImage: NSImage?
    @State private var removeExistingAvatar = false
    @State private var isChoosingAvatar = false
    @State private var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        _nickname = State(initialValue: model.userNickname)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow(title: "PERSONAL PROFILE")
                    Text("个人资料")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("设置本机账户使用的头像和昵称。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
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
            .padding(24)

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    avatarEditor

                    VStack(alignment: .leading, spacing: 8) {
                        Text("昵称")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PhilotesTheme.secondaryText)

                        TextField("输入昵称", text: $nickname)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PhilotesTheme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(
                                PhilotesTheme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(PhilotesTheme.border, lineWidth: 1)
                            }

                        Text("最多 40 个字符；留空时会使用“主人”。")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }
                    .padding(18)
                    .background(
                        PhilotesTheme.surface,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(PhilotesTheme.border, lineWidth: 1)
                    }

                    if let errorMessage {
                        Text(L10n.string(errorMessage))
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.coral)
                    }
                }
                .padding(24)
            }

            Divider()
                .overlay(PhilotesTheme.border)

            HStack(spacing: 10) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.philotesInteractive)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 34)

                Button("保存资料") {
                    save()
                }
                .buttonStyle(.philotesInteractive)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(PhilotesTheme.primaryText, in: Capsule())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 500)
        .background(PhilotesTheme.canvas)
        .fileImporter(
            isPresented: $isChoosingAvatar,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleAvatarSelection(result)
        }
    }

    private var avatarEditor: some View {
        HStack(spacing: 22) {
            ZStack {
                if let selectedAvatarImage {
                    Image(nsImage: selectedAvatarImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    UserAvatarView(
                        imagePath: removeExistingAvatar
                            ? nil
                            : model.userAvatarPath,
                        size: 88
                    )
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(
                color: PhilotesTheme.lavender.opacity(0.16),
                radius: 14
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("头像")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)

                HStack(spacing: 8) {
                    Button("选择图片") {
                        isChoosingAvatar = true
                    }
                    .buttonStyle(.philotesInteractive)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.blue)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(
                        PhilotesTheme.blue.opacity(0.10),
                        in: Capsule()
                    )

                    if hasVisibleAvatar {
                        Button("移除头像") {
                            selectedAvatarData = nil
                            selectedAvatarImage = nil
                            removeExistingAvatar = true
                            errorMessage = nil
                        }
                        .buttonStyle(.philotesInteractive)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.coral)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            PhilotesTheme.coral.opacity(0.08),
                            in: Capsule()
                        )
                    }
                }

                Text("支持 PNG、JPEG、HEIC 和 WebP，保存时会统一压缩。")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            Spacer()
        }
        .padding(18)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private var hasVisibleAvatar: Bool {
        selectedAvatarImage != nil
            || (!removeExistingAvatar && model.userAvatarPath != nil)
    }

    private func handleAvatarSelection(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else {
                throw AvatarStoreError.invalidImage
            }
            selectedAvatarData = data
            selectedAvatarImage = image
            removeExistingAvatar = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let cleanNickname = nickname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let resolvedNickname = cleanNickname.isEmpty
            ? UserProfileStore.defaultNickname
            : cleanNickname

        if let selectedAvatarData {
            guard model.updateUserAvatar(from: selectedAvatarData) else {
                errorMessage = model.errorMessage ?? "用户头像保存失败。"
                return
            }
        } else if removeExistingAvatar {
            model.removeUserAvatar()
        }

        _ = model.updateUserNickname(resolvedNickname)
        dismiss()
    }
}

import AppKit
import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("proactiveMemoryEnabled") private var proactiveMemoryEnabled = true
    @AppStorage("quietPresenceEnabled") private var quietPresenceEnabled = true
    @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false
    @AppStorage(MacControlPreferences.enabledKey) private var macControlEnabled = true
    @AppStorage(MacControlPreferences.advancedEnabledKey) private var advancedMacControlEnabled = false
    @AppStorage(MacControlPreferences.autoApproveKey) private var autoApproveMacActions = false
    @AppStorage(PhilotesLanguage.storageKey)
    private var languageCode = PhilotesLanguage.simplifiedChinese.rawValue
    @State private var permissionRefreshToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "PREFERENCES",
                title: "设置",
                subtitle: "决定 Philotes 如何靠近，以及哪些事情永远不被擅自越过。"
            )

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    companionship
                    language
                    appearance
                    privacy

                    VStack(spacing: 7) {
                        HStack {
                            Text(versionDisplay)
                            Spacer()
                            Text("Made for macOS")
                        }
                    }
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .padding(.horizontal, 4)

                    CreatorCreditsSection()
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .frame(maxWidth: 820, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PhilotesTheme.canvas)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            permissionRefreshToken = UUID()
        }
    }

    private var versionDisplay: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.1"
        return "Philotes \(version) Release"
    }

    private var companionship: some View {
        SettingsGroup(
            title: "陪伴方式",
            description: L10n.format(
                "调整%@靠近你的方式。",
                model.activeAgent?.name ?? L10n.string("智能体")
            )
        ) {
            SettingsToggleRow(
                icon: "sparkles",
                title: "允许自然闪回",
                detail: "在当前话题确实相关时，一天最多主动想起一件小事。",
                isOn: $proactiveMemoryEnabled
            )

            SettingsDivider()

            SettingsToggleRow(
                icon: "moon.stars",
                title: "安静陪伴",
                detail: "没有合适理由时保持安静，不为了刷存在感而说话。",
                isOn: $quietPresenceEnabled
            )

            SettingsDivider()

            SettingsValueRow(
                icon: "clock",
                title: "主动消息频率",
                detail: "自然闪回每天最多 1 次。"
            ) {
                Text("克制")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PhilotesTheme.surfaceRaised, in: Capsule())
            }
        }
    }

    private var appearance: some View {
        SettingsGroup(
            title: "外观",
            description: "调整界面与动态效果。"
        ) {
            SettingsValueRow(
                icon: "circle.lefthalf.filled",
                title: "外观",
                detail: "当前使用深色外观。"
            ) {
                Text("深色")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }

            SettingsDivider()

            SettingsToggleRow(
                icon: "figure.mind.and.body",
                title: "减少动态效果",
                detail: "收住呼吸光晕和转场动画，保留必要的状态反馈。",
                isOn: $reduceMotionEnabled
            )
        }
    }

    private var language: some View {
        SettingsGroup(
            title: L10n.string("界面语言"),
            description: L10n.string("切换后会立即应用到所有界面；用户内容和智能体名字保持原文。")
        ) {
            SettingsValueRow(
                icon: "globe",
                title: L10n.string("语言"),
                detail: L10n.string("选择 Philotes 的显示语言。")
            ) {
                Picker(
                    "",
                    selection: $languageCode
                ) {
                    ForEach(PhilotesLanguage.allCases) { language in
                        Text(language.autonym)
                            .tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }

    private var privacy: some View {
        SettingsGroup(
            title: "数据与隐私",
            description: "对话与记忆保存在这台 Mac 上。"
        ) {
            SettingsToggleRow(
                icon: "cursorarrow.rays",
                title: "Mac 操作请求",
                detail: "允许智能体提出打开应用或网页；默认逐次确认，也可在一键授权后自动执行。",
                isOn: $macControlEnabled
            )

            SettingsDivider()

            SettingsToggleRow(
                icon: "exclamationmark.shield",
                title: "完整 Mac 操作能力",
                detail: "把 AppleScript、键鼠、屏幕快照与 OCR 全部提供给智能体；默认逐批确认。",
                isOn: advancedControlBinding
            )
            .disabled(!macControlEnabled)

            SettingsDivider()

            SettingsToggleRow(
                icon: "lock.open",
                title: "自动执行 Mac 动作",
                detail: "开启后，智能体提出的动作不再逐批弹确认；系统权限仍由 macOS 管理。",
                isOn: $autoApproveMacActions
            )
            .disabled(!macControlEnabled || !advancedMacControlEnabled)

            SettingsDivider()

            SettingsValueRow(
                icon: "key.horizontal",
                title: "一键授权",
                detail: "开启完整能力与自动执行，并立即请求辅助功能、键鼠事件和屏幕录制权限。"
            ) {
                permissionButton("一键授权") {
                    macControlEnabled = true
                    advancedMacControlEnabled = true
                    autoApproveMacActions = true
                    MacSystemPermission.requestAllAdvancedAccess()
                    permissionRefreshToken = UUID()
                }
            }

            SettingsDivider()

            SettingsValueRow(
                icon: "hand.raised",
                title: "系统权限",
                detail: "第一次使用对应高级动作时，macOS 会弹窗请求权限；也可以在这里直接触发请求并打开设置。"
            ) {
                HStack(spacing: 7) {
                    permissionButton("辅助功能") {
                        MacSystemPermission.requestAccessibilityAndOpenSettings()
                        permissionRefreshToken = UUID()
                    }
                    permissionButton("屏幕录制") {
                        MacSystemPermission.requestScreenRecordingAndOpenSettings()
                        permissionRefreshToken = UUID()
                    }
                }
            }
            .disabled(!advancedMacControlEnabled)

            SettingsDivider()

            SettingsValueRow(
                icon: "checkmark.shield",
                title: "当前权限状态",
                detail: "状态来自 macOS 的实时权限预检；如果显示未授权，请重新触发请求并在系统设置中开启。"
            ) {
                HStack(spacing: 6) {
                    permissionBadge(
                        "键鼠",
                        granted: MacSystemPermission.hasAccessibilityAccess
                            && MacSystemPermission.hasEventPostingAccess
                    )
                    permissionBadge(
                        "屏幕",
                        granted: MacSystemPermission.hasScreenRecordingAccess
                    )
                }
            }
            .id(permissionRefreshToken)
            .disabled(!advancedMacControlEnabled)

            SettingsDivider()

            SettingsValueRow(
                icon: "internaldrive",
                title: "本地记忆库",
                detail: model.databasePath.isEmpty ? "正在准备 SQLite 数据库" : model.databasePath
            ) {
                Button("在 Finder 中显示") {
                    let url = URL(fileURLWithPath: model.databasePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .buttonStyle(.philotesInteractive)
                .foregroundStyle(PhilotesTheme.blue)
                .disabled(model.databasePath.isEmpty)
            }

            SettingsDivider()

            SettingsValueRow(
                icon: "books.vertical",
                title: "智能体心智库",
                detail: "每个智能体都有独立的 Obsidian 风格 Markdown 人格、记忆和时间线。"
            ) {
                Button("打开心智库") {
                    let url = AgentMemoryVaultStore.rootDirectoryURL()
                    try? FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(url)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .buttonStyle(.philotesInteractive)
                .foregroundStyle(PhilotesTheme.blue)
            }

            SettingsDivider()

            SettingsValueRow(
                icon: "lock.shield",
                title: "敏感旧事",
                detail: "不会主动出现；只在你明确提起时参与当前上下文。"
            ) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.mint)
            }

        }
    }

    private func permissionButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(L10n.string(title), action: action)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .buttonStyle(.philotesInteractive)
            .foregroundStyle(PhilotesTheme.blue)
    }

    private func permissionBadge(
        _ title: String,
        granted: Bool
    ) -> some View {
        Text(
            L10n.format(
                "%@：%@",
                L10n.string(title),
                L10n.string(granted ? "已授权" : "未授权")
            )
        )
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(
                granted ? PhilotesTheme.mint : PhilotesTheme.coral
            )
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                (granted ? PhilotesTheme.mint : PhilotesTheme.coral)
                    .opacity(0.10),
                in: Capsule()
            )
    }

    private var advancedControlBinding: Binding<Bool> {
        Binding(
            get: { advancedMacControlEnabled },
            set: { enabled in
                advancedMacControlEnabled = enabled
                if enabled {
                    MacSystemPermission.requestAllAdvancedAccess()
                    permissionRefreshToken = UUID()
                }
            }
        )
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(title))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(L10n.string(description))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowLayout(icon: icon, title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(PhilotesTheme.blue)
                .controlSize(.small)
        }
    }
}

private struct SettingsValueRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        SettingsRowLayout(icon: icon, title: title, detail: detail) {
            trailing
        }
    }
}

private struct SettingsRowLayout<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .frame(width: 32, height: 32)
                .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(L10n.string(detail))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(PhilotesTheme.border)
            .frame(height: 1)
            .padding(.leading, 62)
    }
}

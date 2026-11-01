import SwiftUI

struct AgentAPIConfigurationEditor: View {
    @ObservedObject var model: AppModel
    @Binding var provider: AgentAPIProvider
    @Binding var baseURL: String
    @Binding var modelName: String
    @Binding var apiKeyInput: String
    @Binding var clearStoredAPIKey: Bool
    let existingAgentID: Int64?

    @State private var hasStoredAPIKey = false
    @State private var isTesting = false
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow(title: "模型连接")
                    Text(provider.detail)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Picker("", selection: $provider) {
                    ForEach(AgentAPIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            if provider != .none {
                SettingsDivider()

                APIInputRow(
                    icon: "link",
                    title: "API 地址",
                    hint: provider == .deepseek
                        ? "已预置 DeepSeek，也可以换成代理地址"
                        : "基础地址或完整 /chat/completions 地址"
                ) {
                    TextField(
                        provider.defaultBaseURL.isEmpty
                            ? "https://api.example.com/v1"
                            : provider.defaultBaseURL,
                        text: $baseURL
                    )
                }

                SettingsDivider()

                APIInputRow(
                    icon: "cpu",
                    title: "模型",
                    hint: provider == .deepseek
                        ? "例如 deepseek-chat 或 deepseek-reasoner"
                        : "由 API 提供方定义"
                ) {
                    TextField(
                        provider.defaultModel.isEmpty
                            ? "模型名称"
                            : provider.defaultModel,
                        text: $modelName
                    )
                }

                SettingsDivider()

                APIInputRow(
                    icon: "key.horizontal",
                    title: "API Key",
                    hint: hasStoredAPIKey
                        ? "已保存到这个智能体；留空则保持不变"
                        : "只写入 macOS 钥匙串，可留空连接匿名接口"
                ) {
                    SecureField(
                        hasStoredAPIKey ? "已保存" : "可留空",
                        text: $apiKeyInput
                    )
                    .onChange(of: apiKeyInput) { _, newValue in
                        if !newValue.isEmpty {
                            clearStoredAPIKey = false
                        }
                    }
                }

                HStack(spacing: 9) {
                    if !statusMessage.isEmpty {
                        HStack(spacing: 6) {
                            StatusDot(
                                color: statusIsError
                                    ? PhilotesTheme.coral
                                    : PhilotesTheme.mint
                            )
                            Text(L10n.string(statusMessage))
                                .lineLimit(2)
                        }
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                    }

                    Spacer()

                    if hasStoredAPIKey || !apiKeyInput.isEmpty {
                        Button("清除密钥") {
                            clearAPIKey()
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                        .buttonStyle(.philotesInteractive)
                    }

                    Button {
                        Task {
                            await testConnection()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(isTesting ? "测试中…" : "测试连接")
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.philotesInteractive)
                    .disabled(isTesting || !canTest)
                }
            } else {
                Text("这个智能体暂时不能发起远程对话；之后可以在设定里补上。")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
        }
        .padding(16)
        .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
        .onAppear {
            refreshStoredKeyState()
        }
        .onChange(of: provider) { _, newProvider in
            applyProviderDefaults(for: newProvider)
            statusMessage = ""
            statusIsError = false
        }
    }

    private var canTest: Bool {
        guard provider != .none else { return false }
        let resolvedBaseURL = baseURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let resolvedModel = modelName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return (!resolvedBaseURL.isEmpty || !provider.defaultBaseURL.isEmpty)
            && (!resolvedModel.isEmpty || !provider.defaultModel.isEmpty)
    }

    private func applyProviderDefaults(for provider: AgentAPIProvider) {
        switch provider {
        case .deepseek:
            baseURL = provider.defaultBaseURL
            modelName = provider.defaultModel
        case .custom:
            if baseURL == AgentAPIProvider.deepseek.defaultBaseURL {
                baseURL = ""
            }
            if modelName == AgentAPIProvider.deepseek.defaultModel {
                modelName = ""
            }
        case .none:
            break
        }
    }

    private func refreshStoredKeyState() {
        guard let existingAgentID else {
            hasStoredAPIKey = false
            return
        }
        hasStoredAPIKey = !clearStoredAPIKey
            && model.hasStoredAPIKey(for: existingAgentID)
    }

    private func testConnection() async {
        isTesting = true
        statusMessage = "正在连接 API…"
        statusIsError = false
        do {
            let reply = try await model.testAPIConnection(
                provider: provider,
                baseURL: baseURL,
                model: modelName,
                apiKeyInput: apiKeyInput,
                existingAgentID: existingAgentID
            )
            let cleanReply = reply
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            statusMessage = cleanReply.isEmpty
                ? "连接成功"
                : "连接成功 · \(String(cleanReply.prefix(64)))"
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        isTesting = false
    }

    private func clearAPIKey() {
        apiKeyInput = ""
        clearStoredAPIKey = existingAgentID != nil
        hasStoredAPIKey = false
        statusMessage = existingAgentID == nil
            ? "已清空输入的密钥"
            : "保存后会从这个智能体的钥匙串记录中移除密钥"
        statusIsError = false
    }
}

private struct APIInputRow<Field: View>: View {
    let icon: String
    let title: String
    let hint: String
    @ViewBuilder let field: Field

    init(
        icon: String,
        title: String,
        hint: String,
        @ViewBuilder field: () -> Field
    ) {
        self.icon = icon
        self.title = title
        self.hint = hint
        self.field = field()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    PhilotesTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 9)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string(title))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)

                field
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(
                        PhilotesTheme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(PhilotesTheme.border, lineWidth: 1)
                    }

                Text(hint)
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
        }
    }
}

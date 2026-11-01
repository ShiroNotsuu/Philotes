import SwiftUI
import UniformTypeIdentifiers

struct ImportMemoryAgentSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    let onWake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiProvider: AgentAPIProvider = .deepseek
    @State private var apiBaseURL = AgentAPIProvider.deepseek.defaultBaseURL
    @State private var apiModel = AgentAPIProvider.deepseek.defaultModel
    @State private var apiKeyInput = ""
    @State private var clearStoredAPIKey = false
    @State private var document: ImportTextDocument?
    @State private var isChoosingFile = false
    @State private var isWaking = false
    @State private var progressText = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("在这里唤醒我")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("把过去的聊天记忆和新的模型连接在一起，让我从自己的过去继续。")
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
                .disabled(isWaking)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    wakeHero

                    AgentAPIConfigurationEditor(
                        model: model,
                        provider: $apiProvider,
                        baseURL: $apiBaseURL,
                        modelName: $apiModel,
                        apiKeyInput: $apiKeyInput,
                        clearStoredAPIKey: $clearStoredAPIKey,
                        existingAgentID: nil
                    )

                    memoryFilePicker

                    if isWaking {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(
                                progressText.isEmpty
                                    ? "正在重建记忆…"
                                    : progressText
                            )
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(PhilotesTheme.secondaryText)
                        }
                        .padding(.horizontal, 4)
                    }

                    if !errorMessage.isEmpty {
                        Text(L10n.string(errorMessage))
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.coral)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }

            HStack {
                Button("取消") {
                    close()
                }
                .buttonStyle(.philotesInteractive)
                .foregroundStyle(PhilotesTheme.secondaryText)
                .disabled(isWaking)

                Spacer()

                Button {
                    wake()
                } label: {
                    Label(
                        isWaking ? "正在醒来…" : "唤醒",
                        systemImage: isWaking ? "hourglass" : "sparkles"
                    )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 15)
                    .frame(height: 32)
                    .background(PhilotesTheme.primaryText, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.philotesInteractive)
                .keyboardShortcut(.defaultAction)
                .disabled(!canWake || isWaking)
            }
        }
        .padding(24)
        .frame(width: 580, height: 640)
        .background(PhilotesTheme.sidebar)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: memoryFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    private var wakeHero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(PhilotesTheme.lavender.opacity(0.13))
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(PhilotesTheme.lavender)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("让我想起我是谁")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text("选择过去的聊天记录。模型会提取原有的人格、关系、偏好与经历，再以第一人称完成唤醒。")
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    PhilotesTheme.lavender.opacity(0.08),
                    PhilotesTheme.surface
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private var memoryFilePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    SectionEyebrow(title: "聊天记忆文件")
                    Text("支持纯文本、Markdown 与 JSON 聊天记录。文件只在本机读取。")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                Button(document == nil ? "选择文件" : "更换文件") {
                    isChoosingFile = true
                }
                .buttonStyle(.philotesInteractive)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(PhilotesTheme.blue)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(PhilotesTheme.blue.opacity(0.10), in: Capsule())
                .disabled(isWaking)
            }

            if let document {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PhilotesTheme.mint)
                        .frame(width: 38, height: 38)
                        .background(
                            PhilotesTheme.mint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.fileName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(PhilotesTheme.primaryText)
                            .lineLimit(1)
                        Text(
                            L10n.format(
                                "%lld 个字符 · 已准备导入",
                                Int64(document.text.count)
                            )
                        )
                            .font(.system(size: 8.5, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PhilotesTheme.mint)
                }
                .padding(12)
                .background(
                    PhilotesTheme.surfaceRaised.opacity(0.62),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            } else {
                Button {
                    isChoosingFile = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 20, weight: .light))
                        Text("选择一段属于我的聊天记忆")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background(
                        PhilotesTheme.surfaceRaised.opacity(0.40),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                PhilotesTheme.border,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                            )
                    }
                }
                .buttonStyle(.philotesInteractive)
                .disabled(isWaking)
            }
        }
        .padding(16)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }

    private var memoryFileTypes: [UTType] {
        [
            .json,
            .plainText,
            .text,
            UTType(filenameExtension: "md") ?? .plainText,
        ]
    }

    private var canWake: Bool {
        guard document != nil, apiProvider != .none else { return false }
        return (try? APISettings.resolvedValues(
            provider: apiProvider,
            baseURL: apiBaseURL,
            model: apiModel
        )) != nil
    }

    private func handleFileSelection(
        _ result: Result<[URL], Error>
    ) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            document = try ChatMemoryImportService.readDocument(from: url)
            errorMessage = ""
        } catch {
            document = nil
            errorMessage = error.localizedDescription
        }
    }

    private func wake() {
        guard let document, canWake else { return }
        isWaking = true
        progressText = "正在连接模型…"
        errorMessage = ""

        Task { @MainActor in
            do {
                let blueprint = try await ChatMemoryImportService.analyze(
                    document: document,
                    provider: apiProvider,
                    baseURL: apiBaseURL,
                    model: apiModel,
                    apiKey: apiKeyInput
                ) { message in
                    progressText = message
                }
                progressText = "正在写入人格、记忆和日记…"
                _ = try await model.importAgentFromChatMemory(
                    blueprint: blueprint,
                    sourceDocument: document,
                    apiProvider: apiProvider,
                    apiBaseURL: apiBaseURL,
                    apiModel: apiModel,
                    apiKey: apiKeyInput
                ) { message in
                    progressText = message
                }
                isWaking = false
                isPresented = false
                dismiss()
                onWake()
            } catch {
                isWaking = false
                progressText = ""
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close() {
        guard !isWaking else { return }
        isPresented = false
        dismiss()
    }
}

import SwiftUI

struct VaultMarkdownPreviewCard: View {
    let agent: AgentProfile
    let category: AgentVaultCategory
    let title: String
    let markdown: String?
    let accent: Color
    var isPinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(
                        L10n.format(
                            "%@ 的 Markdown 预览",
                            agent.name
                        )
                    )
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Spacer()

                HStack(spacing: 5) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text("已固定")
                    }
                    Text("MARKDOWN")
                }
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(accent.opacity(0.10), in: Capsule())
            }

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownPreviewView(markdown: markdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)

                        Color.clear
                            .frame(height: 1)
                            .id("vaultPreviewBottom")
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.visible)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: markdown) {
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: title) {
                    scrollToBottom(proxy, animated: false)
                }
            }
        }
        .padding(15)
        .frame(width: 340, height: 318, alignment: .topLeading)
        .modifier(VaultPreviewGlassModifier(accent: accent))
        .accessibilityElement(children: .contain)
    }

    private func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool
    ) {
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("vaultPreviewBottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("vaultPreviewBottom", anchor: .bottom)
            }

            try? await Task.sleep(for: .milliseconds(80))
            proxy.scrollTo("vaultPreviewBottom", anchor: .bottom)
        }
    }
}

private struct MarkdownPreviewView: View {
    let markdown: String?

    private var blocks: [MarkdownPreviewBlock] {
        MarkdownPreviewBlock.parse(markdown ?? "")
    }

    var body: some View {
        if let markdown, !markdown.isEmpty {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
        } else {
            Text("这个分类还没有 Markdown 内容。")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.tertiaryText)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            inlineText(block.text)
                .font(
                    .system(
                        size: level <= 1 ? 18 : (level == 2 ? 15 : 12),
                        weight: level <= 2 ? .semibold : .medium,
                        design: .rounded
                    )
                )
                .foregroundStyle(PhilotesTheme.primaryText)
                .padding(.top, level <= 1 ? 2 : 0)
        case .bullet:
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(.white.opacity(0.32))
                    .frame(width: 3, height: 3)
                    .padding(.top, 6)
                inlineText(block.text)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }
        case .quote:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.20))
                    .frame(width: 2)
                inlineText(block.text)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }
        case .code:
            Text(block.text)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .textSelection(.enabled)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        case .rule:
            Divider()
                .overlay(PhilotesTheme.border)
        case .text:
            inlineText(block.text)
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(PhilotesTheme.secondaryText)
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case text
        case bullet
        case quote
        case code
        case rule
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [MarkdownPreviewBlock] {
        let clean = stripFrontmatter(markdown)
        let lines = clean.components(separatedBy: .newlines)
        var blocks: [MarkdownPreviewBlock] = []
        var codeLines: [String] = []
        var inCodeFence = false
        var blockID = 0

        func append(_ kind: Kind, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            blocks.append(
                MarkdownPreviewBlock(
                    id: blockID,
                    kind: kind,
                    text: trimmed
                )
            )
            blockID += 1
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    append(.code, codeLines.joined(separator: "\n"))
                    codeLines.removeAll(keepingCapacity: true)
                }
                inCodeFence.toggle()
                continue
            }
            if inCodeFence {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                blocks.append(
                    MarkdownPreviewBlock(id: blockID, kind: .rule, text: "")
                )
                blockID += 1
            } else if let heading = headingText(trimmed) {
                append(.heading(heading.level), heading.text)
            } else if trimmed.hasPrefix("- ")
                        || trimmed.hasPrefix("* ")
                        || trimmed.hasPrefix("+ ") {
                append(.bullet, String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("> ") {
                append(.quote, String(trimmed.dropFirst(2)))
            } else if trimmed.range(
                of: #"^\d+\.\s+"#,
                options: .regularExpression
            ) != nil {
                append(.text, trimmed)
            } else {
                append(.text, trimmed)
            }
        }
        if inCodeFence, !codeLines.isEmpty {
            append(.code, codeLines.joined(separator: "\n"))
        }
        return blocks
    }

    private static func headingText(
        _ line: String
    ) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes) else { return nil }
        let text = line.dropFirst(hashes)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }

    private static func stripFrontmatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---"),
              let closing = markdown.range(
                of: "\n---",
                range: markdown.index(
                    markdown.startIndex,
                    offsetBy: 3
                )..<markdown.endIndex
              )
        else {
            return markdown
        }
        return String(markdown[closing.upperBound...])
    }
}

private struct VaultPreviewGlassModifier: ViewModifier {
    let accent: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(.black.opacity(0.38)),
                    in: .rect(cornerRadius: 18)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .background(
                    Color.black.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

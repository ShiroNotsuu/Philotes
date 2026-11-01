import SwiftUI

struct MemoryPage: View {
    @ObservedObject var model: AppModel
    @State private var pendingForget: MemoryNode?
    @State private var showingForgetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "LOCAL MEMORY",
                title: "记忆",
                subtitle: "每一条记忆都有来源，也可以被真正忘掉。"
            ) {
                HStack(spacing: 8) {
                    ToolbarIconButton(systemName: "magnifyingglass", label: "搜索记忆")
                    ToolbarIconButton(systemName: "plus", label: "添加记忆")
                }
            }

            Divider()
                .overlay(PhilotesTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overview
                    memoryList
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 26)
                .frame(maxWidth: 1_080, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PhilotesTheme.canvas)
        .confirmationDialog(
            "忘记「\(pendingForget?.title ?? "这条记忆")」？",
            isPresented: $showingForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("彻底忘记", role: .destructive) {
                if let pendingForget {
                    model.forgetMemory(pendingForget)
                }
                pendingForget = nil
            }
            Button("取消", role: .cancel) {
                pendingForget = nil
            }
        } message: {
            Text("这会把内容从本地数据库和后续检索中删除，不能撤销。")
        }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionEyebrow(title: "记忆星图")
                        Text("节点之间的距离代表关联，而不是亲密度。")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }

                    Spacer()

                    Text(
                        L10n.format(
                            "%lld 个节点",
                            Int64(model.memories.count)
                        )
                    )
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PhilotesTheme.surfaceRaised, in: Capsule())
                }

                MemoryStarMap(memories: model.memories)
                    .frame(minHeight: 300)
            }
            .padding(20)
            .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }

            VStack(spacing: 12) {
                MemoryMetricCard(
                    icon: "circle.hexagongrid",
                    eyebrow: "当前",
                    value: "\(model.memories.count)",
                    detail: "条可检索记忆"
                )

                MemoryMetricCard(
                    icon: "lock.shield",
                    eyebrow: "存储",
                    value: "本机",
                    detail: "SQLite 与后续本地索引"
                )

                MemoryMetricCard(
                    icon: "hand.raised",
                    eyebrow: "控制",
                    value: "可遗忘",
                    detail: "删除时同步移出检索"
                )
            }
            .frame(width: 210)
        }
        .frame(height: 360)
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("它记得的事")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("点开左侧星图节点或右侧菜单，可以管理这份记忆。")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                Spacer()
                Text("按时间")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.memories.enumerated()), id: \.element.id) { index, memory in
                    MemoryRow(memory: memory) {
                        pendingForget = memory
                        showingForgetConfirmation = true
                    }

                    if index < model.memories.count - 1 {
                        Rectangle()
                            .fill(PhilotesTheme.border)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }

                if model.memories.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .light))
                        Text("还没有记忆")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("从一场对话开始，值得留下的事会出现在这里。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                }
            }
            .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
        }
    }
}

private struct MemoryStarMap: View {
    let memories: [MemoryNode]

    var body: some View {
        GeometryReader { proxy in
            let points = mapPoints(in: proxy.size)

            ZStack {
                Canvas { context, size in
                    for index in 0..<28 {
                        let x = normalized(index * 37, modulus: 101) * size.width
                        let y = normalized(index * 61 + 13, modulus: 97) * size.height
                        let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.18 : 0.08))
                        )
                    }

                    guard !points.isEmpty else { return }
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)

                    for point in points {
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point.position)
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.10)),
                            lineWidth: 1
                        )
                    }

                    let centerRect = CGRect(
                        x: center.x - 8,
                        y: center.y - 8,
                        width: 16,
                        height: 16
                    )
                    context.fill(
                        Path(ellipseIn: centerRect),
                        with: .color(PhilotesTheme.blue)
                    )
                }

                if points.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 24, weight: .light))
                        Text("等待第一颗记忆星")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                } else {
                    Text("此刻")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.blue)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height / 2 - 18
                        )

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(color(for: point.memory.kind))
                                .frame(width: 7, height: 7)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.5), lineWidth: 0.5)
                                }

                            Text(point.memory.title)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(PhilotesTheme.secondaryText)
                                .lineLimit(1)
                                .frame(maxWidth: 92)
                        }
                        .position(point.position)
                    }
                }
            }
        }
        .background(
            RadialGradient(
                colors: [
                    PhilotesTheme.blue.opacity(0.055),
                    Color.clear
                ],
                center: .center,
                startRadius: 5,
                endRadius: 220
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func mapPoints(in size: CGSize) -> [(memory: MemoryNode, position: CGPoint)] {
        guard !memories.isEmpty else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shortestSide = min(size.width, size.height)

        return memories.enumerated().map { index, memory in
            let angle = -Double.pi / 2
                + (Double(index) / Double(memories.count)) * Double.pi * 2
                + (index.isMultiple(of: 2) ? 0.12 : -0.06)
            let radius = shortestSide * (index.isMultiple(of: 2) ? 0.30 : 0.38)
            return (
                memory,
                CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
            )
        }
    }

    private func normalized(_ value: Int, modulus: Int) -> CGFloat {
        CGFloat(abs(value) % modulus) / CGFloat(modulus)
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

private struct MemoryMetricCard: View {
    let icon: String
    let eyebrow: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(PhilotesTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                SectionEyebrow(title: eyebrow)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(L10n.string(detail))
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }
}

private struct MemoryRow: View {
    let memory: MemoryNode
    let onForget: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(memory.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)

                    if memory.isSensitive {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(PhilotesTheme.coral)
                    }
                }

                Text(memory.summary)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 4) {
                Text(memory.createdAt.philotesShortDate)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                Text(memory.source)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .lineLimit(1)
            }

            Menu {
                Button("查看原始上下文") {}
                Button("编辑记忆") {}
                Divider()
                Button("彻底忘记", role: .destructive, action: onForget)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("管理记忆")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var icon: String {
        switch memory.kind {
        case "date": "calendar"
        case "boundary": "hand.raised"
        case "principle": "text.quote"
        case "preference": "heart"
        default: "sparkle"
        }
    }

    private var color: Color {
        switch memory.kind {
        case "date": PhilotesTheme.blue
        case "boundary": PhilotesTheme.coral
        case "principle": PhilotesTheme.lavender
        default: PhilotesTheme.mint
        }
    }
}

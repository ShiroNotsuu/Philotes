import SwiftUI

extension Notification.Name {
    static let philotesDismissConstellationPreview = Notification.Name(
        "philotesDismissConstellationPreview"
    )
}

struct ConstellationPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            floatingTopBar

            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    private var floatingTopBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("星海")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text("所有记忆，一片宇宙。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }

            Spacer()

            ToolbarIconButton(
                systemName: "magnifyingglass",
                label: "搜索宇宙"
            ) {
                dismissConstellationPreview()
            }
            .onHover { hovering in
                if hovering {
                    dismissConstellationPreview()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(UniverseGlassBarModifier())
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func dismissConstellationPreview() {
        NotificationCenter.default.post(
            name: .philotesDismissConstellationPreview,
            object: nil
        )
    }
}

private struct UniverseGlassBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(.black.opacity(0.30)),
                    in: .rect(cornerRadius: 24)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .background(
                    Color.black.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }
}

struct ConstellationUniverseView: View {
    @ObservedObject var model: AppModel
    let onOpenAgent: (AgentProfile) -> Void

    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero
    @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false
    @State private var zoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var editingAgent: AgentProfile?
    @State private var hoveredVaultPreview: VaultMarkdownPreview?
    @State private var pinnedVaultPreview: VaultMarkdownPreview?

    private var visibleVaultPreview: VaultMarkdownPreview? {
        pinnedVaultPreview ?? hoveredVaultPreview
    }

    private var pinnedVaultPreviewID: String? {
        pinnedVaultPreview?.id
    }

    private var displayedZoom: CGFloat {
        min(max(zoom * gestureZoom, 0.55), 2.4)
    }

    var body: some View {
        GeometryReader { proxy in
            let effectivePan = clampedPan(
                CGSize(
                    width: panOffset.width + dragTranslation.width,
                    height: panOffset.height + dragTranslation.height
                ),
                viewport: proxy.size,
                zoom: displayedZoom
            )

            ZStack {
                universeBackground

                ParallaxStarField()
                    .scaleEffect(1 + (displayedZoom - 1) * 0.18)
                    .offset(
                        x: effectivePan.width * 0.22,
                        y: effectivePan.height * 0.22
                    )
                    .allowsHitTesting(false)

                ZStack {
                    worldGrid
                    ZStack {
                        ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, agent in
                            GalaxySystemView(
                                agent: agent,
                                memories: model.memories(for: agent.id),
                                memoryLinks: model.memoryLinks,
                                vaultCategories: model.vaultCategories(for: agent.id),
                                isActive: agent.id == model.activeAgentID,
                                pinnedPreviewID: pinnedVaultPreviewID,
                                onOpen: {
                                    model.setActiveAgent(agent)
                                    onOpenAgent(agent)
                                },
                                onEdit: {
                                    dismissVaultPreview()
                                    editingAgent = agent
                                },
                                onDismissPreview: dismissVaultPreview,
                                onHoverMemory: { memory in
                                    hoverVaultPreview(
                                        memoryPreview(
                                            memory,
                                            agent: agent
                                        )
                                    )
                                },
                                onTogglePinMemory: { memory in
                                    togglePinnedVaultPreview(
                                        memoryPreview(
                                            memory,
                                            agent: agent
                                        )
                                    )
                                },
                                onHoverCategory: { category in
                                    hoverVaultPreview(
                                        categoryPreview(
                                            category,
                                            agent: agent
                                        )
                                    )
                                },
                                onTogglePinCategory: { category in
                                    togglePinnedVaultPreview(
                                        categoryPreview(
                                            category,
                                            agent: agent
                                        )
                                    )
                                },
                                onEndPreview: { previewID in
                                    endHoveredVaultPreview(previewID)
                                }
                            )
                            .frame(width: 260, height: 220)
                            .position(
                                clusterCenter(
                                    index: index,
                                    count: model.agents.count,
                                    size: proxy.size,
                                    agentID: agent.id
                                )
                            )
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(displayedZoom)
                .offset(effectivePan)
                .animation(zoomInertia, value: zoom)
                .animation(panInertia, value: panOffset)

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Spacer()
                        Text("拖动移动 · 双指缩放")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                        zoomControls(viewport: proxy.size)
                        Spacer()
                    }
                }
                .padding(16)

                if model.agents.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 25, weight: .light))
                        Text("宇宙还在等待第一个智能体")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                if let vaultPreview = visibleVaultPreview {
                    VStack {
                        HStack {
                            Spacer()
                            VaultMarkdownPreviewCard(
                                agent: vaultPreview.agent,
                                category: vaultPreview.category,
                                title: vaultPreview.title,
                                markdown: vaultPreview.markdown,
                                accent: vaultPreview.accent,
                                isPinned: pinnedVaultPreviewID
                                    == vaultPreview.id
                            )
                            .id(vaultPreview.id)
                            .padding(.top, 190)
                            .padding(.trailing, 24)
                        }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .animation(
                        .easeOut(duration: 0.14),
                        value: vaultPreview.id
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: proxy.size))
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($gestureZoom) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        let newZoom = min(max(zoom * value, 0.55), 2.4)
                        zoom = newZoom
                        panOffset = clampedPan(
                            panOffset,
                            viewport: proxy.size,
                            zoom: newZoom
                        )
                    }
            )
        }
        .frame(minHeight: 380)
        .sheet(item: $editingAgent) { agent in
            AgentSettingsSheet(agent: agent, model: model) {
                editingAgent = nil
            }
        }
        .onAppear {
            model.refreshVaultCategories()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .philotesDismissConstellationPreview
            )
        ) { _ in
            guard visibleVaultPreview != nil else { return }
            dismissVaultPreview()
        }
    }

    private var universeBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.029, blue: 0.043),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var worldGrid: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: CGFloat.zero, through: size.width, by: 64) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat.zero, through: size.height, by: 64) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(
                grid,
                with: .color(.white.opacity(0.018)),
                lineWidth: 1
            )
        }
    }

    private func zoomControls(viewport: CGSize) -> some View {
        HStack(spacing: 0) {
            Button {
                dismissVaultPreview()
                setZoom(zoom - 0.18, viewport: viewport)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 30)
            }
            .disabled(zoom <= 0.55)

            Divider()
                .overlay(PhilotesTheme.border)
                .frame(height: 16)

            Button {
                dismissVaultPreview()
                resetUniverse()
            } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .frame(width: 46, height: 30)
            }

            Divider()
                .overlay(PhilotesTheme.border)
                .frame(height: 16)

            Button {
                dismissVaultPreview()
                setZoom(zoom + 0.18, viewport: viewport)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 30, height: 30)
            }
            .disabled(zoom >= 2.4)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(PhilotesTheme.secondaryText)
        .buttonStyle(.philotesInteractive)
        .background(PhilotesTheme.surfaceRaised.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
        .onHover { hovering in
            if hovering {
                dismissVaultPreview()
            }
        }
    }

    private var zoomInertia: Animation {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.24)
    }

    private var panInertia: Animation {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .timingCurve(0.18, 1.0, 0.35, 1.0, duration: 0.28)
    }

    private func setZoom(_ value: CGFloat, viewport: CGSize) {
        let newZoom = min(max(value, 0.55), 2.4)
        withAnimation(zoomInertia) {
            zoom = newZoom
            panOffset = clampedPan(
                panOffset,
                viewport: viewport,
                zoom: newZoom
            )
        }
    }

    private func resetUniverse() {
        withAnimation(zoomInertia) {
            zoom = 1
            panOffset = .zero
        }
    }

    private func dragGesture(viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let projected = CGSize(
                    width: panOffset.width + value.predictedEndTranslation.width,
                    height: panOffset.height + value.predictedEndTranslation.height
                )
                withAnimation(panInertia) {
                    panOffset = clampedPan(
                        projected,
                        viewport: viewport,
                        zoom: zoom
                    )
                }
            }
    }

    private func clampedPan(
        _ offset: CGSize,
        viewport: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        let scaledOverflowX = max(0, viewport.width * (zoom - 1) / 2)
        let scaledOverflowY = max(0, viewport.height * (zoom - 1) / 2)
        let edgeAllowanceX = viewport.width * 0.16
        let edgeAllowanceY = viewport.height * 0.16
        let maxX = scaledOverflowX + edgeAllowanceX
        let maxY = scaledOverflowY + edgeAllowanceY
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func clusterCenter(
        index: Int,
        count: Int,
        size: CGSize,
        agentID: Int64
    ) -> CGPoint {
        guard count > 0 else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }

        if count == 1 {
            return CGPoint(x: size.width * 0.50, y: size.height * 0.50)
        }

        // Keep the composition stable across redraws while avoiding the
        // mechanical rows and columns of a grid.
        let angleNoise = stableUnitNoise(agentID, salt: 0xA24B_AED4)
        let radiusNoise = stableUnitNoise(agentID, salt: 0x9E37_79B9)
        let countPhase = stableUnitNoise(Int64(count), salt: 0x85EB_CA6B)

        let progress = CGFloat(index) / CGFloat(max(1, count - 1))
        let radialProgress = sqrt(progress)
        let angle = -CGFloat.pi / 2
            + CGFloat(index) / CGFloat(count) * CGFloat.pi * 2
            + (countPhase - 0.5) * 0.34
            + (angleNoise - 0.5) * 0.58
        let radius = 0.64
            + radialProgress * 0.36
            + (radiusNoise - 0.5) * 0.12

        let normalizedX = 0.50 + cos(angle) * 0.37 * radius
        let normalizedY = 0.51 + sin(angle) * 0.27 * radius

        return CGPoint(
            x: size.width * min(max(normalizedX, 0.16), 0.84),
            y: size.height * min(max(normalizedY, 0.31), 0.76)
        )
    }

    private func stableUnitNoise(_ value: Int64, salt: UInt64) -> CGFloat {
        var mixed = UInt64(bitPattern: value) &+ salt
        mixed ^= mixed >> 30
        mixed = mixed &* 0xBF58_476D_1CE4_E5B9
        mixed ^= mixed >> 27
        mixed = mixed &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return CGFloat(mixed & 0xFF_FFFF) / CGFloat(0xFF_FFFF)
    }

    private func vaultCategoryColor(
        _ category: AgentVaultCategory,
        agent: AgentProfile
    ) -> Color {
        switch category {
        case .navigation:
            return PhilotesTheme.secondaryText
        case .persona:
            return PhilotesTheme.lavender
        case .memory:
            return agent.accentColor
        case .timeline:
            return PhilotesTheme.blue
        case .diary:
            return PhilotesTheme.mint
        case .maintenance:
            return PhilotesTheme.coral
        }
    }

    private func memoryPreview(
        _ memory: MemoryNode,
        agent: AgentProfile
    ) -> VaultMarkdownPreview {
        VaultMarkdownPreview(
            id: "memory-\(memory.id)",
            agent: agent,
            category: .memory,
            title: memory.title,
            markdown: AgentMemoryVaultStore.previewMarkdown(
                forMemoryID: memory.id,
                agentID: agent.id
            ),
            accent: agent.accentColor
        )
    }

    private func categoryPreview(
        _ category: AgentVaultCategorySummary,
        agent: AgentProfile
    ) -> VaultMarkdownPreview {
        VaultMarkdownPreview(
            id: category.id,
            agent: agent,
            category: category.category,
            title: category.category.title,
            markdown: AgentMemoryVaultStore.previewMarkdown(
                for: category.category,
                agentID: agent.id
            ),
            accent: vaultCategoryColor(
                category.category,
                agent: agent
            )
        )
    }

    private func hoverVaultPreview(_ preview: VaultMarkdownPreview) {
        if pinnedVaultPreview?.id != preview.id {
            pinnedVaultPreview = nil
        }
        hoveredVaultPreview = preview
    }

    private func togglePinnedVaultPreview(
        _ preview: VaultMarkdownPreview
    ) {
        if pinnedVaultPreview?.id == preview.id {
            pinnedVaultPreview = nil
            hoveredVaultPreview = nil
            return
        }
        pinnedVaultPreview = preview
        hoveredVaultPreview = preview
    }

    private func endHoveredVaultPreview(_ previewID: String) {
        if hoveredVaultPreview?.id == previewID {
            hoveredVaultPreview = nil
        }
    }

    private func dismissVaultPreview() {
        pinnedVaultPreview = nil
        hoveredVaultPreview = nil
    }
}

private struct VaultMarkdownPreview: Identifiable {
    let id: String
    let agent: AgentProfile
    let category: AgentVaultCategory
    let title: String
    let markdown: String?
    let accent: Color
}

private struct ParallaxStarField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<230 {
                let x = CGFloat((index * 67 + 19) % 251) / 251 * size.width
                let y = CGFloat((index * 103 + 47) % 239) / 239 * size.height
                let isBright = index.isMultiple(of: 13)
                let radius: CGFloat = isBright ? 1.9 : (index.isMultiple(of: 4) ? 1.2 : 0.8)
                let color: Color

                if index.isMultiple(of: 31) {
                    color = PhilotesTheme.lavender.opacity(0.32)
                } else if index.isMultiple(of: 23) {
                    color = PhilotesTheme.blue.opacity(0.28)
                } else {
                    color = .white.opacity(isBright ? 0.24 : 0.11)
                }

                if isBright {
                    let glow = CGRect(
                        x: x - radius * 2.5,
                        y: y - radius * 2.5,
                        width: radius * 5,
                        height: radius * 5
                    )
                    context.fill(
                        Path(ellipseIn: glow),
                        with: .color(color.opacity(0.12))
                    )
                }

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: x,
                        y: y,
                        width: radius,
                        height: radius
                    )),
                    with: .color(color)
                )
            }
        }
    }
}

private struct PositionedMemory: Identifiable {
    let memory: MemoryNode
    let position: CGPoint

    var id: Int64 { memory.id }
}

private struct PositionedVaultCategory: Identifiable {
    let summary: AgentVaultCategorySummary
    let position: CGPoint

    var id: String { summary.id }
}

private struct GalaxySystemView: View {
    let agent: AgentProfile
    let memories: [MemoryNode]
    let memoryLinks: [MemoryLink]
    let vaultCategories: [AgentVaultCategorySummary]
    let isActive: Bool
    let pinnedPreviewID: String?
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDismissPreview: () -> Void
    let onHoverMemory: (MemoryNode) -> Void
    let onTogglePinMemory: (MemoryNode) -> Void
    let onHoverCategory: (AgentVaultCategorySummary) -> Void
    let onTogglePinCategory: (AgentVaultCategorySummary) -> Void
    let onEndPreview: (String) -> Void

    @State private var isHovering = false

    private var center: CGPoint {
        CGPoint(x: 130, y: 94)
    }

    var body: some View {
        GeometryReader { _ in
            let memoryPoints = memoryPositions()
            let categoryPoints = vaultCategoryPositions()
            let positionsByMemoryID = Dictionary(
                uniqueKeysWithValues: memoryPoints.map { ($0.memory.id, $0.position) }
            )

            ZStack {
                Canvas { context, _ in
                    for category in categoryPoints {
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: category.position)
                        context.stroke(
                            path,
                            with: .color(
                                category.summary.category == .memory
                                    ? agent.accentColor.opacity(0.24)
                                    : .white.opacity(0.12)
                            ),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 4])
                        )
                    }

                    for point in memoryPoints {
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point.position)
                        context.stroke(
                            path,
                            with: .color(agent.accentColor.opacity(isHovering ? 0.34 : 0.19)),
                            lineWidth: 1
                        )
                    }

                    for link in memoryLinks {
                        guard
                            let source = positionsByMemoryID[link.sourceMemoryID],
                            let target = positionsByMemoryID[link.targetMemoryID]
                        else {
                            continue
                        }

                        var path = Path()
                        path.move(to: source)
                        path.addLine(to: target)
                        context.stroke(
                            path,
                            with: .color(.white.opacity(isHovering ? 0.26 : 0.14)),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                        )
                    }
                }

                ForEach(memoryPoints) { point in
                    MemoryStarView(
                        memory: point.memory,
                        isPinned: pinnedPreviewID
                            == "memory-\(point.memory.id)",
                        action: {
                            onTogglePinMemory(point.memory)
                        },
                        onPreview: {
                            onHoverMemory(point.memory)
                        },
                        onEndPreview: {
                            onEndPreview("memory-\(point.memory.id)")
                        }
                    )
                    .position(point.position)
                }

                ForEach(categoryPoints) { category in
                    VaultCategoryNodeView(
                        summary: category.summary,
                        accent: vaultCategoryColor(category.summary.category),
                        isPinned: pinnedPreviewID == category.summary.id
                    ) {
                        onTogglePinCategory(category.summary)
                    } onHover: { hovering in
                        if hovering {
                            onHoverCategory(category.summary)
                        } else {
                            onEndPreview(category.summary.id)
                        }
                    }
                    .position(category.position)
                }

                Button {
                    onDismissPreview()
                    onOpen()
                } label: {
                    ZStack {
                        Image(systemName: "sparkle")
                            .font(.system(size: isHovering ? 68 : 62, weight: .ultraLight))
                            .foregroundStyle(agent.accentColor.opacity(isHovering ? 0.45 : 0.28))

                        Circle()
                            .fill(PhilotesTheme.surfaceRaised)
                            .frame(width: 48, height: 48)
                            .overlay {
                                AgentGlyph(
                                    emoji: agent.emoji,
                                    size: 18,
                                    imagePath: agent.avatarImagePath
                                )
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        agent.accentColor.opacity(isActive ? 0.74 : 0.38),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.philotesInteractive)
                .onHover { hovering in
                    if hovering {
                        onDismissPreview()
                    }
                }
                .position(center)
                .scaleEffect(isHovering ? 1.07 : 1)

                if isHovering {
                    Button {
                        onDismissPreview()
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(PhilotesTheme.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(PhilotesTheme.surfaceRaised, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(PhilotesTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.philotesInteractive)
                    .onHover { hovering in
                        if hovering {
                            onDismissPreview()
                        }
                    }
                    .position(x: center.x + 40, y: center.y - 34)
                    .transition(.scale.combined(with: .opacity))
                }

                VStack(spacing: 3) {
                    Text(agent.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(agent.role)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                .position(x: center.x, y: 175)
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    isHovering = hovering
                }
            }
            .animation(.easeOut(duration: 0.16), value: isHovering)
        }
    }

    private func memoryPositions() -> [PositionedMemory] {
        memories.enumerated().map { index, memory in
            let count = max(1, memories.count)
            let angle = -Double.pi / 2
                + Double(index) / Double(count) * Double.pi * 2
                + Double(agent.id % 5) * 0.13
            let ring = index / 8
            let radius = CGFloat(
                36
                    + ring * 9
                    + Int((memory.id + Int64(index * 13)) % 10)
            )
            return PositionedMemory(
                memory: memory,
                position: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
            )
        }
    }

    private func vaultCategoryPositions() -> [PositionedVaultCategory] {
        let summaries = AgentVaultCategory.allCases.map { category in
            vaultCategories.first { $0.category == category }
                ?? AgentVaultCategorySummary(
                    agentID: agent.id,
                    category: category,
                    count: 0,
                    updatedAt: .distantPast
                )
        }
        return summaries.enumerated().map { index, summary in
            let angle = -CGFloat.pi / 2
                + CGFloat(index) / CGFloat(summaries.count) * CGFloat.pi * 2
            return PositionedVaultCategory(
                summary: summary,
                position: CGPoint(
                    x: center.x + cos(angle) * 78,
                    y: center.y + sin(angle) * 55
                )
            )
        }
    }

    private func vaultCategoryColor(
        _ category: AgentVaultCategory
    ) -> Color {
        switch category {
        case .navigation:
            return PhilotesTheme.secondaryText
        case .persona:
            return PhilotesTheme.lavender
        case .memory:
            return agent.accentColor
        case .timeline:
            return PhilotesTheme.blue
        case .diary:
            return PhilotesTheme.mint
        case .maintenance:
            return PhilotesTheme.coral
        }
    }
}

private struct VaultCategoryNodeView: View {
    let summary: AgentVaultCategorySummary
    let accent: Color
    let isPinned: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: summary.category.systemImage)
                    .font(.system(size: 7, weight: .semibold))
                Text(summary.category.title)
                    .font(.system(size: 7.5, weight: .medium, design: .rounded))
                Text("\(summary.count)")
                    .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 4)
                    .frame(height: 12)
                    .background(accent.opacity(0.14), in: Capsule())

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .foregroundStyle(
                isHovering || isPinned
                    ? PhilotesTheme.primaryText
                    : PhilotesTheme.secondaryText
            )
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                isHovering || isPinned
                    ? PhilotesTheme.surfaceRaised.opacity(0.98)
                    : PhilotesTheme.surface.opacity(0.88),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        accent.opacity(
                            isPinned ? 0.82 : (isHovering ? 0.56 : 0.22)
                        ),
                        lineWidth: isPinned ? 1.4 : 1
                    )
            }
            .shadow(
                color: accent.opacity(
                    isPinned ? 0.38 : (isHovering ? 0.24 : 0.08)
                ),
                radius: isPinned ? 12 : (isHovering ? 9 : 3)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.philotesInteractive)
        .scaleEffect(isHovering || isPinned ? 1.07 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            onHover(hovering)
        }
        .help(
            L10n.format(
                "%@ · %lld 个 Markdown 文件",
                summary.category.title,
                Int64(summary.count)
            )
        )
    }
}

private struct MemoryStarView: View {
    let memory: MemoryNode
    let isPinned: Bool
    let action: () -> Void
    let onPreview: () -> Void
    let onEndPreview: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        memory.accentColor.opacity(
                            isPinned ? 0.34 : (isHovering ? 0.24 : 0.08)
                        )
                    )
                    .frame(
                        width: isPinned ? 28 : (isHovering ? 24 : 12),
                        height: isPinned ? 28 : (isHovering ? 24 : 12)
                    )
                    .blur(radius: isPinned ? 6 : (isHovering ? 5 : 1))

                Circle()
                    .fill(memory.accentColor)
                    .frame(
                        width: isPinned ? 8 : (isHovering ? 7 : 4.5),
                        height: isPinned ? 8 : (isHovering ? 7 : 4.5)
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.55), lineWidth: 0.5)
                    }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.philotesInteractive)
        .overlay(alignment: .top) {
            if isHovering || isPinned {
                HStack(spacing: 4) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(memory.accentColor)
                    }
                    Text(memory.title)
                        .font(
                            .system(
                                size: 9,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    PhilotesTheme.surfaceRaised.opacity(0.98),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            memory.accentColor.opacity(
                                isPinned ? 0.55 : 0.12
                            ),
                            lineWidth: 1
                        )
                }
                .offset(y: -22)
                .fixedSize()
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isHovering = hovering
            }
            if hovering {
                onPreview()
            } else {
                onEndPreview()
            }
        }
        .help(memory.summary)
        .accessibilityLabel(memory.title)
    }
}

import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection
    @Binding var isCollapsed: Bool
    @ObservedObject var model: AppModel
    let onOpenChat: () -> Void
    let glassRefreshToken: UUID
    @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false

    private var primarySections: [AppSection] {
        [.constellation, .groups, .agents]
    }

    private var panelWidth: CGFloat {
        isCollapsed ? 72 : 238
    }

    private var totalWidth: CGFloat {
        panelWidth + 18
    }

    var body: some View {
        sidebarContent
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .background {
                sidebarGlass
                    .id(glassRefreshToken)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 24, x: 8, y: 8)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(width: totalWidth)
            .frame(maxHeight: .infinity)
            .animation(collapseAnimation, value: isCollapsed)
            .accessibilityIdentifier("sidebar")
    }

    private var sidebarContent: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 0) {
            brand

            newConversationButton
                .padding(.horizontal, isCollapsed ? 10 : 12)
                .padding(.top, 18)

            navigation
                .padding(.top, 22)

            if !isCollapsed {
                recent
                    .padding(.top, 26)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 20)

            localStatus
                .padding(.horizontal, isCollapsed ? 10 : 12)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var sidebarGlass: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.10))
                .glassEffect(
                    .regular
                        .tint(.black.opacity(0.46)),
                    in: .rect(cornerRadius: 20)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(0.34))
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            brandMark

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PHILOTES")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(PhilotesTheme.primaryText)

                    Text("生活搭档")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            if !isCollapsed {
                Spacer(minLength: 0)
            }

            Button {
                withAnimation(collapseAnimation) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PhilotesTheme.tertiaryText)
                    .frame(width: 26, height: 26)
                    .background(PhilotesTheme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.philotesInteractive)
            .onHover(perform: dismissConstellationPreviewOnHover)
            .help(isCollapsed ? "展开侧边栏" : "收起侧边栏")
            .accessibilityLabel(isCollapsed ? "展开侧边栏" : "收起侧边栏")
        }
        .padding(.horizontal, isCollapsed ? 0 : 16)
        .padding(.top, 48)
        .frame(maxWidth: .infinity)
    }

    private var brandMark: some View {
        Image("PhilotesBrandMark")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
        .shadow(
            color: PhilotesTheme.blue.opacity(isCollapsed ? 0.18 : 0.08),
            radius: isCollapsed ? 12 : 5
        )
        .accessibilityLabel("Philotes")
    }

    private var newConversationButton: some View {
        Button(action: onOpenChat) {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))

                if !isCollapsed {
                    Text("新对话")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
            }
            .foregroundStyle(PhilotesTheme.primaryText)
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .frame(maxWidth: isCollapsed ? nil : .infinity)
            .frame(width: isCollapsed ? 38 : nil, height: 38)
            .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.philotesInteractive)
        .onHover(perform: dismissConstellationPreviewOnHover)
        .help("新对话")
        .accessibilityIdentifier("newConversationButton")
    }

    private var collapseAnimation: Animation {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var navigation: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 5) {
            if !isCollapsed {
                SidebarSectionLabel(title: "工作区")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 3)
                    .transition(.opacity)
            }

            ForEach(primarySections) { section in
                SidebarRow(
                    section: section,
                    isSelected: selection == section,
                    isCollapsed: isCollapsed
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = section
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 7) {
            SidebarSectionLabel(title: "最近")
                .padding(.horizontal, 16)

            Button {
                onOpenChat()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            L10n.format(
                                "和%@聊聊",
                                model.activeAgent?.name
                                    ?? L10n.string("斐洛")
                            )
                        )
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PhilotesTheme.secondaryText)
                        Text(
                            model.activeAgent?.role
                                ?? L10n.string("生活搭档")
                        )
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(PhilotesTheme.tertiaryText)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.philotesInteractive)
            .onHover(perform: dismissConstellationPreviewOnHover)
            .padding(.horizontal, 4)
        }
    }

    private var localStatus: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 8) {
            if !isCollapsed {
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
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    selection = .account
                }
            } label: {
                footerRow(
                    title: model.userNickname,
                    subtitle: "本地账户",
                    isSelected: selection == .account,
                    localizesTitle: false
                ) {
                    UserAvatarView(
                        imagePath: model.userAvatarPath,
                        size: 30
                    )
                } trailing: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }
            }
            .buttonStyle(.philotesInteractive)
            .onHover(perform: dismissConstellationPreviewOnHover)
            .help("账户")
            .accessibilityIdentifier("sidebar.account")

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    selection = .settings
                }
            } label: {
                footerRow(
                    title: "设置",
                    subtitle: "隐私与陪伴方式",
                    isSelected: selection == .settings
                ) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PhilotesTheme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(
                            PhilotesTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                } trailing: {
                    EmptyView()
                }
            }
            .buttonStyle(.philotesInteractive)
            .onHover(perform: dismissConstellationPreviewOnHover)
            .help("设置")
            .accessibilityIdentifier("sidebar.settings")
        }
        .frame(maxWidth: .infinity)
    }

    private func footerRow<Leading: View, Trailing: View>(
        title: String,
        subtitle: String,
        isSelected: Bool,
        localizesTitle: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            leading()

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(localizesTitle ? L10n.string(title) : title)
                        .font(
                            .system(
                                size: 11,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text(L10n.string(subtitle))
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
                trailing()
            }
        }
        .padding(.horizontal, isCollapsed ? 0 : 9)
        .frame(width: isCollapsed ? 38 : nil, height: 44)
        .background(
            isSelected
                ? PhilotesTheme.surfaceRaised
                : PhilotesTheme.surface.opacity(isCollapsed ? 0 : 0.66),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    isSelected
                        ? PhilotesTheme.borderStrong
                        : PhilotesTheme.border,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
    }
}

private struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(L10n.string(title))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(PhilotesTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(
                        isSelected
                            ? PhilotesTheme.primaryText
                            : PhilotesTheme.secondaryText
                    )

                if !isCollapsed {
                    Text(section.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(
                            isSelected
                                ? PhilotesTheme.primaryText
                                : PhilotesTheme.secondaryText
                        )
                    Spacer()
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .frame(width: isCollapsed ? 38 : nil, height: 36)
            .background(
                isSelected
                    ? PhilotesTheme.surfaceRaised
                    : isHovering
                        ? PhilotesTheme.surface.opacity(0.7)
                        : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.philotesInteractive)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            dismissConstellationPreviewOnHover(hovering)
        }
        .padding(.horizontal, isCollapsed ? 0 : 8)
        .help(isCollapsed ? section.title : section.subtitle)
        .accessibilityIdentifier("sidebar.\(section.rawValue)")
    }
}

private func dismissConstellationPreviewOnHover(_ hovering: Bool) {
    guard hovering else { return }
    NotificationCenter.default.post(
        name: .philotesDismissConstellationPreview,
        object: nil
    )
}

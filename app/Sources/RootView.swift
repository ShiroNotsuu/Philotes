import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection = .constellation
    @State private var isChatWorkspaceExpanded = false
    @State private var glassRefreshToken = UUID()
    @AppStorage("sidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false
    @AppStorage(PhilotesLanguage.storageKey)
    private var languageCode = PhilotesLanguage.simplifiedChinese.rawValue

    private var selectedLanguage: PhilotesLanguage {
        PhilotesLanguage(rawValue: languageCode)
            ?? .simplifiedChinese
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if usesUniverseBackdrop {
                ConstellationUniverseView(model: model) { agent in
                    model.setActiveAgent(agent)
                    selection = .agents
                }
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                PhilotesTheme.canvas
                    .ignoresSafeArea()
            }

            HStack(spacing: 0) {
                SidebarView(
                    selection: $selection,
                    isCollapsed: $isSidebarCollapsed,
                    model: model,
                    onOpenChat: openChatWorkspace,
                    glassRefreshToken: glassRefreshToken
                )

                contentPane
                    .background(
                        selection == .constellation
                            ? Color.clear
                            : PhilotesTheme.canvas
                    )
                    .overlay {
                        if model.personalityActivationNoticeVisible {
                            PersonalityActivatedToast()
                                .transition(
                                    .scale(scale: 0.88)
                                        .combined(with: .opacity)
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(
                        .easeOut(duration: 0.2),
                        value: model.personalityActivationNoticeVisible
                    )
            }
            .buttonStyle(.philotesInteractive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(PhilotesTheme.primaryText)
        .background(PhilotesTheme.canvas)
        .frame(minWidth: 980, minHeight: 680)
        .preferredColorScheme(.dark)
        .environment(\.locale, selectedLanguage.locale)
        .id(languageCode)
        .animation(pageAnimation, value: selection)
        .animation(sidebarAnimation, value: isSidebarCollapsed)
        .animation(pageAnimation, value: isChatWorkspaceExpanded)
        .onChange(of: selection) {
            if isChatWorkspaceExpanded {
                closeChatWorkspace()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .philotesNewConversation)) { _ in
            openChatWorkspace()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            scheduleGlassSurfaceRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            scheduleGlassSurfaceRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            scheduleGlassSurfaceRefresh(for: notification.object as? NSWindow)
        }
        .overlay(alignment: .topTrailing) {
            if let errorMessage = model.errorMessage, !isChatWorkspaceExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PhilotesTheme.coral)
                    Text(L10n.string(errorMessage))
                        .lineLimit(2)
                    Button {
                        model.clearError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.philotesInteractive)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PhilotesTheme.surfaceRaised, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(PhilotesTheme.coral.opacity(0.25), lineWidth: 1)
                }
                .padding(18)
            }
        }
    }

    private var usesUniverseBackdrop: Bool {
        selection == .constellation && !isChatWorkspaceExpanded
    }

    private var contentPane: some View {
        ZStack {
            if isChatWorkspaceExpanded {
                ConversationPage(
                    model: model,
                    onClose: closeChatWorkspace,
                    onAgentDeleted: {
                        selection = .agents
                        closeChatWorkspace()
                    }
                )
                .transition(.opacity)
            } else {
                ZStack {
                    detail
                        .id(selection)
                        .transition(.opacity.combined(with: .scale(scale: 0.994)))
                }
                .overlay(alignment: .bottomTrailing) {
                    if selection != .groups {
                        FloatingChatView(model: model) {
                            openChatWorkspace()
                        }
                        .padding(22)
                        .transition(
                            .scale(scale: 0.96, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .constellation:
            ConstellationPage(model: model)
        case .groups:
            GroupChatPage(model: model)
        case .agents:
            AgentsPage(model: model, onOpenChat: openChatWorkspace)
        case .account:
            AccountPage(model: model)
        case .settings:
            SettingsPage(model: model)
        }
    }

    private func openChatWorkspace() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChatWorkspaceExpanded = true
        }
    }

    private func closeChatWorkspace() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isChatWorkspaceExpanded = false
        }
    }

    private func scheduleGlassSurfaceRefresh(for candidate: NSWindow? = nil) {
        Task { @MainActor in
            await Task.yield()

            let window = candidate ?? NSApp.windows.first {
                $0.canBecomeMain
                    && $0.sheetParent == nil
                    && $0.isVisible
            }
            guard let window,
                  window.sheetParent == nil,
                  window.attachedSheet == nil
            else {
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                glassRefreshToken = UUID()
            }
            window.invalidateShadow()
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
    }

    private var sidebarAnimation: Animation? {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var pageAnimation: Animation? {
        reduceMotionEnabled
            ? .linear(duration: 0.01)
            : .easeOut(duration: 0.18)
    }
}

#Preview {
    RootView(model: PreviewSupport.model)
}

@MainActor
private enum PreviewSupport {
    static let model: AppModel = {
        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("philotes-preview.sqlite")
        return AppModel(databaseURL: previewURL)
    }()
}

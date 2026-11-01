import AppKit
import SwiftUI

extension Notification.Name {
    static let philotesNewConversation = Notification.Name("philotes.newConversation")
}

@main
struct PhilotesApp: App {
    @NSApplicationDelegateAdaptor(PhilotesAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("新对话")) {
                    NotificationCenter.default.post(
                        name: .philotesNewConversation,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

final class PhilotesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyDockIcon()
    }

    private func applyDockIcon() {
        guard let icon = NSImage(named: "PhilotesDockIcon") else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }
}

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case constellation
    case groups
    case agents
    case account
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .constellation: L10n.string("星海")
        case .groups: L10n.string("群聊")
        case .agents: L10n.string("智能体")
        case .account: L10n.string("账户")
        case .settings: L10n.string("设置")
        }
    }

    var systemImage: String {
        switch self {
        case .constellation: "sparkles.rectangle.stack"
        case .groups: "bubble.left.and.bubble.right.fill"
        case .agents: "person.2.crop.square.stack"
        case .account: "person.crop.circle"
        case .settings: "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .constellation: L10n.string("所有记忆星系")
        case .groups: L10n.string("让智能体一起聊天")
        case .agents: L10n.string("选择与创建智能体")
        case .account: L10n.string("账户、使用情况与智能体")
        case .settings: L10n.string("隐私与陪伴方式")
        }
    }
}

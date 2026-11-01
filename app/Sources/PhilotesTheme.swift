import AppKit
import SwiftUI

enum PhilotesTheme {
    static let canvas = Color.black
    static let sidebar = Color(red: 0.045, green: 0.048, blue: 0.054)
    static let surface = Color(red: 0.075, green: 0.079, blue: 0.088)
    static let surfaceRaised = Color(red: 0.105, green: 0.11, blue: 0.122)
    static let surfaceHover = Color(red: 0.13, green: 0.137, blue: 0.151)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.13)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)
    static let blue = Color(red: 0.39, green: 0.68, blue: 1.0)
    static let mint = Color(red: 0.43, green: 0.88, blue: 0.77)
    static let lavender = Color(red: 0.68, green: 0.62, blue: 0.98)
    static let coral = Color(red: 1.0, green: 0.49, blue: 0.47)
    static let cornerRadius: CGFloat = 16
}

struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let localizesTitle: Bool
    @ViewBuilder let trailing: Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        localizesTitle: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.localizesTitle = localizesTitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(PhilotesTheme.tertiaryText)
                }

                Text(localizesTitle ? L10n.string(title) : title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(PhilotesTheme.primaryText)

                Text(L10n.string(subtitle))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }

            Spacer(minLength: 20)
            trailing
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 22)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct PhilotesCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                PhilotesTheme.surface,
                in: RoundedRectangle(cornerRadius: PhilotesTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PhilotesTheme.cornerRadius, style: .continuous)
                    .stroke(PhilotesTheme.border, lineWidth: 1)
            }
    }
}

struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(L10n.string(title).uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(PhilotesTheme.tertiaryText)
    }
}

struct ToolbarIconButton: View {
    let systemName: String
    let label: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PhilotesTheme.secondaryText)
                .frame(width: 32, height: 32)
                .background(PhilotesTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PhilotesTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.philotesInteractive)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 4)
            }
    }
}

struct AgentGlyph: View {
    let emoji: String
    let size: CGFloat
    var imagePath: String? = nil

    var body: some View {
        Group {
            if let imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size * 1.35, height: size * 1.35)
                    .clipShape(Circle())
            } else {
                Text(emoji.isEmpty ? "✨" : emoji)
                    .font(.system(size: size))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: size * 1.35, height: size * 1.35)
            }
        }
        .accessibilityLabel("智能体头像")
    }
}

struct UserAvatarView: View {
    let imagePath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            PhilotesTheme.lavender.opacity(0.72),
                            PhilotesTheme.blue.opacity(0.46)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "person.fill")
                        .font(
                            .system(
                                size: size * 0.42,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("用户头像")
    }
}

struct PhilotesInteractiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveBody(configuration: configuration)
    }

    private struct InteractiveBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false
        @AppStorage("reduceMotionEnabled") private var reduceMotionEnabled = false

        var body: some View {
            configuration.label
                .scaleEffect(
                    configuration.isPressed
                        ? 0.985
                        : isHovering
                            ? 1.008
                            : 1
                )
                .brightness(isHovering ? 0.025 : 0)
                .shadow(
                    color: isHovering ? .white.opacity(0.035) : .clear,
                    radius: 4
                )
                .animation(hoverAnimation, value: isHovering)
                .animation(hoverAnimation, value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
        }

        private var hoverAnimation: Animation {
            reduceMotionEnabled
                ? .linear(duration: 0.01)
                : .easeOut(duration: 0.14)
        }
    }
}

extension ButtonStyle where Self == PhilotesInteractiveButtonStyle {
    static var philotesInteractive: PhilotesInteractiveButtonStyle {
        PhilotesInteractiveButtonStyle()
    }
}

extension Date {
    var philotesShortDate: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .month(.abbreviated)
                .day()
        )
    }

    var philotesTime: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .hour()
                .minute()
        )
    }
}

extension AgentProfile {
    var accentColor: Color {
        switch accent {
        case "lavender": PhilotesTheme.lavender
        case "mint": PhilotesTheme.mint
        case "coral": PhilotesTheme.coral
        default: PhilotesTheme.blue
        }
    }
}

extension MemoryNode {
    var accentColor: Color {
        switch kind {
        case "date": PhilotesTheme.blue
        case "boundary": PhilotesTheme.coral
        case "principle", "idea": PhilotesTheme.lavender
        default: PhilotesTheme.mint
        }
    }
}

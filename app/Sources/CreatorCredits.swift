import AppKit
import Foundation
import SwiftUI

@MainActor
final class CreatorAvatarStore: ObservableObject {
    static let shared = CreatorAvatarStore()

    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = false

    private static let remoteURL = URL(
        string: """
        https://p3-pc-sign.douyinpic.com/aweme-avatar/\
        tos-cn-avt-0015_37ff0553e773a74a5f0f36084c175979~\
        tplv-8yspqt5zfm-300x300.webp?\
        lk3s=93de098e&x-expires=1793624400&\
        x-signature=y%2Ftd8S7AXhDeMV88n4%2BKzNdhpmM%3D&\
        from=2480802190&s=profile&se=false&sc=avatar&\
        l=202610312126303B3FAF5328EC45753862
        """
    )

    private var hasStarted = false

    private init() {
        image = Self.readCachedImage()
    }

    func load() {
        guard !hasStarted else { return }
        hasStarted = true

        if image != nil {
            return
        }

        isLoading = true
        Task { @MainActor [weak self] in
            await self?.downloadAvatar()
        }
    }

    private func downloadAvatar() async {
        defer { isLoading = false }
        guard let remoteURL = Self.remoteURL else { return }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let downloadedImage = NSImage(data: data)
            else {
                return
            }

            let cacheURL = Self.cacheURL
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            image = downloadedImage
        } catch {
            // Keep the local default avatar when the network image is unavailable.
        }
    }

    private static var cacheURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Philotes", isDirectory: true)
            .appendingPathComponent("CreatorAvatars", isDirectory: true)
            .appendingPathComponent("ShiroNotsu.webp")
    }

    private static func readCachedImage() -> NSImage? {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return NSImage(data: data)
    }
}

struct CreatorCreditsSection: View {
    @ObservedObject private var avatarStore = CreatorAvatarStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PhilotesTheme.lavender)
                    .frame(width: 32, height: 32)
                    .background(
                        PhilotesTheme.lavender.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    SectionEyebrow(title: "创作者")
                    Text("ResetSophia")
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(PhilotesTheme.primaryText)
                    Text("由团队成员共同打造")
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
            }

            HStack(spacing: 10) {
                CreatorMemberCard(
                    name: "ShiroNotsu",
                    role: "软件开发",
                    avatar: avatarStore.image,
                    isRemoteAvatarLoading: avatarStore.isLoading
                )

                CreatorMemberCard(
                    name: "CoverV604",
                    role: "测试及底层构建",
                    avatar: nil,
                    isRemoteAvatarLoading: false
                )
            }
        }
        .padding(16)
        .background(
            PhilotesTheme.surface,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
        .task {
            avatarStore.load()
        }
    }
}

private struct CreatorMemberCard: View {
    let name: String
    let role: String
    let avatar: NSImage?
    let isRemoteAvatarLoading: Bool

    var body: some View {
        HStack(spacing: 11) {
            CreatorAvatar(
                image: avatar,
                isLoading: isRemoteAvatarLoading
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.primaryText)
                Text(L10n.string(role))
                    .font(
                        .system(
                            size: 9,
                            weight: .regular,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(PhilotesTheme.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(
            PhilotesTheme.surfaceRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(PhilotesTheme.border, lineWidth: 1)
        }
    }
}

private struct CreatorAvatar: View {
    let image: NSImage?
    let isLoading: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            PhilotesTheme.blue.opacity(0.22),
                            PhilotesTheme.lavender.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(PhilotesTheme.secondaryText)
            }
        }
        .overlay {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

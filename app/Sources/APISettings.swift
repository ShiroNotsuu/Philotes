import Foundation
import Security

struct APIConfiguration {
    let endpoint: URL
    let model: String
    let apiKey: String?
}

enum AgentAPIProvider: String, CaseIterable, Identifiable {
    case none
    case deepseek
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.string("暂不配置")
        case .deepseek: return "DeepSeek"
        case .custom: return L10n.string("自定义兼容接口")
        }
    }

    var detail: String {
        switch self {
        case .none:
            return L10n.string("创建后仍然可以回来配置")
        case .deepseek:
            return L10n.string("预置 DeepSeek 地址与 deepseek-chat")
        case .custom:
            return L10n.string("任何兼容 OpenAI Chat Completions 的接口")
        }
    }

    var badgeTitle: String {
        switch self {
        case .none: return L10n.string("API 未配置")
        case .deepseek: return "DeepSeek"
        case .custom: return L10n.string("自定义 API")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .none, .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .none, .custom: return ""
        }
    }
}

enum APISettings {
    static let baseURLDefaultsKey = "customAPIBaseURL"
    static let modelDefaultsKey = "customAPIModel"

    static func resolvedValues(
        provider: AgentAPIProvider,
        baseURL: String,
        model: String
    ) throws -> (baseURL: String, model: String) {
        guard provider != .none else {
            return ("", "")
        }

        let cleanBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = cleanBaseURL.isEmpty
            ? provider.defaultBaseURL
            : cleanBaseURL
        let resolvedModel = cleanModel.isEmpty
            ? provider.defaultModel
            : cleanModel

        _ = try endpointURL(from: resolvedBaseURL)
        guard !resolvedModel.isEmpty else {
            throw APIConfigurationError.missingModel
        }
        return (resolvedBaseURL, resolvedModel)
    }

    static func configuration(
        provider: AgentAPIProvider,
        baseURL: String,
        model: String,
        apiKeyInput: String,
        existingAgentID: Int64?
    ) throws -> APIConfiguration {
        guard provider != .none else {
            throw APIConfigurationError.missingProvider
        }

        let values = try resolvedValues(
            provider: provider,
            baseURL: baseURL,
            model: model
        )
        let cleanKey = apiKeyInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let storedKey = try existingAgentID.flatMap {
            try APIKeychain.load(for: $0)
        }
        let apiKey = cleanKey.isEmpty ? storedKey : cleanKey
        return APIConfiguration(
            endpoint: try endpointURL(from: values.baseURL),
            model: values.model,
            apiKey: apiKey?.isEmpty == false ? apiKey : nil
        )
    }

    static func legacyConfigurationIfPresent() -> (
        baseURL: String,
        model: String
    )? {
        let defaults = UserDefaults.standard
        let baseURL = (
            defaults.string(forKey: baseURLDefaultsKey) ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (
            defaults.string(forKey: modelDefaultsKey) ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !model.isEmpty else {
            return nil
        }
        return (baseURL, model)
    }

    static func clearLegacyConfiguration() {
        UserDefaults.standard.removeObject(forKey: baseURLDefaultsKey)
        UserDefaults.standard.removeObject(forKey: modelDefaultsKey)
    }

    static func endpointURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIConfigurationError.missingEndpoint
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil
        else {
            throw APIConfigurationError.invalidEndpoint
        }
        guard components.user == nil, components.password == nil else {
            throw APIConfigurationError.embeddedCredentials
        }

        let host = components.host?
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let isLocalHost = host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
        if scheme == "http" && !isLocalHost {
            throw APIConfigurationError.insecureEndpoint
        }

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if !components.path.hasSuffix("/chat/completions") {
            let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + [basePath, "chat/completions"]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }
        components.fragment = nil

        guard let url = components.url else {
            throw APIConfigurationError.invalidEndpoint
        }
        return url
    }
}

enum APIConfigurationError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint
    case insecureEndpoint
    case embeddedCredentials
    case missingProvider
    case missingModel
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "请先填写 API 地址。"
        case .invalidEndpoint:
            return "API 地址需要是有效的 http 或 https 地址。"
        case .insecureEndpoint:
            return "远程 API 必须使用 HTTPS；HTTP 仅允许 localhost。"
        case .embeddedCredentials:
            return "请勿把账号或密码写进 API 地址；API Key 请填在单独字段。"
        case .missingProvider:
            return "请先为这个智能体选择 API。"
        case .missingModel:
            return "请先填写模型名称。"
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            if status == errSecAuthFailed {
                return """
                无法访问 macOS 钥匙串（\(status)）：旧开发构建的签名已变化。\
                请重新输入一次 API Key；Philotes 会把它写入修正后的钥匙串记录。
                """
            }
            return "无法访问 macOS 钥匙串（\(status)）：\(detail ?? "未知错误")"
        }
    }
}

enum APIKeychain {
    // A new service avoids stale ACLs created by earlier ad-hoc Debug builds.
    private static let service = "com.shironotsu.philotes.custom-api.v2"
    private static let legacyService = "com.shironotsu.philotes.custom-api"
    private static let legacyAccount = "api-key"

    static func load(for agentID: Int64) throws -> String? {
        try load(account: account(for: agentID))
    }

    static func hasKey(for agentID: Int64) -> Bool {
        (try? load(for: agentID))?.isEmpty == false
    }

    static func save(_ apiKey: String, for agentID: Int64) throws {
        try save(apiKey, account: account(for: agentID))
    }

    static func delete(for agentID: Int64) throws {
        try delete(account: account(for: agentID))
    }

    static func migrateLegacyKey(to agentID: Int64) throws {
        guard !hasKey(for: agentID),
              let legacyKey = try load(account: legacyAccount),
              !legacyKey.isEmpty
        else {
            return
        }
        try save(legacyKey, for: agentID)
        try delete(account: legacyAccount)
    }

    private static func account(for agentID: Int64) -> String {
        "agent-\(agentID)-api-key"
    }

    private static func load(account: String) throws -> String? {
        if let current = try load(account: account, service: service) {
            return current
        }

        do {
            guard let legacy = try load(
                account: account,
                service: legacyService
            ) else {
                return nil
            }
            try save(legacy, account: account)
            try? delete(account: account, service: legacyService)
            return legacy
        } catch APIConfigurationError.keychain(let status)
            where status == errSecAuthFailed
                || status == errSecInteractionNotAllowed {
            // A changed ad-hoc signature can make an old item unreadable.
            // Treat it as absent so the user can enter a fresh key.
            return nil
        }
    }

    private static func load(
        account: String,
        service: String
    ) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIConfigurationError.keychain(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ apiKey: String, account: String) throws {
        try save(apiKey, account: account, service: service)
    }

    private static func save(
        _ apiKey: String,
        account: String,
        service: String
    ) throws {
        let data = Data(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updates: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIConfigurationError.keychain(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIConfigurationError.keychain(addStatus)
        }
    }

    private static func delete(account: String) throws {
        try delete(account: account, service: service)
        try? delete(account: account, service: legacyService)
    }

    private static func delete(
        account: String,
        service: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIConfigurationError.keychain(status)
        }
    }

}

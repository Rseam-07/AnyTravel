import Foundation
import Observation
import Security

enum AssistantProviderMode: String, CaseIterable, Identifiable, Sendable {
    case managed
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .managed: "AnyTravel 智能服务"
        case .custom: "自定义服务"
        }
    }
}

protocol AssistantSecretStoring {
    func read() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

@Observable
final class AssistantSettingsStore {
    static let providerModeKey = "AnyTravelAssistantProviderModeV1"
    static let customBaseURLKey = "AnyTravelAssistantCustomBaseURLV1"
    static let customModelKey = "AnyTravelAssistantCustomModelV1"

    var mode: AssistantProviderMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.providerModeKey) }
    }
    var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Self.customBaseURLKey) }
    }
    var customModel: String {
        didSet { defaults.set(customModel, forKey: Self.customModelKey) }
    }
    private(set) var hasCustomAPIKey: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secretStore: any AssistantSecretStoring
    @ObservationIgnored private let managedAPIKey: () -> String

    init(
        defaults: UserDefaults = .standard,
        secretStore: any AssistantSecretStoring = KeychainAssistantSecretStore(),
        managedAPIKey: @escaping () -> String = { EmbeddedServiceConfiguration.zaiAPIKey }
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
        self.managedAPIKey = managedAPIKey
        mode = defaults.string(forKey: Self.providerModeKey)
            .flatMap(AssistantProviderMode.init(rawValue:)) ?? .managed
        customBaseURL = defaults.string(forKey: Self.customBaseURLKey)
            ?? "https://open.bigmodel.cn/api/paas/v4"
        customModel = defaults.string(forKey: Self.customModelKey) ?? "glm-5.3-flash"
        hasCustomAPIKey = ((try? secretStore.read()) ?? nil)?.isEmpty == false
    }

    var isConfigured: Bool {
        switch mode {
        case .managed:
            let companionConfigured = !(defaults.string(forKey: PricingBackendClient.serviceURLDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return companionConfigured || !managedAPIKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:
            return !customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && hasCustomAPIKey
        }
    }

    func managedServiceURLText() -> String {
        defaults.string(forKey: PricingBackendClient.serviceURLDefaultsKey) ?? ""
    }

    func customAPIKey() throws -> String? {
        try secretStore.read()
    }

    func saveCustomAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AssistantSettingsError.emptyAPIKey }
        try secretStore.save(trimmed)
        hasCustomAPIKey = true
    }

    func deleteCustomAPIKey() throws {
        try secretStore.delete()
        hasCustomAPIKey = false
    }
}

struct KeychainAssistantSecretStore: AssistantSecretStoring {
    private let service = "com.anytravel.app.assistant"
    private let account = "custom-openai-compatible"

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AssistantSettingsError.keychain(status)
        }
        return value
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]
        let status: OSStatus
        if try read() == nil {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        } else {
            status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw AssistantSettingsError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AssistantSettingsError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum AssistantSettingsError: LocalizedError, Equatable {
    case emptyAPIKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey: "请先填写 API Key。"
        case let .keychain(status): "钥匙串暂时无法保存这把钥匙（\(status)）。"
        }
    }
}

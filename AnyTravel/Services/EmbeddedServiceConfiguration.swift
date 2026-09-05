import Foundation

enum EmbeddedServiceConfiguration {
    static var serviceURL: String {
        let override = value(infoKey: "AnyTravelServiceURL", environmentKey: "ANYTRAVEL_SERVICE_URL")
        return override.isEmpty ? publicDefaultsURL : override
    }

    private static let publicDefaultsURL: String = {
        guard let url = Bundle.main.url(forResource: "ServiceDefaults", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode(PublicDefaults.self, from: data) else { return "" }
        return values.serviceBaseURL
    }()

    private struct PublicDefaults: Decodable { var serviceBaseURL: String }

    static var rollingGoAPIKey: String {
        value(infoKey: "AnyTravelRollingGoAPIKey", environmentKey: "ROLLINGGO_API_KEY")
    }

    static var amapWebServiceKey: String {
        value(infoKey: "AnyTravelAMapWebServiceKey", environmentKey: "AMAP_API_KEY")
    }

    static var zaiAPIKey: String {
        value(infoKey: "AnyTravelZAIAPIKey", environmentKey: "ZAI_API_KEY")
    }

    private static func value(infoKey: String, environmentKey: String) -> String {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !environmentValue.isEmpty { return environmentValue }

        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleValue.isEmpty,
              !bundleValue.hasPrefix("$("),
              bundleValue.lowercased() != "undefined" else { return "" }
        return bundleValue
    }
}

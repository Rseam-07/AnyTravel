import Foundation

struct TravelAssistantPlaceContext: Codable, Equatable, Sendable {
    var name: String
    var dayIndex: Int
    var interest: String
}

struct TravelAssistantContext: Codable, Equatable, Sendable {
    var destination: String
    var dayCount: Int
    var budgetPerPerson: Int
    var pace: String
    var travelMode: String
    var selectedDayIndex: Int
    var interests: [String]
    var places: [TravelAssistantPlaceContext]
    var origin = ""
    var travelers = 1
    var startDate: String?
    var endDate: String?
    var longDistanceMode: String?
    var accommodationMaxNightlyPrice: Int?
    var accommodationSort = AccommodationSort.recommended.rawValue
}

struct TravelAssistantRequest: Codable, Equatable, Sendable {
    var input: String
    var context: TravelAssistantContext
}

enum TravelAssistantActionType: String, Codable, Sendable {
    case setDestination = "set_destination"
    case setOrigin = "set_origin"
    case setPace = "set_pace"
    case setTravelMode = "set_travel_mode"
    case setLongDistanceMode = "set_long_distance_mode"
    case setDayCount = "set_day_count"
    case setTravelers = "set_travelers"
    case setBudget = "set_budget"
    case setStartDate = "set_start_date"
    case setEndDate = "set_end_date"
    case setAccommodationMaxPrice = "set_accommodation_max_price"
    case setAccommodationSort = "set_accommodation_sort"
    case addInterest = "add_interest"
    case removeInterest = "remove_interest"
    case generatePlan = "generate_plan"
    case focusPlace = "focus_place"
    case removePlace = "remove_place"
}

struct TravelAssistantAction: Codable, Equatable, Sendable {
    var type: TravelAssistantActionType
    var value: String
}

struct TravelAssistantInterpretation: Codable, Equatable, Sendable {
    var reply: String
    var actions: [TravelAssistantAction]
    var model: String?
    var capturedAt: Date?
}

struct TravelAssistantClient {
    private let session: URLSession
    private let managedAPIKey: () -> String
    private let managedBaseURL: URL
    private let managedModel: String

    init(
        session: URLSession = .shared,
        managedAPIKey: @escaping () -> String = { EmbeddedServiceConfiguration.zaiAPIKey },
        managedBaseURL: URL = URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
        managedModel: String = "glm-5.3-flash"
    ) {
        self.session = session
        self.managedAPIKey = managedAPIKey
        self.managedBaseURL = managedBaseURL
        self.managedModel = managedModel
    }

    func interpret(
        input: String,
        context: TravelAssistantContext,
        settings: AssistantSettingsStore
    ) async throws -> TravelAssistantInterpretation {
        let requestPayload = TravelAssistantRequest(input: input, context: context)
        switch settings.mode {
        case .managed:
            return try await managedInterpretation(requestPayload, settings: settings)
        case .custom:
            return try await customInterpretation(requestPayload, settings: settings)
        }
    }

    private func managedInterpretation(
        _ payload: TravelAssistantRequest,
        settings: AssistantSettingsStore
    ) async throws -> TravelAssistantInterpretation {
        if let baseURL = Self.normalizedBaseURL(settings.managedServiceURLText(), allowLocalHTTP: true) {
            let endpoint = baseURL.appendingPathComponent("v1/assistant/interpret")
            let (data, response) = try await sendJSON(payload, to: endpoint)
            try Self.validate(response: response, data: data)
            do {
                let decoded = try JSONDecoder.anyTravelAssistant.decode(TravelAssistantInterpretation.self, from: data)
                return Self.validated(decoded, places: payload.context.places)
            } catch let error as TravelAssistantError {
                throw error
            } catch {
                throw TravelAssistantError.invalidResponse
            }
        }

        let apiKey = managedAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw TravelAssistantError.managedServiceNotConfigured }
        return try await openAIInterpretation(
            payload,
            baseURL: managedBaseURL,
            apiKey: apiKey,
            model: managedModel
        )
    }

    private func customInterpretation(
        _ payload: TravelAssistantRequest,
        settings: AssistantSettingsStore
    ) async throws -> TravelAssistantInterpretation {
        guard let baseURL = Self.normalizedBaseURL(settings.customBaseURL, allowLocalHTTP: true) else {
            throw TravelAssistantError.invalidBaseURL
        }
        guard let apiKey = try settings.customAPIKey(), !apiKey.isEmpty else {
            throw TravelAssistantError.missingAPIKey
        }
        let model = settings.customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TravelAssistantError.missingModel }
        return try await openAIInterpretation(payload, baseURL: baseURL, apiKey: apiKey, model: model)
    }

    private func openAIInterpretation(
        _ payload: TravelAssistantRequest,
        baseURL: URL,
        apiKey: String,
        model: String
    ) async throws -> TravelAssistantInterpretation {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        let body = OpenAIChatRequest(
            model: model,
            temperature: 0.1,
            responseFormat: .init(type: "json_object"),
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? "{}")
            ]
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw TravelAssistantError.network(error.localizedDescription) }
        try Self.validate(response: response, data: data)
        guard let content = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data).choices.first?.message.content,
              let contentData = Self.unfencedJSON(content).data(using: .utf8),
              var interpretation = try? JSONDecoder.anyTravelAssistant.decode(TravelAssistantInterpretation.self, from: contentData) else {
            throw TravelAssistantError.invalidResponse
        }
        interpretation.model = model
        interpretation.capturedAt = .now
        return Self.validated(interpretation, places: payload.context.places)
    }

    private func sendJSON<Value: Encodable>(_ value: Value, to url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(value)
        do { return try await session.data(for: request) }
        catch { throw TravelAssistantError.network(error.localizedDescription) }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw TravelAssistantError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let backend = try? JSONDecoder().decode(AssistantBackendError.self, from: data)
            throw TravelAssistantError.httpFailure(statusCode: http.statusCode, message: backend?.message ?? backend?.error)
        }
    }

    private static func validated(
        _ interpretation: TravelAssistantInterpretation,
        places: [TravelAssistantPlaceContext]
    ) -> TravelAssistantInterpretation {
        let canonicalPlaces = Dictionary(uniqueKeysWithValues: places.map { ($0.name.normalizedAssistantName, $0.name) })
        let actions = interpretation.actions.compactMap { action -> TravelAssistantAction? in
            switch action.type {
            case .setDestination, .setOrigin:
                let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                return TravelAssistantAction(type: action.type, value: String(value.prefix(80)))
            case .setPace:
                return ["relaxed", "balanced", "full"].contains(action.value) ? action : nil
            case .setTravelMode:
                return ["walking", "transit", "driving"].contains(action.value) ? action : nil
            case .setLongDistanceMode:
                return ["train", "flight", "driving", "coach", "auto"].contains(action.value) ? action : nil
            case .setDayCount:
                guard let number = Int(action.value) else { return nil }
                return TravelAssistantAction(type: .setDayCount, value: String(min(max(number, 1), 7)))
            case .setTravelers:
                guard let number = Int(action.value) else { return nil }
                return TravelAssistantAction(type: .setTravelers, value: String(min(max(number, 1), 8)))
            case .setBudget:
                guard let number = Int(action.value) else { return nil }
                return TravelAssistantAction(type: .setBudget, value: String(min(max(number, 1_000), 30_000)))
            case .setStartDate, .setEndDate:
                guard Self.dayFormatter.date(from: action.value) != nil else { return nil }
                return action
            case .setAccommodationMaxPrice:
                guard let number = Int(action.value) else { return nil }
                return TravelAssistantAction(type: action.type, value: String(min(max(number, 100), 10_000)))
            case .setAccommodationSort:
                return AccommodationSort(rawValue: action.value) == nil ? nil : action
            case .addInterest, .removeInterest:
                return TripInterest(rawValue: action.value) == nil ? nil : action
            case .generatePlan:
                return ["true", "false"].contains(action.value.lowercased()) ? action : nil
            case .focusPlace, .removePlace:
                guard let canonical = canonicalPlaces[action.value.normalizedAssistantName] else { return nil }
                return TravelAssistantAction(type: action.type, value: canonical)
            }
        }
        var result = interpretation
        result.reply = String(interpretation.reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        result.actions = Array(actions.prefix(16))
        return result
    }

    static func normalizedBaseURL(_ value: String, allowLocalHTTP: Bool) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed), let host = components.host else {
            return nil
        }
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        guard components.scheme == "https" || (allowLocalHTTP && isLocal && components.scheme == "http") else {
            return nil
        }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    private static func unfencedJSON(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```json") { result.removeFirst(7) }
        else if result.hasPrefix("```") { result.removeFirst(3) }
        if result.hasSuffix("```") { result.removeLast(3) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let systemPrompt = """
    你是 AnyTravel 的旅行意图控制器。用户可以从一句完全自由的中文开始，也可以修改现有计划。只返回 JSON：
    {"reply":"简洁、温暖、略有诗意的中文回应","actions":[{"type":"动作","value":"值"}]}
    允许动作：
    set_destination(城市或区域)、set_origin(出发城市)、set_day_count(1...7)、set_travelers(1...8)、set_budget(1000...30000)、set_pace(relaxed|balanced|full)、set_travel_mode(walking|transit|driving)、set_long_distance_mode(auto|train|flight|driving|coach)、set_start_date(yyyy-MM-dd)、set_end_date(yyyy-MM-dd)、set_accommodation_max_price(100...10000)、set_accommodation_sort(recommended|lowestPrice|closestToAttractions|closestToTransit)、add_interest/remove_interest(gardens|culture|food|nature|family|night)、generate_plan(true|false)、focus_place 与 remove_place（value 必须是 context.places 中完全相同的名称）。
    当用户明确要求规划、安排行程时返回 generate_plan=true；只是在探索目的地时不要擅自生成。地点会由地图服务核验，所以可以提取用户明确说出的目的地，但不要臆造。不要返回链接、代码或额外字段。无法安全操作时 actions 为空。
    """

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum TravelAssistantError: LocalizedError, Equatable {
    case managedServiceNotConfigured
    case invalidBaseURL
    case missingAPIKey
    case missingModel
    case invalidResponse
    case httpFailure(statusCode: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .managedServiceNotConfigured: "请先在设置中接通 AnyTravel 伴随服务。"
        case .invalidBaseURL: "模型服务地址无效；请使用 HTTPS，或本机调试地址。"
        case .missingAPIKey: "请先把自己的 API Key 安全存入钥匙串。"
        case .missingModel: "请填写模型名称。"
        case .invalidResponse: "智能向导返回了无法辨认的内容。"
        case let .httpFailure(statusCode, message): "智能向导暂时没有接通（\(statusCode)）\(message.map { "：\($0)" } ?? "")"
        case let .network(message): "智能向导暂时走散了：\(message)"
        }
    }
}

private struct AssistantBackendError: Decodable {
    var error: String?
    var message: String?
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable { var role: String; var content: String }
    struct ResponseFormat: Encodable { var type: String }

    var model: String
    var temperature: Double
    var responseFormat: ResponseFormat
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case responseFormat = "response_format"
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }
    var choices: [Choice]
}

private extension JSONDecoder {
    static let anyTravelAssistant: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }()
}

private extension String {
    var normalizedAssistantName: String {
        precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "zh-Hans"))
    }
}

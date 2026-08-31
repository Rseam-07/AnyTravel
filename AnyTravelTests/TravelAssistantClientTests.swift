import XCTest
@testable import AnyTravel

@MainActor
final class TravelAssistantClientTests: XCTestCase {
    override func tearDown() {
        AssistantURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testManagedModeUsesCompanionEndpointWithoutClientAuthorization() async throws {
        AssistantURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/assistant/interpret")
            XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
            let body = Data(#"{"reply":"脚步已经放慢。","actions":[{"type":"set_pace","value":"relaxed"}],"model":"glm-5.3-flash","capturedAt":"2026-08-31T12:00:00.000Z"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeContext(mode: .managed)

        let result = try await context.client.interpret(
            input: "轻松一点",
            context: travelContext,
            settings: context.settings
        )

        XCTAssertEqual(result.actions, [.init(type: .setPace, value: "relaxed")])
        XCTAssertEqual(result.model, "glm-5.3-flash")
    }

    func testCustomModeUsesKeychainSecretAndOpenAICompatiblePath() async throws {
        AssistantURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/paas/v4/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer test-secret")
            let content = #"{"reply":"把地图移到拙政园。","actions":[{"type":"focus_place","value":"拙政园"}]}"#
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content]]]
            ])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeContext(mode: .custom)
        context.settings.customBaseURL = "https://open.bigmodel.cn/api/paas/v4"
        context.settings.customModel = "glm-5.3-flash"
        try context.settings.saveCustomAPIKey("test-secret")

        let result = try await context.client.interpret(
            input: "看看拙政园",
            context: travelContext,
            settings: context.settings
        )

        XCTAssertEqual(result.actions, [.init(type: .focusPlace, value: "拙政园")])
        XCTAssertEqual(result.model, "glm-5.3-flash")
    }

    func testCustomResponseCannotOperateAnInventedPlace() async throws {
        AssistantURLProtocol.requestHandler = { request in
            let content = #"{"reply":"看看寒山寺。","actions":[{"type":"focus_place","value":"寒山寺"},{"type":"set_budget","value":"999999"}]}"#
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content]]]
            ])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let context = try makeContext(mode: .custom)
        try context.settings.saveCustomAPIKey("test-secret")

        let result = try await context.client.interpret(
            input: "看看寒山寺，预算多一些",
            context: travelContext,
            settings: context.settings
        )

        XCTAssertEqual(result.actions, [.init(type: .setBudget, value: "30000")])
    }

    private func makeContext(mode: AssistantProviderMode) throws -> (
        client: TravelAssistantClient,
        settings: AssistantSettingsStore,
        defaults: UserDefaults
    ) {
        let suiteName = "AnyTravel.TravelAssistantClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("https://companion.example/", forKey: PricingBackendClient.serviceURLDefaultsKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = MemoryAssistantSecretStore()
        let settings = AssistantSettingsStore(defaults: defaults, secretStore: secretStore)
        settings.mode = mode
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssistantURLProtocol.self]
        return (TravelAssistantClient(session: URLSession(configuration: configuration)), settings, defaults)
    }

    private var travelContext: TravelAssistantContext {
        TravelAssistantContext(
            destination: "苏州",
            dayCount: 3,
            budgetPerPerson: 3_000,
            pace: "full",
            travelMode: "walking",
            selectedDayIndex: 0,
            interests: ["culture", "gardens"],
            places: [
                .init(name: "拙政园", dayIndex: 0, interest: "gardens"),
                .init(name: "苏州博物馆", dayIndex: 0, interest: "culture")
            ]
        )
    }
}

@MainActor
private final class MemoryAssistantSecretStore: AssistantSecretStoring {
    private var value: String?

    func read() throws -> String? { value }
    func save(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

private final class AssistantURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

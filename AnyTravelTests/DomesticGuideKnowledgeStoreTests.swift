import XCTest
@testable import AnyTravel

@MainActor
final class DomesticGuideKnowledgeStoreTests: XCTestCase {
    func testPackagedKnowledgeResolvesCitySuffixAndRanksLandmarks() throws {
        let store = DomesticGuideKnowledgeStore(bundle: .main)

        let destination = try XCTUnwrap(store.resolveDestination("杭州市"))
        let places = store.places(for: "杭州")

        XCTAssertEqual(destination.title, "杭州")
        XCTAssertTrue(places.contains { $0.name == "西湖" })
        XCTAssertEqual(places.first?.popularity?.rank, 1)
        XCTAssertTrue(places.allSatisfy { $0.source == "AnyTravel 目的地资料（非实时）" })
    }
}

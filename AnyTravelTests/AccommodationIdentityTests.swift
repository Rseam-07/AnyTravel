import XCTest
@testable import AnyTravel

@MainActor
final class AccommodationIdentityTests: XCTestCase {
    func testNearbyAliasesFromOneBrandMatch() {
        XCTAssertTrue(
            AccommodationIdentity.isSameProperty(
                name: "苏州诺富特酒店",
                coordinate: Coordinate(latitude: 31.3000, longitude: 120.6000),
                brand: "雅高",
                and: "Novotel Suzhou",
                coordinate: Coordinate(latitude: 31.3002, longitude: 120.6002),
                brand: "Accor"
            )
        )
    }

    func testDifferentBrandsInOneBuildingDoNotMergeByCoordinateAlone() {
        XCTAssertFalse(
            AccommodationIdentity.isSameProperty(
                name: "城市之光酒店",
                coordinate: Coordinate(latitude: 31.3000, longitude: 120.6000),
                brand: nil,
                and: "河畔精选酒店",
                coordinate: Coordinate(latitude: 31.30001, longitude: 120.60001),
                brand: nil
            )
        )
    }

    func testSameGenericNameFarAwayRemainsSeparate() {
        XCTAssertFalse(
            AccommodationIdentity.isSameProperty(
                name: "城市便捷酒店",
                coordinate: Coordinate(latitude: 31.20, longitude: 120.50),
                brand: nil,
                and: "城市便捷酒店",
                coordinate: Coordinate(latitude: 31.30, longitude: 120.70),
                brand: nil
            )
        )
    }

    func testNearbySisterBrandsRemainSeparate() {
        for (first, second, group) in [
            ("苏州诺富特酒店", "苏州美居酒店", "雅高"),
            ("苏州希尔顿酒店", "苏州希尔顿花园酒店", "Hilton"),
            ("苏州皇冠假日酒店", "苏州假日酒店", "IHG")
        ] {
            XCTAssertFalse(AccommodationIdentity.isSameProperty(
                name: first, coordinate: Coordinate(latitude: 31.30, longitude: 120.60), brand: group,
                and: second, coordinate: Coordinate(latitude: 31.30001, longitude: 120.60001), brand: group
            ), "\(first) and \(second) are different brands")
        }
    }

    func testEmptyNormalizedNamesAreNotIdentityEvidence() {
        XCTAssertFalse(AccommodationIdentity.isSameProperty(
            name: "酒店", coordinate: Coordinate(latitude: 31.30, longitude: 120.60), brand: nil,
            and: "宾馆", coordinate: Coordinate(latitude: 31.30, longitude: 120.60), brand: nil
        ))
    }
}

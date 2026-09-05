import CoreLocation
import Foundation

/// One conservative identity rule for MapKit, RollingGo and hotel websites.
/// Coordinates alone are not enough: two brands can share the same building.
enum AccommodationIdentity {
    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .replacingOccurrences(of: "酒店", with: "")
            .replacingOccurrences(of: "宾馆", with: "")
            .replacingOccurrences(of: "民宿", with: "")
            .replacingOccurrences(of: "旅馆", with: "")
            .lowercased()
    }

    static func namesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedName(lhs)
        let right = normalizedName(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        return min(left.count, right.count) >= 4 && (left.contains(right) || right.contains(left))
    }

    static func isSameProperty(
        name lhsName: String,
        coordinate lhsCoordinate: Coordinate,
        brand lhsBrand: String?,
        and rhsName: String,
        coordinate rhsCoordinate: Coordinate,
        brand rhsBrand: String?
    ) -> Bool {
        let distance = CLLocation(
            latitude: lhsCoordinate.latitude,
            longitude: lhsCoordinate.longitude
        ).distance(from: CLLocation(latitude: rhsCoordinate.latitude, longitude: rhsCoordinate.longitude))
        let leftName = normalizedName(lhsName)
        let rightName = normalizedName(rhsName)
        guard !leftName.isEmpty, !rightName.isEmpty else { return false }
        let leftBrand = hotelBrand(name: lhsName, brand: lhsBrand)
        let rightBrand = hotelBrand(name: rhsName, brand: rhsBrand)
        if let leftBrand, let rightBrand, leftBrand != rightBrand { return false }
        if leftName == rightName, distance <= 250 { return true }
        if namesLikelyMatch(lhsName, rhsName), distance <= 150 { return true }
        return distance <= 80 && leftBrand != nil && leftBrand == rightBrand
    }

    static func officialWebsite(name: String, brand: String?) -> URL? {
        let value = "\(brand ?? "") \(name)".lowercased()
        guard let match = officialSites.first(where: { entry in
            entry.0.contains(where: value.contains)
        }) else { return nil }
        return URL(string: match.1)
    }

    private static func hotelBrand(name: String, brand: String?) -> String? {
        func match(_ value: String) -> String? {
            let normalized = normalizedName(value)
            return hotelBrands.first(where: { $0.1.contains(where: normalized.contains) })?.0
        }
        // Supplier brand fields often contain a corporate group, not a brand.
        return match(name) ?? match(brand ?? "")
    }

    // Match specific sub-brands before their parent-name substrings.
    private static let hotelBrands: [(String, [String])] = [
        ("grand-mercure", ["美爵", "grandmercure"]),
        ("ibis-styles", ["宜必思尚品", "ibisstyles"]),
        ("pullman", ["铂尔曼", "pullman"]),
        ("novotel", ["诺富特", "novotel"]),
        ("mercure", ["美居", "mercure"]),
        ("ibis", ["宜必思", "ibis"]),
        ("sofitel", ["索菲特", "sofitel"]),
        ("fairmont", ["费尔蒙", "fairmont"]),
        ("hampton", ["欢朋", "hampton"]),
        ("hilton-garden", ["希尔顿花园", "hiltongarden"]),
        ("doubletree", ["逸林", "doubletree"]),
        ("conrad", ["康莱德", "conrad"]),
        ("waldorf", ["华尔道夫", "waldorf"]),
        ("hilton", ["希尔顿", "hilton"]),
        ("jw-marriott", ["jw万豪", "jwmarriott"]),
        ("courtyard", ["万怡", "courtyard"]),
        ("sheraton", ["喜来登", "sheraton"]),
        ("westin", ["威斯汀", "westin"]),
        ("ritz-carlton", ["丽思卡尔顿", "ritzcarlton"]),
        ("le-meridien", ["艾美", "lemeridien"]),
        ("marriott", ["万豪", "marriott"]),
        ("holiday-inn-express", ["智选假日", "holidayinnexpress"]),
        ("crowne-plaza", ["皇冠假日", "crowneplaza"]),
        ("holiday-inn", ["假日", "holidayinn"]),
        ("indigo", ["英迪格", "indigo"]),
        ("voco", ["voco"]),
        ("intercontinental", ["洲际", "intercontinental"])
    ]

    private static let officialSites: [([String], String)] = [
        (["雅高", "铂尔曼", "pullman", "诺富特", "novotel", "美居", "mercure", "宜必思", "ibis", "索菲特", "sofitel", "费尔蒙", "fairmont"], "https://all.accor.com/"),
        (["希尔顿", "康莱德", "华尔道夫", "欢朋", "hampton", "hilton", "conrad", "waldorf"], "https://www.hilton.com.cn/"),
        (["万豪", "喜来登", "威斯汀", "丽思卡尔顿", "艾美", "marriott", "sheraton", "westin", "ritz"], "https://www.marriott.com.cn/"),
        (["洲际", "皇冠假日", "智选假日", "英迪格", "voco", "ihg", "intercontinental"], "https://www.ihg.com.cn/"),
        (["汉庭", "全季", "桔子", "华住", "h world"], "https://www.hworld.com/"),
        (["亚朵", "atour"], "https://www.yaduo.com/"),
        (["锦江", "维也纳", "麗枫", "希岸"], "https://www.jinjianghotels.com/"),
        (["凯悦", "hyatt"], "https://www.hyatt.com/"),
        (["香格里拉", "shangri-la"], "https://www.shangri-la.com/cn/"),
        (["首旅", "如家", "homeinn"], "https://www.bthhotels.com/"),
        (["格林", "green tree"], "https://www.998.com/")
    ]
}

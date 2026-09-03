import Foundation

enum ProviderAccount: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case ctrip
    case qunar
    case tongcheng
    case fliggy
    case tripCom
    case railway12306

    var id: Self { self }

    var title: String {
        switch self {
        case .ctrip: "携程"
        case .qunar: "去哪儿"
        case .tongcheng: "同程旅行"
        case .fliggy: "飞猪旅行"
        case .tripCom: "Trip.com"
        case .railway12306: "铁路12306"
        }
    }

    var symbolName: String {
        switch self {
        case .ctrip, .qunar, .tongcheng, .fliggy, .tripCom: "bed.double.fill"
        case .railway12306: "tram.fill"
        }
    }

    var loginURL: URL {
        switch self {
        case .ctrip: URL(string: "https://passport.ctrip.com/user/login")!
        case .qunar: URL(string: "https://user.qunar.com/passport/login.jsp")!
        case .tongcheng: URL(string: "https://m.ly.com/")!
        case .fliggy: URL(string: "https://login.taobao.com/member/login.jhtml")!
        case .tripCom: URL(string: "https://www.trip.com/user/login/")!
        case .railway12306: URL(string: "https://kyfw.12306.cn/otn/resources/login.html")!
        }
    }

    var cookieDomains: [String] {
        switch self {
        case .ctrip: ["ctrip.com", "c-ctrip.com"]
        case .qunar: ["qunar.com"]
        case .tongcheng: ["ly.com", "17u.cn", "elong.com"]
        case .fliggy: ["taobao.com", "fliggy.com"]
        case .tripCom: ["trip.com"]
        case .railway12306: ["12306.cn"]
        }
    }

    init?(travelProvider: TravelProvider) {
        switch travelProvider {
        case .ctrip: self = .ctrip
        case .qunar: self = .qunar
        case .tongcheng: self = .tongcheng
        case .fliggy: self = .fliggy
        case .tripCom: self = .tripCom
        case .railway12306: self = .railway12306
        case .skyscanner, .rollingGo, .propertyOfficial, .anyTravelEstimate: return nil
        }
    }
}

struct ProviderBrowserDestination: Identifiable, Hashable, Sendable {
    let id: UUID
    let provider: ProviderAccount
    let url: URL
    let title: String

    init(id: UUID = UUID(), provider: ProviderAccount, url: URL, title: String) {
        self.id = id
        self.provider = provider
        self.url = url
        self.title = title
    }
}

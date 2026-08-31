import Foundation

struct TripLogistics: Codable, Equatable, Hashable, Sendable {
    var origin = ""
    var startDate: Date?
    var endDate: Date?
    var travelers = 1
    var preferredLongDistanceMode: LongDistanceMode?
    var skipAccommodation = false
    var skipTransport = false

    var hasDates: Bool { startDate != nil && endDate != nil }

    var nights: Int {
        guard !skipAccommodation else { return 0 }
        guard let startDate, let endDate else { return 0 }
        return max(Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
    }
}

enum LongDistanceMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case train
    case flight
    case driving
    case coach

    var id: Self { self }

    var title: String {
        switch self {
        case .train: "高铁/火车"
        case .flight: "飞机"
        case .driving: "自驾"
        case .coach: "长途客运"
        }
    }

    var shortTitle: String {
        switch self {
        case .train: "高铁"
        case .flight: "飞机"
        case .driving: "自驾"
        case .coach: "客运"
        }
    }

    var symbolName: String {
        switch self {
        case .train: "tram.fill"
        case .flight: "airplane"
        case .driving: "car.fill"
        case .coach: "bus.fill"
        }
    }
}

enum TravelProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case ctrip
    case qunar
    case tripCom
    case skyscanner
    case rollingGo
    case railway12306
    case propertyOfficial
    case anyTravelEstimate

    var id: Self { self }

    var title: String {
        switch self {
        case .ctrip: "携程"
        case .qunar: "去哪儿"
        case .tripCom: "Trip.com"
        case .skyscanner: "Skyscanner"
        case .rollingGo: "道旅 RollingGo"
        case .railway12306: "铁路12306"
        case .propertyOfficial: "住宿官网"
        case .anyTravelEstimate: "AnyTravel 估算"
        }
    }
}

enum QuoteKind: String, Codable, Hashable, Sendable {
    case live
    case indicative
    case budgetEstimate
    case demo
    case requiresPartnerAccess
    case checkOnProvider

    var title: String {
        switch self {
        case .live: "实时价"
        case .indicative: "参考价"
        case .budgetEstimate: "预算估算"
        case .demo: "演示价"
        case .requiresPartnerAccess: "待渠道授权"
        case .checkOnProvider: "到渠道查询"
        }
    }
}

enum PriceUnit: String, Codable, Hashable, Sendable {
    case perNight
    case perPerson
    case total

    var suffix: String {
        switch self {
        case .perNight: "/晚"
        case .perPerson: "/人"
        case .total: ""
        }
    }
}

struct ProviderQuote: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let provider: TravelProvider
    var amountCNY: Int?
    var unit: PriceUnit
    var kind: QuoteKind
    var capturedAt: Date?
    var bookingURL: URL?
    var note: String

    init(
        id: UUID = UUID(),
        provider: TravelProvider,
        amountCNY: Int? = nil,
        unit: PriceUnit,
        kind: QuoteKind,
        capturedAt: Date? = nil,
        bookingURL: URL? = nil,
        note: String
    ) {
        self.id = id
        self.provider = provider
        self.amountCNY = amountCNY
        self.unit = unit
        self.kind = kind
        self.capturedAt = capturedAt
        self.bookingURL = bookingURL
        self.note = note
    }

    var priceText: String {
        guard let amountCNY else { return kind.title }
        return "¥\(amountCNY.formatted(.number.grouping(.automatic)))\(unit.suffix)"
    }

    var freshnessText: String? {
        guard let capturedAt else { return nil }
        let minutes = max(Int(Date.now.timeIntervalSince(capturedAt) / 60), 0)
        switch minutes {
        case 0...2: return "刚刚"
        case 3..<30: return "\(minutes)分钟前"
        case 30..<120: return "\(minutes)分钟前 · 请复核"
        default: return capturedAt.formatted(date: .abbreviated, time: .shortened) + " · 请刷新"
        }
    }

    var isStale: Bool {
        guard let capturedAt else { return false }
        return Date.now.timeIntervalSince(capturedAt) >= 30 * 60
    }
}

enum AccessPointKind: String, Codable, Hashable, Sendable {
    case rail
    case airport
    case metro

    var title: String {
        switch self {
        case .rail: "高铁站"
        case .airport: "机场"
        case .metro: "地铁站"
        }
    }

    var symbolName: String {
        switch self {
        case .rail: "tram.fill"
        case .airport: "airplane"
        case .metro: "m.circle.fill"
        }
    }
}

struct AccessPoint: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let coordinate: Coordinate
    let kind: AccessPointKind

    init(id: UUID = UUID(), name: String, coordinate: Coordinate, kind: AccessPointKind) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.kind = kind
    }
}

struct AccommodationOption: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let coordinate: Coordinate
    var officialWebsiteURL: URL?
    var attractionDistanceMeters: Double
    var accessDistances: [AccessPointKind: Double]
    var nearestAccessPoints: [AccessPointKind: AccessPoint]
    var quotes: [ProviderQuote]
    var recommendationReasons: [String]

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        coordinate: Coordinate,
        officialWebsiteURL: URL? = nil,
        attractionDistanceMeters: Double,
        accessDistances: [AccessPointKind: Double] = [:],
        nearestAccessPoints: [AccessPointKind: AccessPoint] = [:],
        quotes: [ProviderQuote] = [],
        recommendationReasons: [String] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.officialWebsiteURL = officialWebsiteURL
        self.attractionDistanceMeters = attractionDistanceMeters
        self.accessDistances = accessDistances
        self.nearestAccessPoints = nearestAccessPoints
        self.quotes = quotes
        self.recommendationReasons = recommendationReasons
    }

    var bestPricedQuote: ProviderQuote? {
        quotes
            .filter { $0.amountCNY != nil && $0.kind != .demo }
            .min { ($0.amountCNY ?? .max) < ($1.amountCNY ?? .max) }
    }
}

struct TransportOption: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let mode: LongDistanceMode
    var title: String
    var originName: String
    var destinationName: String
    var durationMinutes: Int?
    var departureTime: Date?
    var arrivalTime: Date?
    var arrivalAccessPoint: AccessPoint?
    var hotelTransferMeters: Double?
    var quotes: [ProviderQuote]
    var recommendationReasons: [String]
    var isRecommended: Bool

    init(
        id: UUID = UUID(),
        mode: LongDistanceMode,
        title: String,
        originName: String,
        destinationName: String,
        durationMinutes: Int? = nil,
        departureTime: Date? = nil,
        arrivalTime: Date? = nil,
        arrivalAccessPoint: AccessPoint? = nil,
        hotelTransferMeters: Double? = nil,
        quotes: [ProviderQuote] = [],
        recommendationReasons: [String] = [],
        isRecommended: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.originName = originName
        self.destinationName = destinationName
        self.durationMinutes = durationMinutes
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.arrivalAccessPoint = arrivalAccessPoint
        self.hotelTransferMeters = hotelTransferMeters
        self.quotes = quotes
        self.recommendationReasons = recommendationReasons
        self.isRecommended = isRecommended
    }
}

struct LogisticsSnapshot: Codable, Hashable, Sendable {
    var accommodations: [AccommodationOption]
    var selectedAccommodationID: AccommodationOption.ID?
    var transportOptions: [TransportOption]
    var selectedTransportID: TransportOption.ID?
}

enum QuoteRefreshState: Equatable, Sendable {
    case idle
    case needsDates
    case needsService
    case stale(String)
    case refreshing
    case updated(capturedAt: Date, count: Int, cached: Bool)
    case partial(capturedAt: Date?, count: Int, message: String)
    case noResults(capturedAt: Date?, message: String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "价格会在条件齐全后抵达"
        case .needsDates: "日期还没有落定"
        case .needsService: "报价驿站尚未连接"
        case .stale: "行程刚刚有了变化"
        case .refreshing: "正在带回这一刻的价格"
        case .updated: "这一刻的价格已经抵达"
        case .partial: "部分价格已经抵达"
        case .noResults: "这一次还没有找到可用价格"
        case .failed: "价格在途中暂时走散了"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "添上日期并连接报价节点后，可以读取渠道报价。"
        case .needsDates:
            "添上出发与返程日，才能按当日库存核价。"
        case .needsService:
            "在设置中填入开源报价节点地址，密钥仍只留在服务端。"
        case let .stale(message), let .failed(message):
            message
        case .refreshing:
            "住宿、班次与余票会逐一更新，已有方案仍可继续查看。"
        case let .updated(capturedAt, count, cached):
            "共带回\(count)条结果 · \(capturedAt.formatted(date: .omitted, time: .shortened))\(cached ? " · 命中短时缓存" : "")"
        case let .partial(capturedAt, count, message):
            "已带回\(count)条结果\(capturedAt.map { " · \($0.formatted(date: .omitted, time: .shortened))" } ?? "")；\(message)"
        case let .noResults(capturedAt, message):
            "\(capturedAt.map { "\($0.formatted(date: .omitted, time: .shortened)) · " } ?? "")\(message)"
        }
    }

    var symbolName: String {
        switch self {
        case .idle, .needsDates: "calendar.badge.clock"
        case .needsService: "network.slash"
        case .stale: "arrow.trianglehead.2.clockwise.rotate.90"
        case .refreshing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .updated: "checkmark.seal.fill"
        case .partial: "circle.lefthalf.filled"
        case .noResults: "magnifyingglass"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var actionTitle: String? {
        switch self {
        case .idle, .needsDates: "补充条件"
        case .needsService: "去连接"
        case .stale, .partial, .noResults, .failed: "再试一次"
        case .refreshing, .updated: nil
        }
    }
}

enum ExpenseSource: String, Codable, Hashable, Sendable {
    case live
    case estimate
    case budgetEnvelope

    var title: String {
        switch self {
        case .live: "已报价"
        case .estimate: "估算"
        case .budgetEnvelope: "预算额度"
        }
    }
}

struct ExpenseLine: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let amountCNY: Int
    let source: ExpenseSource
}

struct ScheduleItem: Hashable, Identifiable, Sendable {
    let id: String
    let timeText: String
    let title: String
    let detail: String
    let placeID: TravelPlace.ID?
}

enum PlanMapFocus: String, CaseIterable, Identifiable {
    case itinerary
    case accommodation
    case transport
    case budget

    var id: Self { self }

    var title: String {
        switch self {
        case .itinerary: "行程"
        case .accommodation: "住宿"
        case .transport: "交通"
        case .budget: "费用"
        }
    }

    var symbolName: String {
        switch self {
        case .itinerary: "map.fill"
        case .accommodation: "bed.double.fill"
        case .transport: "tram.fill"
        case .budget: "list.bullet.rectangle"
        }
    }
}

extension Double {
    var anyTravelDistanceText: String {
        if self >= 1_000 { return String(format: "%.1f公里", self / 1_000) }
        return "\(Int(self.rounded()))米"
    }
}

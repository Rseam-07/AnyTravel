import Foundation

nonisolated struct AdjustmentIntent: Equatable, Sendable {
    var destination: String?
    var origin: String?
    var pace: TripPace?
    var travelMode: TravelMode?
    var longDistanceMode: LongDistanceMode?
    var dayCount: Int?
    var travelers: Int?
    var budgetPerPerson: Int?
    var startDate: Date?
    var endDate: Date?
    var accommodationMaxPrice: Int?
    var accommodationSort: AccommodationSort?
    var shouldGeneratePlan = false
    var addedInterests: Set<TripInterest> = []
    var removedInterests: Set<TripInterest> = []
    var excludedPlaceTerm: String?

    var isRecognized: Bool {
        destination != nil
            || origin != nil
            || pace != nil
            || travelMode != nil
            || longDistanceMode != nil
            || dayCount != nil
            || travelers != nil
            || budgetPerPerson != nil
            || startDate != nil
            || endDate != nil
            || accommodationMaxPrice != nil
            || accommodationSort != nil
            || shouldGeneratePlan
            || !addedInterests.isEmpty
            || !removedInterests.isEmpty
            || excludedPlaceTerm != nil
    }
}

nonisolated struct PlannerIntentParser {
    nonisolated init() {}

    nonisolated func parse(_ input: String) -> AdjustmentIntent {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return AdjustmentIntent() }

        var intent = AdjustmentIntent()
        let isRemoval = ["不要", "去掉", "删除", "不想去"].contains { text.contains($0) }

        intent.origin = firstString(
            matching: #"(?:从|由)\s*([\p{Han}A-Za-z·]{2,24}?)(?=出发|启程|去|到)"#,
            in: text
        )
        intent.destination = firstString(
            matching: #"(?:想去|要去|前往|抵达|去|到)\s*([\p{Han}A-Za-z0-9·]{2,24}?)(?=玩|旅游|旅行|度假|出差|待|逛|，|,|。|；|;|\s|$)"#,
            in: text
        )
        intent.shouldGeneratePlan = ["规划", "安排行程", "做个行程", "生成行程", "排一下"].contains { text.contains($0) }

        if text.contains("轻松") || text.contains("松弛") || text.contains("少一点") {
            intent.pace = .relaxed
        } else if text.contains("充实") || text.contains("紧凑") || text.contains("多安排") {
            intent.pace = .full
        } else if text.contains("适中") || text.contains("正常节奏") {
            intent.pace = .balanced
        }

        if text.contains("公交") || text.contains("地铁") || text.contains("公共交通") {
            intent.travelMode = .transit
        } else if text.contains("开车") || text.contains("驾车") || text.contains("自驾") {
            intent.travelMode = .driving
        } else if text.contains("步行") || text.contains("走路") || text.contains("慢逛") {
            intent.travelMode = .walking
        }

        if text.contains("高铁") || text.contains("火车") || text.contains("动车") {
            intent.longDistanceMode = .train
        } else if text.contains("飞机") || text.contains("航班") || text.contains("机票") {
            intent.longDistanceMode = .flight
        } else if text.contains("自驾去") || text.contains("开车去") {
            intent.longDistanceMode = .driving
        } else if text.contains("大巴") || text.contains("长途客运") {
            intent.longDistanceMode = .coach
        }

        let interestKeywords: [TripInterest: [String]] = [
            .gardens: ["园林", "建筑", "古建"],
            .culture: ["博物馆", "人文", "展览"],
            .food: ["美食", "餐厅", "吃"],
            .nature: ["自然", "公园", "户外"],
            .family: ["亲子", "孩子", "儿童"],
            .night: ["夜游", "夜景", "晚上"]
        ]

        for (interest, keywords) in interestKeywords where keywords.contains(where: text.contains) {
            if isRemoval {
                intent.removedInterests.insert(interest)
            } else {
                intent.addedInterests.insert(interest)
            }
        }

        intent.dayCount = firstInteger(matching: #"(\d{1,2})\s*天"#, in: text).map { min(max($0, 1), 7) }
        intent.budgetPerPerson = firstInteger(matching: #"(\d{2,6})\s*(?:元|块)"#, in: text)
        intent.travelers = firstInteger(matching: #"(\d{1,2})\s*(?:个)?(?:人|位)"#, in: text).map { min(max($0, 1), 8) }
            ?? chineseTravelerCount(in: text)
        intent.accommodationMaxPrice = firstInteger(
            matching: #"(?:酒店|住宿|房价|民宿).{0,10}?(?:不超过|以内|以下|最多|预算)\s*(\d{2,5})"#,
            in: text
        ) ?? firstInteger(
            matching: #"(\d{2,5})\s*(?:元|块).{0,4}?(?:一晚|每晚|/晚)"#,
            in: text
        )
        if text.contains("最便宜") || text.contains("价格最低") {
            intent.accommodationSort = .lowestPrice
        } else if text.contains("离景点近") || text.contains("景点最近") {
            intent.accommodationSort = .closestToAttractions
        } else if text.contains("离地铁近") || text.contains("交通方便") || text.contains("车站近") {
            intent.accommodationSort = .closestToTransit
        }

        let dates = parsedDates(in: text)
        intent.startDate = dates.first
        intent.endDate = dates.dropFirst().first

        if isRemoval, intent.removedInterests.isEmpty {
            for prefix in ["不要", "去掉", "删除", "不想去"] {
                if let range = text.range(of: prefix) {
                    let term = text[range.upperBound...]
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if !term.isEmpty {
                        intent.excludedPlaceTerm = term
                    }
                    break
                }
            }
        }

        return intent
    }

    nonisolated private func firstInteger(matching pattern: String, in text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }

        return Int(text[range])
    }

    nonisolated private func firstString(matching pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }

    nonisolated private func chineseTravelerCount(in text: String) -> Int? {
        let values = ["一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8]
        for (word, count) in values where text.contains("\(word)人") || text.contains("\(word)个人") || text.contains("\(word)位") || text.contains("一家\(word)口") {
            return count
        }
        return text.contains("一家三口") ? 3 : nil
    }

    nonisolated private func parsedDates(in text: String) -> [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let year = calendar.component(.year, from: startOfToday)
        let pattern = #"(?:(\d{4})[年\-/])?(\d{1,2})[月\-/](\d{1,2})日?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let monthRange = Range(match.range(at: 2), in: text),
                  let dayRange = Range(match.range(at: 3), in: text),
                  let month = Int(text[monthRange]),
                  let day = Int(text[dayRange])
            else { return nil }
            let explicitYear = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
            var components = DateComponents(year: explicitYear ?? year, month: month, day: day)
            var date = calendar.date(from: components).map(calendar.startOfDay(for:))
            if explicitYear == nil, let value = date, value < startOfToday {
                components.year = year + 1
                date = calendar.date(from: components).map(calendar.startOfDay(for:))
            }
            return date
        }
    }
}

import Foundation

nonisolated struct AdjustmentIntent: Equatable, Sendable {
    var pace: TripPace?
    var travelMode: TravelMode?
    var dayCount: Int?
    var budgetPerPerson: Int?
    var addedInterests: Set<TripInterest> = []
    var removedInterests: Set<TripInterest> = []
    var excludedPlaceTerm: String?

    var isRecognized: Bool {
        pace != nil
            || travelMode != nil
            || dayCount != nil
            || budgetPerPerson != nil
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
}

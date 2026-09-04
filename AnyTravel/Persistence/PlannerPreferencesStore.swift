import Foundation

struct PlannerPreferences: Codable, Equatable, Sendable {
    var origin: String
    var travelers: Int
    var budgetPerPerson: Int
    var pace: TripPace

    static let standard = PlannerPreferences(
        origin: "",
        travelers: 1,
        budgetPerPerson: 3_000,
        pace: .relaxed
    )
}

struct PlannerPreferencesStore {
    private static let storageKey = "AnyTravelPlannerPreferencesV1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PlannerPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let preferences = try? JSONDecoder().decode(PlannerPreferences.self, from: data) else {
            return .standard
        }
        return preferences
    }

    func save(from draft: TripDraft) {
        let preferences = PlannerPreferences(
            origin: draft.logistics.origin.trimmingCharacters(in: .whitespacesAndNewlines),
            travelers: min(max(draft.logistics.travelers, 1), 8),
            budgetPerPerson: min(max(draft.budgetPerPerson, 1_000), 30_000),
            pace: .relaxed
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func applyingSavedPreferences(to draft: TripDraft = TripDraft()) -> TripDraft {
        let preferences = load()
        var result = draft
        result.logistics.origin = preferences.origin
        result.logistics.travelers = preferences.travelers
        result.budgetPerPerson = preferences.budgetPerPerson
        result.pace = preferences.pace
        if !result.logistics.hasDates {
            let calendar = Calendar.current
            let start = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: 7, to: .now) ?? .now
            )
            result.logistics.startDate = start
            result.logistics.endDate = calendar.date(
                byAdding: .day,
                value: max(result.dayCount - 1, 1),
                to: start
            )
        }
        return result
    }
}

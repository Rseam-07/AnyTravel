import Foundation
import Observation

@Observable
final class TripStore {
    private(set) var trips: [SavedTrip] = []
    private(set) var lastErrorMessage: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func save(_ trip: SavedTrip) throws {
        let previousTrips = trips
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.insert(trip, at: 0)
        }
        trips.sort { $0.createdAt > $1.createdAt }
        do {
            try persist()
        } catch {
            trips = previousTrips
            throw error
        }
    }

    func delete(_ trip: SavedTrip) throws {
        let previousTrips = trips
        trips.removeAll { $0.id == trip.id }
        do {
            try persist()
        } catch {
            trips = previousTrips
            throw error
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            trips = try Self.decoder.decode([SavedTrip].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            lastErrorMessage = "已保存行程暂时无法读取：\(error.localizedDescription)"
            trips = []
        }
    }

    private func persist() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try Self.encoder.encode(trips)
            try data.write(to: fileURL, options: .atomic)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw PlanningError.saveFailed
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("AnyTravel", isDirectory: true)
            .appendingPathComponent("saved-trips.json", isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

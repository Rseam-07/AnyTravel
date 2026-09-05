import Foundation
import Observation

@Observable
final class TripStore {
    private(set) var trips: [SavedTrip] = []
    private(set) var lastErrorMessage: String?

    private let fileURL: URL
    private var primaryWasUnreadable = false

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
            primaryWasUnreadable = true
            do {
                let backup = try Data(contentsOf: backupURL)
                trips = try Self.decoder.decode([SavedTrip].self, from: backup)
                    .sorted { $0.createdAt > $1.createdAt }
                lastErrorMessage = "最近一次旅册未能读取，已找回上次备份；原文件会先另存保留。"
            } catch {
                lastErrorMessage = "已保存行程暂时无法读取，原文件会保留，不会被新行程静默覆盖。"
                trips = []
            }
        }
    }

    private func persist() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            var recoveryCopy: URL?
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let previous = try Data(contentsOf: fileURL)
                if primaryWasUnreadable {
                    let recoveryURL = nextRecoveryURL()
                    try previous.write(to: recoveryURL, options: .atomic)
                    recoveryCopy = recoveryURL
                } else {
                    _ = try Self.decoder.decode([SavedTrip].self, from: previous)
                    try previous.write(to: backupURL, options: .atomic)
                }
            }
            let data = try Self.encoder.encode(trips)
            try data.write(to: fileURL, options: .atomic)
            primaryWasUnreadable = false
            if let recoveryCopy {
                lastErrorMessage = "旧的未读旅册已另存为 \(recoveryCopy.lastPathComponent)，新记录已经安全保存。"
            } else {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            throw PlanningError.saveFailed
        }
    }

    private var backupURL: URL {
        fileURL.appendingPathExtension("backup")
    }

    private func nextRecoveryURL() -> URL {
        let base = fileURL.appendingPathExtension("unreadable")
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        return fileURL.appendingPathExtension("unreadable-\(UUID().uuidString)")
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

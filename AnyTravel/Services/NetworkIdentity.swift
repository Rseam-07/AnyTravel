import Foundation

/// Keeps versioned request identity in one place so provider clients cannot
/// silently ship stale hard-coded app versions.
enum NetworkIdentity {
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "AnyTravel/\(version?.nonEmpty ?? "development") (iOS; +https://github.com/Rseam-07/AnyTravel)"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

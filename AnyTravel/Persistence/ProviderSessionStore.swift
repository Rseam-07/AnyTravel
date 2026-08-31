import Foundation
import Observation
import WebKit

@Observable
final class ProviderSessionStore {
    private(set) var connectedAt: [ProviderAccount: Date] = [:]
    private let defaults: UserDefaults
    private let storageKey = "AnyTravelProviderSessionsV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func markSessionReady(_ provider: ProviderAccount) {
        connectedAt[provider] = .now
        persist()
    }

    func isConnected(_ provider: ProviderAccount) -> Bool {
        connectedAt[provider] != nil
    }

    func disconnect(_ provider: ProviderAccount) async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where provider.cookieDomains.contains(where: { cookie.domain.hasSuffix($0) }) {
            await cookieStore.deleteCookie(cookie)
        }
        connectedAt[provider] = nil
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ProviderAccount: Date].self, from: data) else {
            return
        }
        connectedAt = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connectedAt) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            delete(cookie) { continuation.resume() }
        }
    }
}

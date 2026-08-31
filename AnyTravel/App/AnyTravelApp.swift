import SwiftUI

@main
struct AnyTravelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(AnyTravelPalette.route)
        }
    }
}

import SwiftUI

enum AnyTravelPalette {
    // Asset-catalog colors are resolved by SwiftUI on its render executor. Avoid
    // UIColor dynamic-provider closures here: SwiftUI may resolve them off the
    // main actor while animating and Swift 6 correctly traps that mismatch.
    static let route = Color("AnyTravelRoute")
    static let routeDark = Color("AnyTravelRouteDark")
    static let warm = Color("AnyTravelWarm")
    static let ink = Color("AnyTravelInk")
    static let secondaryInk = Color("AnyTravelSecondaryInk")
    static let softSurface = Color("AnyTravelSoftSurface")
    static let inputSurface = Color("AnyTravelInputSurface")
    static let elevatedSurface = Color("AnyTravelElevatedSurface")
    static let glassStroke = Color("AnyTravelGlassStroke")
    static let mapRouteHalo = Color("AnyTravelMapRouteHalo")

    static let dayRoutes: [Color] = [
        route,
        Color("AnyTravelDayRoute2"),
        Color("AnyTravelDayRoute3"),
        Color("AnyTravelDayRoute4"),
        Color("AnyTravelDayRoute5"),
        Color("AnyTravelDayRoute6"),
        Color("AnyTravelDayRoute7")
    ]

    static func routeColor(for dayIndex: Int) -> Color {
        dayRoutes[dayIndex % dayRoutes.count]
    }

}

extension View {
    @ViewBuilder
    func anyTravelGlassCard(cornerRadius: CGFloat = 30) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AnyTravelPalette.glassStroke, lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    func anyTravelGlassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(AnyTravelPalette.glassStroke, lineWidth: 0.8) }
        }
    }

    @ViewBuilder
    func anyTravelGlassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(AnyTravelPalette.glassStroke, lineWidth: 0.8) }
        }
    }
}

struct AnyTravelPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.965 : 1))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .animation(AnyTravelMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

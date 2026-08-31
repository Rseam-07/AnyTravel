import SwiftUI

enum AnyTravelPalette {
    static let route = Color(red: 0.07, green: 0.43, blue: 0.40)
    static let routeDark = Color(red: 0.035, green: 0.31, blue: 0.29)
    static let warm = Color(red: 0.96, green: 0.36, blue: 0.20)
    static let ink = Color(red: 0.07, green: 0.14, blue: 0.13)
    static let secondaryInk = Color(red: 0.30, green: 0.40, blue: 0.38)
    static let softSurface = Color(red: 0.95, green: 0.97, blue: 0.96)

    static let dayRoutes: [Color] = [
        route,
        Color(red: 0.91, green: 0.46, blue: 0.14),
        Color(red: 0.38, green: 0.34, blue: 0.72),
        Color(red: 0.08, green: 0.48, blue: 0.66),
        Color(red: 0.66, green: 0.28, blue: 0.47),
        Color(red: 0.37, green: 0.50, blue: 0.18),
        Color(red: 0.76, green: 0.30, blue: 0.18)
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
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    func anyTravelGlassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8) }
        }
    }

    @ViewBuilder
    func anyTravelGlassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8) }
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

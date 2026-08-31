import SwiftUI

enum AnyTravelMotion {
    static func press(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.08)
            : .spring(response: 0.20, dampingFraction: 0.76, blendDuration: 0.04)
    }

    static func snappy(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.08)
    }

    static func settle(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.10)
    }

    static func route(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.46, dampingFraction: 0.80, blendDuration: 0.08)
    }

    static func panelTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.985, anchor: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .bottom))
        )
    }

    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.975))
    }
}

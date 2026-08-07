import SwiftUI

// Liquid Glass shipped in iOS 26, but nothing in the app depends on it
// structurally — every call site is decoration floating over a photo. Routing
// those sites through these helpers keeps the glass treatment on iOS 26 and
// falls back to a frosted material below it, which is what lets the deployment
// target sit at 18.0 instead of 26.0.

extension View {
    /// Frosted capsule behind floating text — the error banner and the toast.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.18), lineWidth: 0.5))
        }
    }

    /// The glass treatment on the two floating icon buttons. Both labels are
    /// square, so the capsule reads as a circle.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(FrostedButtonStyle())
        }
    }
}

/// Stand-in for `.glass` on iOS 18, which dims and shrinks under a press the
/// way the real style does.
private struct FrostedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.18), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

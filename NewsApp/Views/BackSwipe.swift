import SwiftUI

/// Go back by swiping right from anywhere on the screen, not just from the few
/// points along the left edge that UIKit listens to.
///
/// **Why this doesn't drive the system gesture.** The obvious implementation is
/// to point a full-width `UIPanGestureRecognizer` at the same target and action
/// UIKit uses for its edge recogniser, which gets the real interactive pop —
/// the screen tracking your finger, rubber-banding back if you let go early.
/// That was built, and it pops *two* screens per swipe inside a
/// `NavigationStack`: the recogniser outlives the screen it just popped, and
/// its remaining updates drive a second transition. Attaching it to the screen's
/// own view instead doesn't help, and policing it means depending on the
/// internals of an undocumented transition handler. Popping one screen reliably
/// is worth more than the finger tracking.
///
/// So the swipe is recognised on release rather than followed live: flick right,
/// and the screen leaves with the ordinary pop animation.
private struct BackSwipe: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    /// Travel that counts as going back, in points.
    private static let commit: CGFloat = 90

    /// A flick can be shorter if it was moving fast enough to have carried on.
    private static let flick: CGFloat = 180

    /// How much more horizontal than vertical the drag has to be. Loose enough
    /// for the arc a thumb naturally makes, tight enough that a scroll with a
    /// bit of sideways drift in it never counts.
    private static let straightness: CGFloat = 1.5

    func body(content: Content) -> some View {
        // Simultaneous, not exclusive: a story scrolls and the feed turns its
        // pages with their own gestures, and both must keep working. Nothing
        // here acts until the finger lifts, so sharing costs them nothing.
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                let across = value.translation.width
                let down = abs(value.translation.height)
                guard across > 0, across > down * Self.straightness else { return }
                guard across > Self.commit
                    || value.predictedEndTranslation.width > Self.flick
                else { return }
                dismiss()
            }
        )
    }
}

extension View {
    /// Adds a rightward swipe, anywhere on the screen, that goes back.
    func backSwipe() -> some View {
        modifier(BackSwipe())
    }
}

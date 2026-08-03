import SwiftUI

/// The feed's page turn: a vertical, notepad-style flip.
///
/// The screen is a spiral-bound pad hinged across its horizontal midline.
/// Dragging up lifts the current story's **bottom half** off the pad and swings
/// it about that hinge — foreshortening as it rises, its near edge splaying out
/// past both sides of the screen — until it is edge-on and gone. Past that point
/// the same flap keeps turning, now over the top half, and what you see is its
/// back: the *next* story's **top half**, unfolding flat. The next story's
/// bottom half has been sitting underneath the whole time, revealed as the flap
/// lifts off it. Dragging down is the same thing mirrored.
///
/// In CSS this is `rotateX()` + `transform-origin` + `backface-visibility`.
/// SwiftUI has no two-sided surface, so the faces are two separate views swapped
/// at 90° — which is the whole point here, since the two faces carry *different
/// stories* rather than two sides of the same one.
///
/// A `ScrollView` can't do this. `.scrollTransition` hands each item a phase and
/// transforms it as one rigid rectangle; there is no way to split an item at the
/// midline, put half of it above half of its neighbour, or control the z-order
/// between them. Hence a hand-driven drag.
///
/// **Where this deliberately parts company with Flipboard.** Frame-by-frame,
/// Flipboard's second half doesn't turn the flap at all: the crease *travels* up
/// the screen while both pages sit perfectly still, the outgoing page simply
/// clipped away from its bottom edge. Here the crease stays on the midline and
/// the incoming half unfolds from it. That was a judgement call, made after
/// watching both — this reads as one continuous turn of a single sheet, which is
/// what the notepad metaphor wants. Don't "fix" it back without asking.
struct FlipPager<Page: View>: View {
    let count: Int
    @Binding var index: Int
    /// Built flat and fully interactive when settled, and as clipped halves
    /// while a turn is in flight.
    @ViewBuilder var page: (Int) -> Page

    /// Signed turn progress: `0` settled, `+1` a completed turn forward to
    /// `index + 1`, `-1` a completed turn back to `index - 1`.
    @State private var progress: Double = 0

    /// Finger travel for a full turn, as a fraction of screen height. Matching
    /// the height exactly makes every page feel like hard work.
    private static var dragSpan: CGFloat { 0.62 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let p = liveProgress

            ZStack {
                if p == 0 {
                    // Settled: one plain, untransformed view, so hit testing,
                    // the heart button and navigation all behave normally.
                    page(index)
                        .frame(width: size.width, height: size.height)
                } else {
                    FlipLayers(
                        progress: p,
                        index: index,
                        count: count,
                        size: size,
                        page: page
                    )
                    // Mid-turn the layers are clipped halves of the same card;
                    // nothing there is meant to be tappable.
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(.black)
            .contentShape(.rect)
            // High priority, not `.gesture`: the card is wrapped in a
            // NavigationLink, and a plain `.gesture` is outranked by it — the
            // link stays pressed through the drag and fires on release, so
            // every attempt to turn a page opened the story instead. Taking
            // priority here is safe because `minimumDistance` means a click
            // that doesn't move never starts this gesture at all, leaving the
            // link to handle it.
            .highPriorityGesture(drag(height: size.height))
        }
    }

    // MARK: - Gesture

    private func drag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                progress = resisted(-value.translation.height / (height * Self.dragSpan))
            }
            .onEnded { value in
                // Predicted end, not the raw translation, so a short fast flick
                // turns the page and a long slow drag that stalls doesn't.
                settle(predicted: -value.predictedEndTranslation.height / (height * Self.dragSpan))
            }
    }

    /// Clamps to a single page turn, and turns a pull past either end of the
    /// feed into a small elastic tug that always springs back.
    private func resisted(_ raw: Double) -> Double {
        let target = raw > 0 ? index + 1 : index - 1
        guard (0..<count).contains(target) else {
            return max(-0.07, min(0.07, raw * 0.18))
        }
        return max(-1, min(1, raw))
    }

    private func settle(predicted: Double) {
        let target = progress > 0 ? index + 1 : index - 1
        guard (0..<count).contains(target), abs(predicted) > 0.5 else {
            withAnimation(.spring(response: 0.38, dampingFraction: 1)) { progress = 0 }
            return
        }
        // Critically damped: paper doesn't bounce, and an overshoot past 1 would
        // carry the flap back past the hinge.
        withAnimation(.spring(response: 0.42, dampingFraction: 1), completionCriteria: .logicallyComplete) {
            progress = progress > 0 ? 1 : -1
        } completion: {
            // A completed turn renders identically to the settled next page, so
            // committing the index and zeroing progress is invisible.
            index = target
            progress = 0
        }
    }

    // MARK: - Debug

    private var liveProgress: Double {
        #if DEBUG
        Self.frozenProgress ?? progress
        #else
        progress
        #endif
    }

    #if DEBUG
    /// Freezes the turn at a fixed progress so a mid-flip frame can be
    /// screenshotted. The shape of this transition is impossible to judge from
    /// its endpoints, and a finger can't be held still for a screenshot.
    ///
    ///     xcrun simctl launch <device> com.shanedoc.NewsApp -flipProgress 0.35
    ///
    /// Note it ignores the gesture entirely while set, so a frozen build looks
    /// exactly like paging with no animation at all.
    private static var frozenProgress: Double? {
        let v = UserDefaults.standard.double(forKey: "flipProgress")
        return v == 0 ? nil : v
    }
    #endif
}

// MARK: - The turn

/// The three layers of a turn in flight: the top half of the pad, the bottom
/// half of the pad, and the flap rotating between them.
///
/// **`Animatable` is load-bearing here.** `withAnimation` evaluates a body
/// *once*, at its final value, then interpolates whatever animatable modifiers
/// it finds between the old rendering and the new one. Without this conformance
/// a flick produced no fold at all: SwiftUI saw a flap in the bottom slot at one
/// angle and a flap in the top slot at another, and simply slid the one to the
/// other with its contents swapped. Conforming to `Animatable` makes SwiftUI
/// re-evaluate this body for every interpolated `progress`, which is the only
/// way the halves can be re-picked frame by frame.
///
/// A slow drag hid that completely, because `onChanged` re-evaluates the body on
/// its own — the fold was only ever wrong when an animation was driving it.
private struct FlipLayers<Page: View>: View, Animatable {
    var progress: Double
    var index: Int
    var count: Int
    var size: CGSize
    var page: (Int) -> Page

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Strength of the 3D projection. Tuned so the near edge splays visibly past
    /// both sides of the screen at the steepest part of the turn — that flare is
    /// what reads as paper rather than as a rotating rectangle.
    private static var perspective: CGFloat { 0.62 }

    var body: some View {
        let forward = progress > 0
        let q = min(abs(progress), 1)                  // 0 … 1
        let target = forward ? index + 1 : index - 1
        let past = q > 0.5                             // gone edge-on yet?

        // The flap always shows the half it is currently covering, so which slot
        // it occupies is decided by how far through the turn it is.
        let flapSlot: Half = forward == past ? .top : .bottom
        let flapPage = past ? target : index
        // One continuous sweep: 0 → 90 → 0, re-anchored to the far edge as it
        // passes vertical.
        let angle = forward
            ? (past ? 180 * q - 180 : 180 * q)
            : (past ? 180 - 180 * q : -180 * q)

        return ZStack {
            VStack(spacing: 0) {
                half(forward ? index : target, .top)
                    .creaseShadow(on: .bottom, showing: forward ? 0 : 1 - q * 2)
                half(forward ? target : index, .bottom)
                    .creaseShadow(on: .top, showing: forward ? 1 - q * 2 : 0)
            }

            VStack(spacing: 0) {
                if flapSlot == .bottom { Color.clear.frame(height: size.height / 2) }
                half(flapPage, flapSlot)
                    // Light falls off the page as it turns away from you. This
                    // is what sells the crease — without it the flap reads as a
                    // sheet of glass.
                    .overlay { Color.black.opacity(0.55 * sin(abs(angle) * .pi / 180)) }
                    .rotation3DEffect(
                        .degrees(angle),
                        axis: (x: 1, y: 0, z: 0),
                        // The hinge: whichever edge of the flap faces the
                        // midline.
                        anchor: flapSlot == .top ? .bottom : .top,
                        perspective: Self.perspective
                    )
                if flapSlot == .top { Color.clear.frame(height: size.height / 2) }
            }
        }
        // Every recomputed frame *is* the animation. Letting the ambient
        // transaction animate these values again makes the flap chase its own
        // position a frame behind, which smears the fold.
        .transaction { $0.animation = nil }
    }

    /// One half of a page, clipped out of a full-size render of it.
    ///
    /// The card is laid out at full screen size and then offset behind a
    /// half-height window, rather than being asked to lay itself out at half
    /// height — otherwise the two halves would each reflow to fit and stop
    /// lining up as one page.
    @ViewBuilder
    private func half(_ i: Int, _ part: Half) -> some View {
        Color.black
            .frame(width: size.width, height: size.height / 2)
            .overlay {
                if (0..<count).contains(i) {
                    page(i)
                        .frame(width: size.width, height: size.height)
                        .offset(y: part == .top ? size.height / 4 : -size.height / 4)
                }
            }
            .clipped()
    }
}

private enum Half { case top, bottom }

// MARK: - Crease shadow

private extension View {
    /// The shadow the raised flap casts onto the page underneath it, hard
    /// against the hinge and fading out as the flap lifts away.
    func creaseShadow(on edge: VerticalEdge, showing amount: Double) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            LinearGradient(
                colors: [.black.opacity(0.5 * max(0, min(1, amount))), .clear],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
            .frame(height: 130)
            .allowsHitTesting(false)
        }
    }
}

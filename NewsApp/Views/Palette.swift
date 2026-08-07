import SwiftUI

/// The two colours the rest of the app is built out of.
///
/// It used to be black and white literally — `.background(.black)`,
/// `.foregroundStyle(.white)` — written that way when dark was the only mode.
/// Light mode needs both to flip, so they're named for the job they do rather
/// than the colour they happen to be: `page` is whatever the paper is, `ink` is
/// whatever is printed on it.
///
/// Not every black in the app became a `page`, and not every white an `ink`.
/// The scrim under a headline, the shadow a turning page casts, the tag's own
/// white lettering on its coloured capsule — those sit on a photograph, not on
/// the page, and they stay exactly as dark or as light as they are in both
/// modes.
///
/// Both are `nonisolated`, for the same reason `NewsCategory.tint` is — see the
/// note there. A dynamic colour's provider runs on whichever thread is drawing,
/// which during a page turn is SwiftUI's async render thread; the module's
/// default MainActor isolation would otherwise put a main-queue assertion in
/// front of it and trap. These two are drawn by every half-page of every fold,
/// so they would have been next.
enum Palette {
    /// The background behind everything: black, or a warm near-white that reads
    /// as newsprint rather than as a lightbox.
    nonisolated static let page = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 1)
            : UIColor(red: 0.980, green: 0.976, blue: 0.969, alpha: 1)
    })

    /// Everything drawn on the page. Used at full strength for headlines and at
    /// a fraction of it for secondary text, hairlines and row fills — the
    /// fractions in the app are all of this, so they follow the mode too.
    nonisolated static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 1)
            : UIColor(red: 0.078, green: 0.075, blue: 0.071, alpha: 1)
    })
}

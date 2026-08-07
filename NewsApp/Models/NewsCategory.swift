import SwiftUI

/// The six sections the feed is divided into. The raw values match the
/// `category` strings in the feed JSON (see feed-data/schema.md) and the list in
/// `hermes/config.json → sections.order`.
///
/// `Article` decodes `category` strictly and `Feed` holds a plain `[Article]`, so
/// a category this enum doesn't know throws and takes the *whole feed* down with
/// it rather than dropping the one story. A new section therefore ships here
/// first and goes into the config only once this build is on the phone.
enum NewsCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case national
    case northernIreland
    case global
    case tech
    case ai

    var id: String { rawValue }

    /// Label shown in the category tag on each card.
    ///
    /// Abbreviated where the full name would misbehave: the tag is a capsule and
    /// the reading bar centres this word under its own run of ticks, so
    /// "NORTHERN IRELAND" would be half the width of the bar and spend most of a
    /// section clamped against one end of it.
    var displayName: String {
        switch self {
        case .local: "Local"
        case .national: "National"
        case .northernIreland: "N. Ireland"
        case .global: "World"
        case .tech: "Tech"
        case .ai: "AI"
        }
    }

    /// Position in the feed. The app reads sections in this order, like the
    /// sections of a newspaper.
    var sortOrder: Int {
        switch self {
        case .local: 0
        case .national: 1
        case .northernIreland: 2
        case .global: 3
        case .tech: 4
        case .ai: 5
        }
    }

    /// Accent used for the category tag and as the fallback background when a
    /// photo is missing or still loading.
    ///
    /// Two versions of each. The first was picked to sit on black, and the
    /// reading bar names the current section in flat tint on the page itself —
    /// mid-bright orange on newsprint is barely there. The light variants are
    /// the same hues taken down far enough to read on paper, and still dark
    /// enough for the tag's white lettering.
    ///
    /// **`nonisolated` is load-bearing**, here and on the two tables below.
    /// UIKit resolves a dynamic colour on whichever thread is drawing, and
    /// SwiftUI draws a page turn on its own async render thread rather than on
    /// the main one. This module builds with default MainActor isolation, so
    /// without this the closure is inferred `@MainActor` and Swift 6 puts a
    /// "same queue?" assertion in front of every call into it — which trapped on
    /// the first frame of every flip, off the main queue, in
    /// `ShapeStyleResolver`. Nothing in here needs the main actor: it reads a
    /// trait and a frozen enum case and returns a colour.
    nonisolated var tint: Color {
        Color(uiColor: UIColor { [self] traits in
            let rgb = traits.userInterfaceStyle == .dark ? onDark : onLight
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    /// Northern Ireland is the olive: the five existing hues leave a gap between
    /// tech's orange and local's green-teal, and it is the one opening wide
    /// enough that the new tag can't be mistaken for a neighbour at a glance.
    /// Green rather than anything flag-adjacent — the section covers both
    /// communities and shouldn't wear either one's colour.
    nonisolated private var onDark: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .local: (0.20, 0.62, 0.47)
        case .national: (0.25, 0.47, 0.78)
        case .northernIreland: (0.45, 0.60, 0.24)
        case .global: (0.62, 0.35, 0.72)
        case .tech: (0.88, 0.52, 0.20)
        case .ai: (0.82, 0.30, 0.42)
        }
    }

    nonisolated private var onLight: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .local: (0.09, 0.42, 0.31)
        case .national: (0.13, 0.31, 0.56)
        case .northernIreland: (0.30, 0.42, 0.13)
        case .global: (0.43, 0.22, 0.52)
        case .tech: (0.65, 0.35, 0.09)
        case .ai: (0.60, 0.17, 0.28)
        }
    }

    var symbolName: String {
        switch self {
        case .local: "mappin.and.ellipse"
        case .national: "building.columns"
        case .northernIreland: "map"
        case .global: "globe"
        case .tech: "cpu"
        case .ai: "sparkles"
        }
    }
}

import SwiftUI

/// The five sections the feed is divided into. The raw values match the
/// `category` strings in the feed JSON (see feed-data/schema.md).
enum NewsCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case national
    case global
    case tech
    case ai

    var id: String { rawValue }

    /// Label shown in the category tag on each card.
    var displayName: String {
        switch self {
        case .local: "Local"
        case .national: "National"
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
        case .global: 2
        case .tech: 3
        case .ai: 4
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
    var tint: Color {
        Color(uiColor: UIColor { [self] traits in
            let rgb = traits.userInterfaceStyle == .dark ? onDark : onLight
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    private var onDark: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .local: (0.20, 0.62, 0.47)
        case .national: (0.25, 0.47, 0.78)
        case .global: (0.62, 0.35, 0.72)
        case .tech: (0.88, 0.52, 0.20)
        case .ai: (0.82, 0.30, 0.42)
        }
    }

    private var onLight: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .local: (0.09, 0.42, 0.31)
        case .national: (0.13, 0.31, 0.56)
        case .global: (0.43, 0.22, 0.52)
        case .tech: (0.65, 0.35, 0.09)
        case .ai: (0.60, 0.17, 0.28)
        }
    }

    var symbolName: String {
        switch self {
        case .local: "mappin.and.ellipse"
        case .national: "building.columns"
        case .global: "globe"
        case .tech: "cpu"
        case .ai: "sparkles"
        }
    }
}

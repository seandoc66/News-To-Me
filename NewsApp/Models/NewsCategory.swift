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
    var tint: Color {
        switch self {
        case .local: Color(red: 0.20, green: 0.62, blue: 0.47)
        case .national: Color(red: 0.25, green: 0.47, blue: 0.78)
        case .global: Color(red: 0.62, green: 0.35, blue: 0.72)
        case .tech: Color(red: 0.88, green: 0.52, blue: 0.20)
        case .ai: Color(red: 0.82, green: 0.30, blue: 0.42)
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

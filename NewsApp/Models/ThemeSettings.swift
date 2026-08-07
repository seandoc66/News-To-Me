import SwiftUI

/// Light, dark, or whatever the phone is doing.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands the decision back to iOS, which is what "System" means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The face the stories are set in.
///
/// Three designs rather than a font picker: `Font.Design` stays on the system
/// faces, so every weight, every Dynamic Type size and every accessibility
/// setting keeps working. A bundled font would have to bring all of that with it.
enum ReadingFont: String, CaseIterable, Identifiable, Sendable {
    case serif
    case sans
    case rounded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .serif: "Serif"
        case .sans: "Sans"
        case .rounded: "Rounded"
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }
}

/// How big the reading text is, *relative to* the phone's own Dynamic Type
/// setting rather than instead of it.
///
/// An absolute size would quietly undo whatever the reader has already set in
/// Settings › Display & Brightness — someone who reads at large everywhere would
/// open this app and find it back at the default. A step keeps both: the system
/// size is the starting point, and this nudges it.
enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case xLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xLarge: "X-Large"
        }
    }

    /// Steps up or down the Dynamic Type scale from wherever the phone is set.
    var step: Int {
        switch self {
        case .small: -1
        case .medium: 0
        case .large: 1
        case .xLarge: 2
        }
    }
}

/// How the reader wants the app to look. Everything here is a preference of
/// Shane's, saved on the phone — none of it comes from the feed.
@Observable
final class ThemeSettings {
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var readingFont: ReadingFont {
        didSet { defaults.set(readingFont.rawValue, forKey: Key.readingFont) }
    }

    var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let appearance = "appearanceMode"
        static let readingFont = "readingFont"
        static let textSize = "textSize"
    }

    /// Dark and serif are the defaults because that is what the app was before
    /// it could be anything else — an existing install shouldn't change its
    /// appearance the first time it launches with this in it.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .dark
        readingFont = ReadingFont(rawValue: defaults.string(forKey: Key.readingFont) ?? "") ?? .serif
        textSize = TextSize(rawValue: defaults.string(forKey: Key.textSize) ?? "") ?? .medium
    }
}

// MARK: - Applying it

private extension DynamicTypeSize {
    /// This size moved `steps` along the scale, stopping at either end.
    func shifted(by steps: Int) -> DynamicTypeSize {
        guard steps != 0 else { return self }
        let sizes = DynamicTypeSize.allCases
        guard let current = sizes.firstIndex(of: self) else { return self }
        return sizes[min(max(current + steps, 0), sizes.count - 1)]
    }
}

/// Puts the reader's three choices into the environment, once, at the root.
///
/// The type size is worked out here rather than at each `Text` because the step
/// is relative: this is the one place that still sees the phone's own Dynamic
/// Type setting before the app's own adjustment is layered on top of it.
private struct ThemedRoot: ViewModifier {
    let theme: ThemeSettings

    @Environment(\.dynamicTypeSize) private var systemTypeSize

    func body(content: Content) -> some View {
        let resolved = systemTypeSize.shifted(by: theme.textSize.step)

        return content
            .environment(theme)
            .environment(\.readingFont, theme.readingFont.design)
            .dynamicTypeSize(resolved)
            // Handed on as a finished size rather than a step, so anywhere that
            // has to restate it can do so without compounding it.
            .environment(\.resolvedTypeSize, resolved)
            .preferredColorScheme(theme.appearance.colorScheme)
    }
}

/// Restates at a sheet what the root already said.
///
/// A sheet is its own UIKit presentation. Custom environment values reach it —
/// the store and the reading face both arrive intact — but two things don't:
/// `preferredColorScheme`, which is a preference and travels the other way, and
/// the type size, which the new hosting controller re-reads from the phone's own
/// Dynamic Type trait. Both are simply said again here.
private struct ThemedSheet: ViewModifier {
    @Environment(ThemeSettings.self) private var theme
    @Environment(\.resolvedTypeSize) private var resolved

    func body(content: Content) -> some View {
        content
            // Assignment rather than a step, so this is a no-op on any OS where
            // the size did come through.
            .transformEnvironment(\.dynamicTypeSize) { size in
                if let resolved { size = resolved }
            }
            .preferredColorScheme(theme.appearance.colorScheme)
    }
}

extension View {
    /// Apply at the app's root, and nowhere else — a second application would
    /// shift the type size twice.
    func themed(_ theme: ThemeSettings) -> some View {
        modifier(ThemedRoot(theme: theme))
    }

    /// Apply to the content of every sheet. See `ThemedSheet`.
    func themedSheet() -> some View {
        modifier(ThemedSheet())
    }
}

// MARK: - Reading font

private struct ReadingFontKey: EnvironmentKey {
    static let defaultValue: Font.Design = .serif
}

private struct ResolvedTypeSizeKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize? = nil
}

extension EnvironmentValues {
    /// The phone's Dynamic Type size with the app's own step already in it, or
    /// nil above the root that works it out.
    var resolvedTypeSize: DynamicTypeSize? {
        get { self[ResolvedTypeSizeKey.self] }
        set { self[ResolvedTypeSizeKey.self] = newValue }
    }

    /// The face headlines, teasers and story text are set in. Chrome — buttons,
    /// tags, the reading bar — deliberately doesn't read this: it isn't what's
    /// being read.
    var readingFont: Font.Design {
        get { self[ReadingFontKey.self] }
        set { self[ReadingFontKey.self] = newValue }
    }
}

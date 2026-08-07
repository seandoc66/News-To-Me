import SwiftUI

@main
struct NewsAppApp: App {
    @State private var store = ArticleStore()
    @State private var theme = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // Appearance, reading face and text size, all three at once —
                // and only here. See `themed(_:)`.
                .themed(theme)
        }
    }
}

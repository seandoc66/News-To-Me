import SwiftUI

@main
struct NewsAppApp: App {
    @State private var store = ArticleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

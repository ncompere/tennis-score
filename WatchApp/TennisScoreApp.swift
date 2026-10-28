import SwiftUI

@main
@MainActor
struct TennisScoreApp: App {
    @State private var store = MatchStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .tint(.mint)
        }
    }
}

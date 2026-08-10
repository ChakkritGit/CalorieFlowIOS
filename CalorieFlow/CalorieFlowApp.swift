import SwiftUI

@main
struct CalorieFlowApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Palette.green)
                .preferredColorScheme(.light)
        }
    }
}

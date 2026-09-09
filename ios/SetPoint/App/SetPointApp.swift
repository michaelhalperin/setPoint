import SwiftUI

@main
struct SetPointApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .tint(Palette.accent)
        }
    }
}

import SwiftUI

@main
struct SetPointApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .tint(Palette.accent)
                .onOpenURL { url in
                    if case let .checkIn(id) = DeepLink(url: url) {
                        env.push.openCheckIn(id)
                    }
                }
                .task {
                    LiveActivityController.shared.observePushToStartToken()
                    await env.push.registerIfAuthorized()
                }
        }
    }
}

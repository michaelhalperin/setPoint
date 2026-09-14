import SwiftUI

@main
struct SetPointApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var env = AppEnvironment()

    init() {
        CrashReporting.start()
    }

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
                    await env.health.refreshState()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await env.health.refreshState()
                        await env.health.sync()
                    }
                }
        }
    }
}

import SwiftUI

/// The signed-in shell: three tabs, with onboarding presented full-screen over
/// everything until it's complete.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var home: HomeViewModel?
    @State private var onboarding: OnboardingViewModel?
    @State private var selection = Tab.today

    enum Tab: Hashable { case today, week, settings }

    var body: some View {
        Group {
            if let home, let onboarding {
                TabView(selection: $selection) {
                    NavigationStack {
                        HomeContent(model: home)
                            .navigationTitle("Today")
                            .navigationBarTitleDisplayMode(.large)
                            .toolbarBackground(Palette.background, for: .navigationBar)
                    }
                    .tabItem { Label("Today", systemImage: "sun.max") }
                    .tag(Tab.today)

                    NavigationStack { SettlementView() }
                        .tabItem { Label("Week", systemImage: "chart.bar") }
                        .tag(Tab.week)

                    NavigationStack { SettingsView() }
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
                .tint(Palette.accent)
                .fullScreenCover(isPresented: needsOnboarding) {
                    OnboardingFlow(model: onboarding)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard home == nil else { return }
            let h = HomeViewModel(api: env.api, onUnauthorized: { env.auth.handleUnauthorized() })
            onboarding = OnboardingViewModel(api: env.api, onComplete: { Task { await h.load() } })
            home = h
            await h.load()
        }
    }

    private var needsOnboarding: Binding<Bool> {
        Binding(
            get: {
                if case .needsOnboarding = home?.phase { return true }
                return false
            },
            set: { _ in }
        )
    }
}

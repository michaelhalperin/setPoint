import SwiftUI
import UIKit

/// The signed-in shell: three tabs, with onboarding presented full-screen over
/// everything until it's complete.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var home: HomeViewModel?
    @State private var onboarding: OnboardingViewModel?
    @State private var selection = Tab.today
    @State private var deepLinkCheckInID: String?

    enum Tab: Hashable { case today, week, you }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Palette.background).withAlphaComponent(0.94)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        Group {
            if let home, let onboarding {
                TabView(selection: $selection) {
                    NavigationStack {
                        HomeContent(model: home, deepLinkCheckInID: $deepLinkCheckInID)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .tabItem { Label("Today", systemImage: "sun.max") }
                    .tag(Tab.today)

                    NavigationStack {
                        SettlementView()
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .tabItem { Label("Week", systemImage: "chart.bar") }
                    .tag(Tab.week)

                    NavigationStack { SettingsView() }
                        .tabItem { Label("You", systemImage: "person") }
                        .tag(Tab.you)
                }
                .tint(Palette.accent)
                .fullScreenCover(isPresented: needsOnboarding) {
                    OnboardingFlow(model: onboarding)
                }
            } else {
                HomeSkeletonView()
            }
        }
        .onChange(of: env.push.pendingCheckInID) { _, id in
            guard let id else { return }
            selection = .today
            deepLinkCheckInID = id
            env.push.pendingCheckInID = nil
        }
        .task {
            guard home == nil else { return }
            let h = HomeViewModel(
                api: env.api,
                onUnauthorized: { env.auth.handleUnauthorized() },
                onMealChanged: { env.changes.mealsChanged() }
            )
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

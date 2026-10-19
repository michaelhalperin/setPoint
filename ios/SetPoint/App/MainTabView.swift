import SwiftUI

/// The signed-in shell: four tabs (Today · Train · Progress · You) behind a
/// floating glass nav with the ember "+" in the middle for logging. Onboarding is
/// presented full-screen over everything until it's complete.
///
/// Tabs are kept alive in a ZStack instead of a system TabView, so the nav can
/// float over content and only appear on each tab's root screen.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var home: HomeViewModel?
    @State private var onboarding: OnboardingViewModel?
    @State private var selection = Tab.today
    @State private var visited: Set<Tab> = [.today]
    @State private var deepLinkCheckInID: String?
    /// A just-logged meal opened from the "Logged · Fix" toast.
    @State private var fixing: MealSummary?

    enum Tab: Hashable, CaseIterable {
        case today, training, week, you

        /// The name in analytics.
        var screenName: String {
            switch self {
            case .today: return "today"
            case .training: return "train"
            case .week: return "progress"
            case .you: return "you"
            }
        }
    }

    var body: some View {
        Group {
            if let home, let onboarding {
                ZStack {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        if visited.contains(tab) {
                            stack(for: tab, home: home)
                                .opacity(selection == tab ? 1 : 0)
                                .allowsHitTesting(selection == tab)
                                .accessibilityHidden(selection != tab)
                        }
                    }
                }
                .modifier(LogAnywhere(home: home))
                .overlay(alignment: .bottom) { justLoggedToast(home: home) }
                .fullScreenCover(item: $fixing) { meal in
                    MealFixView(
                        meal: meal,
                        onSaved: { _ in Task { await home.load(showSpinner: false) } },
                        onRemove: {
                            fixing = nil
                            Task { try? await home.removeMeal(id: meal.id) }
                        },
                        onClose: { fixing = nil }
                    )
                }
                .fullScreenCover(isPresented: needsOnboarding) {
                    OnboardingFlow(model: onboarding)
                }
            } else {
                HomeSkeletonView()
            }
        }
        .onChange(of: env.push.pendingCheckInID) { _, id in
            guard let id else { return }
            select(.today)
            deepLinkCheckInID = id
            env.push.pendingCheckInID = nil
        }
        .onChange(of: env.changes.pendingLogPhoto) { _, pending in
            guard pending else { return }
            select(.today)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Analytics.send(.appOpened, api: env.api) }
        }
        .onChange(of: env.chrome.tabRequest) { _, tab in
            guard let tab else { return }
            select(tab)
            env.chrome.clearTabRequest()
        }
        .task {
            guard home == nil else { return }
            let h = HomeViewModel(
                api: env.api,
                onUnauthorized: { env.auth.handleUnauthorized() },
                onMealChanged: { env.changes.mealsChanged() }
            )
            onboarding = OnboardingViewModel(
                api: env.api,
                progressStore: .standard,
                onComplete: { Task { await h.load() } }
            )
            home = h
            await h.load()
            Analytics.send(.appOpened, api: env.api)
            Analytics.screen(selection.screenName, api: env.api)
            await env.flags.refresh(using: env.api)
            await env.subscription.refresh(using: env.api)
        }
    }

    @ViewBuilder
    private func stack(for tab: Tab, home: HomeViewModel) -> some View {
        NavigationStack {
            Group {
                switch tab {
                case .today:
                    HomeContent(model: home, deepLinkCheckInID: $deepLinkCheckInID)
                case .training:
                    if env.subscription.entitled {
                        TrainingScreen(isTabRoot: true)
                    } else {
                        TrainingLockedView()
                    }
                case .week:
                    SettlementView()
                case .you:
                    SettingsView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !(tab == .today && env.chrome.navHidden) {
                    FloatingNav(selection: selection, onSelect: select, onLog: openLog)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: env.chrome.navHidden)
        }
    }

    @ViewBuilder
    private func justLoggedToast(home: HomeViewModel) -> some View {
        Group {
            if let failure = env.chrome.failure, !env.chrome.logPanelOpen {
                ActionFailedToast(failure: failure) { env.chrome.retryFailure() }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: failure.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if env.chrome.failure?.id == failure.id { env.chrome.clearFailure() }
                    }
            } else if let logged = env.chrome.justLogged, !env.chrome.logPanelOpen, !env.chrome.navHidden {
                JustLoggedToast(logged: logged) {
                    env.chrome.clearJustLogged()
                    Task { fixing = await meal(logged.mealID, in: home) }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: logged.token) {
                    try? await Task.sleep(for: .seconds(5))
                    if env.chrome.justLogged?.token == logged.token { env.chrome.clearJustLogged() }
                }
            }
        }
        .animation(Motion.snappy, value: env.chrome.justLogged)
        .animation(Motion.snappy, value: env.chrome.failure)
    }

    /// The logged meal as Today has it — after one reload if Today hasn't caught up.
    private func meal(_ id: String, in home: HomeViewModel) async -> MealSummary? {
        func find() -> MealSummary? {
            if case let .loaded(response) = home.phase { return response.meals.first { $0.id == id } }
            return nil
        }
        if let found = find() { return found }
        await home.load(showSpinner: false)
        return find()
    }

    private func select(_ tab: Tab) {
        if tab != selection { Analytics.screen(tab.screenName, api: env.api) }
        env.chrome.logPanelOpen = false
        visited.insert(tab)
        selection = tab
    }

    /// The "+": log right where you are. On Today it's Today's own panel; on any
    /// other tab the panel rises over that screen and the meal lands on Today.
    private func openLog() {
        Haptics.nudge()
        if selection == .today {
            env.chrome.requestLog()
        } else {
            env.chrome.logPanelOpen = true
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

/// The floating glass nav: two tabs, the ember "+", two tabs.
struct FloatingNav: View {
    let selection: MainTabView.Tab
    let onSelect: (MainTabView.Tab) -> Void
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.today, "Today", "sun.max")
            item(.training, "Train", "figure.strengthtraining.traditional")
            Button(action: onLog) {
                EmberBall(size: 54, glow: true) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .buttonStyle(PressableCard())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Log food")
            item(.week, "Progress", "chart.line.uptrend.xyaxis")
            item(.you, "You", "person")
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color(hex: 0x1C1C20, opacity: 0.82)))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline))
                .elevation(.floating)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func item(_ tab: MainTabView.Tab, _ title: String, _ symbol: String) -> some View {
        let current = selection == tab
        return Button {
            if !current { Haptics.select() }
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 24)
                Text(title)
                    .font(Typography.data(10, weight: .regular))
            }
            .foregroundStyle(current ? Palette.ink : Color(hex: 0x71717A))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
    }
}

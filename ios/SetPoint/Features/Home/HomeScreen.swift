import SwiftUI

struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: HomeViewModel?

    var body: some View {
        Group {
            if let model {
                HomeContent(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                let vm = HomeViewModel(api: env.api, onUnauthorized: { env.auth.handleUnauthorized() })
                model = vm
                await vm.load()
            }
        }
    }
}

struct HomeContent: View {
    @Bindable var model: HomeViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLogMeal = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            switch model.phase {
            case .loading:
                ProgressView()

            case let .failed(message):
                RetryState(message: message) { Task { await model.load() } }

            case .needsOnboarding:
                OnboardingNeededView()

            case let .loaded(home):
                loaded(home)
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isLoaded)
        .sheet(isPresented: $showingLogMeal) {
            LogMealSheet(isLogging: model.loggingMeal) { text in
                Task {
                    await model.logMeal(text: text)
                    showingLogMeal = false
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var isLoaded: Bool {
        if case .loaded = model.phase { return true }
        return false
    }

    @ViewBuilder
    private func loaded(_ home: HomeResponse) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                LedgerHero(ledger: home.ledger, framing: home.framing)
                ManagerNote(text: home.managerNote, emphasised: home.framing.accent)

                if let checkIn = home.activeCheckIn {
                    CheckInCard(checkIn: checkIn)
                }

                ProteinRow(ledger: home.ledger)

                if home.framing.primaryCta == "log_meal" {
                    ActionButton(title: "Log a meal") { showingLogMeal = true }
                        .firstAppearPulse(home.framing.accent)
                } else {
                    ActionButton(title: "Log a meal", kind: .secondary) { showingLogMeal = true }
                }
            }
            .padding(20)
        }
        .refreshable { await model.load(showSpinner: false) }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack {
            Text("Today")
                .font(Typography.data(15, weight: .semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkFaint)
            Spacer()
            Button {
                env.auth.signOut()
            } label: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

private struct RetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(Typography.data(15))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            ActionButton(title: "Try again", kind: .secondary, action: retry)
                .frame(maxWidth: 200)
        }
        .padding(28)
    }
}

private struct OnboardingNeededView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Let's set you up")
                .font(Typography.voice(24))
                .foregroundStyle(Palette.ink)
            Text("Onboarding — goal, meal times, and a short safety screen — is the next screen to build.")
                .font(Typography.data(14))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

#if DEBUG
#Preview("Loaded — under target") {
    HomeContent(model: .previewed(.loaded(.sampleUnder)))
        .environment(AppEnvironment.preview())
}

#Preview("Loaded — over target") {
    HomeContent(model: .previewed(.loaded(.sampleOver)))
        .environment(AppEnvironment.preview())
}
#endif

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
    @State private var showingCheckIn = false
    @Namespace private var checkInNamespace

    private static let checkInGeometryID = "active-check-in"

    private var activeCheckIn: HomeResponse.ActiveCheckIn? {
        if case let .loaded(home) = model.phase { return home.activeCheckIn }
        return nil
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            switch model.phase {
            case .loading:
                ProgressView()

            case let .failed(message):
                RetryState(message: message) { Task { await model.load() } }

            case .needsOnboarding:
                OnboardingContainer { await model.load() }

            case let .loaded(home):
                loaded(home)
            }

            if showingCheckIn, let checkIn = activeCheckIn {
                PrescriptionView(
                    checkIn: checkIn,
                    namespace: checkInNamespace,
                    geometryID: Self.checkInGeometryID,
                    onDismiss: { withAnimation(springForCheckIn) { showingCheckIn = false } },
                    onResolved: {
                        withAnimation(springForCheckIn) { showingCheckIn = false }
                        Task { await model.load(showSpinner: false) }
                    },
                    onLogSomethingElse: {
                        withAnimation(springForCheckIn) { showingCheckIn = false }
                        showingLogMeal = true
                    }
                )
                .transition(.opacity)
                .zIndex(2)
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

    private var springForCheckIn: Animation {
        Motion.adaptive(Motion.sheet, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private func loaded(_ home: HomeResponse) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                LedgerHero(ledger: home.ledger, framing: home.framing)
                ManagerNote(text: home.managerNote, emphasised: home.framing.accent)

                if let checkIn = home.activeCheckIn, !showingCheckIn {
                    CheckInContent(checkIn: checkIn)
                        .matchedGeometryEffect(id: Self.checkInGeometryID, in: checkInNamespace)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(springForCheckIn) { showingCheckIn = true }
                        }
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

private struct OnboardingContainer: View {
    let onComplete: @MainActor () async -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var model: OnboardingViewModel?

    var body: some View {
        Group {
            if let model {
                OnboardingFlow(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                model = OnboardingViewModel(api: env.api, onComplete: {
                    Task { await onComplete() }
                })
            }
        }
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

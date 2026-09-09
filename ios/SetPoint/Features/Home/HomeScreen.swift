import SwiftUI

struct HomeContent: View {
    @Bindable var model: HomeViewModel
    var deepLinkCheckInID: Binding<String?> = .constant(nil)

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
                // Presented full-screen by MainTabView.
                ProgressView()

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
        .toolbar(showingCheckIn ? .hidden : .visible, for: .tabBar)
        .onChange(of: deepLinkCheckInID.wrappedValue) { _, id in
            guard id != nil else { return }
            Task { await openDeepLinkedCheckIn() }
        }
    }

    private func openDeepLinkedCheckIn() async {
        let target = deepLinkCheckInID.wrappedValue
        await model.load(showSpinner: false)
        if let target, activeCheckIn?.id == target {
            withAnimation(springForCheckIn) { showingCheckIn = true }
        }
        deepLinkCheckInID.wrappedValue = nil
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

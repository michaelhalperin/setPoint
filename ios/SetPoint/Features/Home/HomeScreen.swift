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

            homeLayer
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isLoaded)
                .overlay {
                    Palette.scrim
                        .ignoresSafeArea()
                        .opacity(showingCheckIn ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(Motion.adaptive(Motion.morph, reduceMotion: reduceMotion), value: showingCheckIn)

            if showingCheckIn, let checkIn = activeCheckIn {
                Group {
                    if checkIn.tier >= 3 {
                        ConversationView(
                            checkInID: checkIn.id,
                            onDismiss: { withAnimation(springForCheckIn) { showingCheckIn = false } },
                            onResolved: {
                                withAnimation(springForCheckIn) { showingCheckIn = false }
                                Task { await model.load(showSpinner: false) }
                            }
                        )
                    } else {
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
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showingLogMeal) {
            LogMealSheet {
                showingLogMeal = false
                Task { await model.load(showSpinner: false) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .toolbar(showingCheckIn ? .hidden : .visible, for: .tabBar)
        .onChange(of: deepLinkCheckInID.wrappedValue) { _, id in
            guard id != nil else { return }
            Task { await openDeepLinkedCheckIn() }
        }
    }

    private func openCheckIn() {
        Haptics.nudge()
        withAnimation(springForCheckIn) { showingCheckIn = true }
    }

    private func openDeepLinkedCheckIn() async {
        let target = deepLinkCheckInID.wrappedValue
        await model.load(showSpinner: false)
        if let target, activeCheckIn?.id == target {
            openCheckIn()
        }
        deepLinkCheckInID.wrappedValue = nil
    }

    private var isLoaded: Bool {
        if case .loaded = model.phase { return true }
        return false
    }

    private var springForCheckIn: Animation {
        Motion.adaptive(Motion.morph, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var homeLayer: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case let .failed(message):
            RetryState(message: message) { Task { await model.load() } }
        case .needsOnboarding:
            ProgressView() // presented full-screen by MainTabView
        case let .loaded(home):
            loaded(home)
        }
    }

    @ViewBuilder
    private func loaded(_ home: HomeResponse) -> some View {
        ScrollView {
            VStack(spacing: Space.sm + 2) {
                LedgerHero(ledger: home.ledger, framing: home.framing)
                    .appearIn(0)
                ManagerNote(text: home.managerNote, emphasised: home.framing.accent)
                    .appearIn(1)

                if let checkIn = home.activeCheckIn, !showingCheckIn {
                    Button {
                        openCheckIn()
                    } label: {
                        CheckInContent(checkIn: checkIn, restingElevation: .floating)
                            .matchedGeometryEffect(id: Self.checkInGeometryID, in: checkInNamespace)
                    }
                    .buttonStyle(PressableCard())
                    .appearIn(2)
                }

                ProteinRow(ledger: home.ledger)
                    .appearIn(3)

                Group {
                    if home.framing.primaryCta == "log_meal" {
                        ActionButton(title: "Log a meal") { showingLogMeal = true }
                            .firstAppearPulse(home.framing.accent)
                    } else {
                        ActionButton(title: "Log a meal", kind: .secondary) { showingLogMeal = true }
                    }
                }
                .appearIn(4)
                .padding(.top, Space.xxs)
            }
            .padding(Space.gutter)
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

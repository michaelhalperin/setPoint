import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            #if DEBUG
            if let stub = DebugPreviewStub.fromLaunchArguments() {
                stub.view
            } else {
                authedContent
            }
            #else
            authedContent
            #endif
        }
        .modifier(HintCopyReader())
        .modifier(AppLanguageReader())
        .animation(Motion.adaptive(Motion.gentle, reduceMotion: reduceMotion), value: env.auth.status)
        .task {
            env.auth.bootstrap()
            #if DEBUG
            if CommandLine.arguments.contains("-autoDevSignIn"), !env.auth.hasToken {
                await env.auth.developerSignIn()
            }
            #endif
        }
    }

    @ViewBuilder
    private var authedContent: some View {
        switch env.auth.status {
        case .loading:
            if env.auth.hasToken {
                HomeSkeletonView()
            } else {
                SignInSkeletonView()
            }
        case .signedOut:
            WelcomeView()
        case let .signedIn(userId):
            MainTabView()
                .id(userId)
        case .needsInvite:
            InviteCodeView()
        }
    }
}

#if DEBUG
/// The floating nav for stubbed screens, hidden when Today asks.
private struct StubNav: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if !env.chrome.navHidden {
            FloatingNav(selection: .today, onSelect: { _ in }, onLog: { env.chrome.requestLog() })
        }
    }
}

/// Renders a specific screen with sample data via a launch argument, for
/// screenshots and manual review: `-uiStub home` / `-uiStub home-over`.
@MainActor
enum DebugPreviewStub {
    case home(HomeResponse)
    case homeModel(HomeViewModel)
    case welcome
    case invite
    case onboarding(OnboardingViewModel.Step)
    case prescription
    case conversation(resolved: Bool)
    case logMeal(LogMealStubState)
    case savedMeal
    case fixMeal
    case scanner(LogMealViewModel.ScanStatus)
    case mealDetail
    case snooze
    case settings
    case settingsGoal
    case settingsMealTimes
    case settingsMealTimesWeekends
    case settingsFoods
    case settingsSavedMeals
    case settingsHealth
    case settingsHealthWrite
    case calendarSettings
    case calendarConnect
    case calendarPick
    case calendarWeek(kept: Bool)
    case calendarDay
    case calendarRules
    case calendarCalendars
    case training
    case refuel
    case checkinSmaller
    case settingsAppetite
    case widgets
    case burn
    case orderNearby
    case nutritionAssistant(String)
    case paywall
    case settingsAccount
    case settingsDelete

    enum LogMealStubState { case compose, parsing, result, quick, scan, typing, working, offline, failed }
    case settlement(SettlementResponse)
    case settlementLoading

    @ViewBuilder
    var view: some View {
        switch self {
        case let .homeModel(model):
            NavigationStack {
                HomeContent(model: model)
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        StubNav()
                    }
            }
        case let .home(response):
            NavigationStack {
                HomeContent(model: .previewed(.loaded(response)), previewLogger: .sampleQuickLog)
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        StubNav()
                    }
            }
        case .invite:
            InviteCodeView()
        case .welcome:
            WelcomeView()
        case let .onboarding(step):
            OnboardingFlow(model: .previewed(at: step))
                .background(Palette.background)
        case .prescription:
            PrescriptionStubHost()
        case let .conversation(resolved):
            ConversationView(
                checkInID: "ci_stub",
                onDismiss: {},
                onResolved: {},
                previewModel: .previewed(resolved: resolved)
            )
        case let .logMeal(state):
            LogMealStubHost(state: state)
        case .fixMeal:
            FixMealStubHost()
        case let .scanner(status):
            ScannerStubHost(status: status)
        case .mealDetail:
            HomeContent(model: .previewed(.loaded(.sampleOnPace)))
                .sheet(isPresented: .constant(true)) {
                    MealDetailSheet(meal: .detailSample, onRemove: {}, dayKcalTarget: 3100, onLogAgain: {}, onSaveDraft: { _ in true })
                }
        case .snooze:
            ZStack(alignment: .bottom) {
                PrescriptionStubHost()
                Palette.scrim.ignoresSafeArea()
                SnoozeSheet(choices: CheckInActions.snoozeChoices(nextMealMinutes: 150)) { _ in }
                    .frame(height: SnoozeSheet.height(for: 3))
                    .background(Palette.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
            }
            .ignoresSafeArea(edges: .bottom)
        case .savedMeal:
            SavedMealEditorView(
                draft: SavedMealDraft(from: SavedMeal.samples[0]),
                onSave: { _ in true }
            )
        case .settings:
            NavigationStack { SettingsView(previewModel: .previewed()) }
        case .settingsGoal:
            NavigationStack { GoalSettingsView(model: Self.goalStubModel) }
        case .settingsMealTimes:
            NavigationStack { RhythmSettingsView(model: .previewed()) }
        case .settingsMealTimesWeekends:
            NavigationStack { RhythmSettingsView(model: .previewedWeekends(), startOnWeekends: true) }
        case .settingsFoods:
            NavigationStack { FoodsSettingsView(model: .previewed()) }
        case .settingsSavedMeals:
            NavigationStack { SavedMealsSettingsView(previewMeals: SavedMeal.samples) }
        case .settingsHealth, .settingsHealthWrite:
            NavigationStack { HealthSettingsView() }
        case .calendarSettings:
            NavigationStack { CalendarSettingsView() }
        case .calendarConnect:
            NavigationStack { CalendarConnectView() }
        case .calendarPick:
            NavigationStack { CalendarPickView() }
        case .calendarWeek:
            NavigationStack { CalendarWeekView() }
        case .calendarDay:
            NavigationStack { CalendarDayView(date: "2026-09-15") }
        case .calendarRules:
            NavigationStack { BusyRulesView() }
        case .calendarCalendars:
            NavigationStack { CalendarsView() }
        case .training:
            NavigationStack { TrainingScreen(preview: .sample) }
        case .refuel:
            RefuelSheet(
                checkIn: .init(
                    id: "ci_refuel",
                    tier: 1,
                    status: "PENDING",
                    message: "You trained. Eat something now.",
                    deferUntil: nil,
                    prescription: HomeResponse.sampleUnder.activeCheckIn?.prescription,
                    slot: "refuel",
                    kind: "REFUEL"
                ),
                dinnerMin: 1170,
                remainingSeconds: 18 * 60,
                onHadThis: {},
                onCoveredByDinner: {},
                onDismiss: {}
            )
        case .checkinSmaller:
            if let checkIn = HomeResponse.sampleUnder.activeCheckIn {
                let full = checkIn.prescription!
                let smaller = HomeResponse.ActiveCheckIn.Prescription(
                    id: full.id,
                    totalKcal: full.totalKcal,
                    totalProteinG: full.totalProteinG,
                    items: [
                        .init(name: "Protein smoothie", quantity: 1, kcal: 420, proteinG: 32),
                        .init(name: "Peanut butter toast", quantity: 1, kcal: 250, proteinG: 12),
                    ]
                )
                PrescriptionView(
                    checkIn: checkIn,
                    headline: "Lunch slipped.",
                    whyNow: "Usually 13:00",
                    onDismiss: {},
                    onResolved: {},
                    onAlreadyAte: {},
                    suggestSmallerDefault: true,
                    appetiteLevel: "LOW",
                    previewVariants: .init(full: full, smaller: smaller)
                )
            }
        case .settingsAppetite:
            NavigationStack { AppetiteSettingsView(previewHistory: .sample, previewMode: "SMALL_FREQUENT") }
        case .widgets:
            WidgetsStubHost()
        case let .nutritionAssistant(state):
            NutritionAssistantView(previewModel: .previewed(state))
        case .orderNearby:
            NavigationStack {
                OrderNearbyView(gapKcal: 700, slotTitle: "Lunch", preview: .sample)
            }
        case .burn:
            NavigationStack { BurnScreen(preview: .sample) }
        case .paywall:
            PaywallView()
        case .settingsAccount:
            NavigationStack { AccountSettingsView(model: .previewed()) }
        case .settingsDelete:
            NavigationStack { AccountSettingsView(model: .previewed(), startDeleting: true) }
        case let .settlement(response):
            SettlementView(previewModel: .previewed(response))
        case .settlementLoading:
            SettlementView(previewModel: .previewedLoading())
        }
    }

    private static var goalStubModel: SettingsViewModel {
        let model = SettingsViewModel.previewed()
        model.pace = .gentle
        return model
    }

    static func fromLaunchArguments() -> DebugPreviewStub? {
        guard let index = CommandLine.arguments.firstIndex(of: "-uiStub"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        switch CommandLine.arguments[index + 1] {
        case "home": return .home(.sampleUnder)
        case "home-over": return .home(.sampleOver)
        case "home-loading": return .homeModel(.previewed(.loading))
        case "home-error": return .homeModel(.previewed(.failed("Your phone is offline. I’ll catch up when you’re back.")))
        case "home-stale": return .homeModel(.previewedStale(.sampleOnPace))
        case "home-empty": return .home(.sampleEmpty)
        case "home-snoozed": return .home(.sampleSnoozed)
        case "home-talk": return .home(.sampleTalk)
        case "home-onpace": return .home(.sampleOnPace)
        case "home-missed": return .home(.sampleMissed)
        case "home-quiet": return .home(.sampleQuiet)
        case "home-topup": return .home(.sampleTopUp)
        case "home-light": return .home(.sampleLightCheckIn)
        case "home-close": return .home(.sampleClose)
        case "welcome", "welcome-notice", "welcome-plan", "welcome-quiet": return .welcome
        case "invite": return .invite
        case "onboarding-goal", "onboarding-target": return .onboarding(.goal)
        case "onboarding", "onboarding-about": return .onboarding(.about)
        case "onboarding-rhythm": return .onboarding(.rhythm)
        case "onboarding-restrictions": return .onboarding(.restrictions)
        case "onboarding-safety": return .onboarding(.safety)
        case "onboarding-reach": return .onboarding(.reach)
        case "onboarding-covered", "onboarding-outcome": return .onboarding(.covered)
        case "prescription": return .prescription
        case "conversation": return .conversation(resolved: false)
        case "conversation-resolved": return .conversation(resolved: true)
        case "log-meal": return .logMeal(.compose)
        case "log-meal-parsing": return .logMeal(.parsing)
        case "log-meal-result": return .logMeal(.result)
        case "log-quick": return .logMeal(.quick)
        case "log-scan": return .logMeal(.scan)
        case "scanner": return .scanner(.scanning)
        case "scanner-looking": return .scanner(.lookingUp)
        case "scanner-miss": return .scanner(.notFound)
        case "scanner-label": return .scanner(.readingLabel)
        case "scanner-found": return .scanner(.found)
        case "meal-detail": return .mealDetail
        case "log-typing": return .logMeal(.typing)
        case "log-working": return .logMeal(.working)
        case "log-offline": return .logMeal(.offline)
        case "log-failed": return .logMeal(.failed)
        case "saved-meal": return .savedMeal
        case "fix-meal": return .fixMeal
        case "snooze": return .snooze
        case "settings": return .settings
        case "you": return .settings
        case "calendar-settings":
            CalendarManager.shared.loadPreview(connected: true)
            return .calendarSettings
        case "calendar-connect":
            CalendarManager.shared.loadPreview(connected: false)
            return .calendarConnect
        case "calendar-reconnect":
            CalendarManager.shared.loadPreview(connected: false, reconnect: true)
            return .calendarConnect
        case "calendar-pick":
            CalendarManager.shared.loadPreview(connected: false)
            return .calendarPick
        case "calendar-week":
            CalendarManager.shared.loadPreview(connected: true)
            return .calendarWeek(kept: false)
        case "calendar-week-kept":
            CalendarManager.shared.loadPreview(connected: true, keptTomorrow: true)
            return .calendarWeek(kept: true)
        case "calendar-day":
            CalendarManager.shared.loadPreview(connected: true)
            return .calendarDay
        case "calendar-rules":
            CalendarManager.shared.loadPreview(connected: true)
            return .calendarRules
        case "calendar-calendars":
            CalendarManager.shared.loadPreview(connected: true)
            return .calendarCalendars
        case "home-busy": return .home(.sampleBusy)
        case "home-training": return .home(.sampleTraining)
        case "home-appetite", "home-appetite-low": return .home(.sampleAppetiteLow)
        case "home-appetite-ask": return .home(.sampleAppetiteAsk)
        case "training": return .training
        case "refuel": return .refuel
        case "checkin-smaller", "checkin-not-hungry": return .checkinSmaller
        case "settings-appetite", "appetite-record": return .settingsAppetite
        case "widgets": return .widgets
        case "burn": return .burn
        case "order-nearby": return .orderNearby
        case "assistant": return .nutritionAssistant("chat")
        case "assistant-empty": return .nutritionAssistant("empty")
        case "assistant-consent": return .nutritionAssistant("consent")
        case "paywall": return .paywall
        case "settings-goal": return .settingsGoal
        case "settings-meal-times": return .settingsMealTimes
        case "settings-meal-times-weekends": return .settingsMealTimesWeekends
        case "settings-foods": return .settingsFoods
        case "settings-saved-meals": return .settingsSavedMeals
        case "settings-health", "settings-health-write": return .settingsHealthWrite
        case "settings-account": return .settingsAccount
        case "settings-delete": return .settingsDelete
        case "settlement": return .settlement(.sample)
        case "settlement-weigh-in": return .settlement(.sampleNeedsWeighIn)
        case "settlement-empty", "week-one": return .settlement(.sampleEmpty)
        case "settlement-loading": return .settlementLoading
        default: return nil
        }
    }
}

private struct WidgetsStubHost: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Widgets")
                    .font(Typography.display(28))
                    .foregroundStyle(Palette.ink)
                widgetCard(title: "Small") {
                    TodayWidgetSmallView(snapshot: .preview)
                        .padding(16)
                        .frame(width: 158, height: 158)
                        .background(WidgetChrome.background)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                widgetCard(title: "Medium") {
                    TodayWidgetMediumView(snapshot: .preview)
                        .padding(16)
                        .frame(width: 338, height: 158)
                        .background(WidgetChrome.background)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                widgetCard(title: "Lock Screen") {
                    VStack(spacing: 6) {
                        TodayLockInlineView(snapshot: .preview)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.ink.opacity(0.85))
                        Text(Date.now.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 80, weight: .light))
                            .foregroundStyle(Palette.ink)
                        HStack(spacing: 10) {
                            TodayLockCircularView(snapshot: .preview)
                                .frame(width: 74, height: 74)
                                .background(.ultraThinMaterial, in: Circle())
                            TodayLockRectangularView(snapshot: .preview)
                                .padding(.horizontal, 12)
                                .frame(width: 172, height: 74)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            Color(hex: 0x0B0B10)
                            RadialGradient(colors: [Palette.ember.opacity(0.42), .clear], center: UnitPoint(x: 0.3, y: 0.9), startRadius: 0, endRadius: 260)
                            RadialGradient(colors: [Palette.haze.opacity(0.3), .clear], center: UnitPoint(x: 0.75, y: 0.2), startRadius: 0, endRadius: 220)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            }
            .padding(Space.lg)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private func widgetCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(Typography.data(13, weight: .bold))
                .foregroundStyle(Palette.inkFaint)
            content()
        }
    }
}

private struct LogMealStubHost: View {
    let state: DebugPreviewStub.LogMealStubState

    var body: some View {
        switch state {
        case .compose:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                startComposerExpanded: true
            )
        case .quick:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .sampleQuickLog,
                startComposerExpanded: true
            )
        case .scan:
            LogScanStubHost()
        case .typing:
            HomeContent(
                model: .previewed(.loaded(.sampleUnder)),
                previewLogger: .previewed(.compose, text: "two eggs, toast and a ba"),
                startComposerExpanded: true
            )
        case .working:
            HomeContent(
                model: .previewed(.loaded(.sampleUnder)),
                previewLogger: .previewed(.parsing, submittedPrompt: "two eggs, toast and a banana")
            )
        case .offline:
            HomeContent(
                model: .previewed(.loaded(.sampleUnder)),
                previewLogger: .previewed(.queued("Kept on this phone — I’ll log it when you’re back online."), submittedPrompt: "two eggs, toast and a banana")
            )
        case .failed:
            HomeContent(
                model: .previewed(.loaded(.sampleUnder)),
                previewLogger: .previewed(.failed("Try the foods, like “eggs on toast”."), submittedPrompt: "brekky thing")
            )
        case .parsing:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .samplePhotoParsing
            )
        case .result:
            HomeContent(
                model: .previewed(.loaded(.sampleEmpty)),
                previewLogger: .samplePhotoConfirm
            )
        }
    }
}

private struct FixMealStubHost: View {
    @State private var model = LogMealViewModel.samplePhotoConfirm
    @Namespace private var ns

    var body: some View {
        PhotoParseConfirm(model: model, namespace: ns, imageID: "fix-image", cardID: "fix-card", startEditing: true, onKeep: {})
    }
}

private struct LogScanStubHost: View {
    var body: some View {
        ScannerStubHost(status: .found)
    }
}

/// The scanner over a black stand-in camera, with a live product so the amount
/// picks can be tried.
private struct ScannerStubHost: View {
    let status: LogMealViewModel.ScanStatus
    @State private var product: LogMealViewModel.BarcodeProduct? = .init(food: .sampleYogurt, servings: 1)
    @State private var editor: SavedMealDraft?
    @State private var saved = false

    var body: some View {
        BarcodeScannerView(
            status: status,
            product: $product,
            slotTitle: "Lunch",
            previewAiming: true,
            onCode: { _ in },
            onRescan: {},
            onType: {},
            onLabelPhoto: { _ in },
            onLog: {},
            onSave: { editor = product.map(SavedMealDraft.init(from:)) },
            saved: saved,
            editor: $editor,
            onSaveEditor: { _ in
                saved = true
                return true
            },
            onCancel: {}
        )
    }
}

private struct PrescriptionStubHost: View {
    var body: some View {
        ZStack {
            // A dimmed Home behind, so the morph's depth reads in review.
            HomeContent(model: .previewed(.loaded(.sampleUnder)))
                .disabled(true)
                .overlay { Palette.scrim.ignoresSafeArea().allowsHitTesting(false) }

            if let checkIn = HomeResponse.sampleUnder.activeCheckIn {
                PrescriptionView(
                    checkIn: checkIn,
                    headline: TodayCopy.headline(TodayMoment.resolve(.sampleUnder)),
                    whyNow: TodayCopy.whyNow(.sampleUnder),
                    onDismiss: {},
                    onResolved: {},
                    onAlreadyAte: {}
                )
            }
        }
    }
}
#endif

#Preview("Signed out") {
    RootView().environment(AppEnvironment.preview())
}

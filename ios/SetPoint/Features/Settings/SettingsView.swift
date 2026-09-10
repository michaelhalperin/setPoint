import SwiftUI

/// You tab — identity header plus destination rows (Airbnb profile, not a Form dump).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: SettingsViewModel?
    #if DEBUG
    @State private var showingDevOnboarding = false
    @State private var showingDevMealConfirm = false
    #endif

    init(previewModel: SettingsViewModel? = nil) {
        _model = State(initialValue: previewModel)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                SettingsSkeletonView()
            }
        }
        .task {
            if model == nil {
                let vm = SettingsViewModel(
                    api: env.api,
                    onUnauthorized: { env.auth.handleUnauthorized() },
                    onDeleted: { env.auth.signOut() }
                )
                model = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SettingsViewModel) -> some View {
        switch model.phase {
        case .loading:
            SettingsSkeletonView()
        case let .failed(message):
            ContentUnavailableView("Load failed", systemImage: "person", description: Text(message))
        case .loaded:
            profile(model)
        }
    }

    @ViewBuilder
    private func profile(_ model: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header(model)
                    .appearIn(0)

                planCard(model)
                    .appearIn(1)

                managerStatus(model)
                    .appearIn(2)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Adjust the plan").sectionLabelStyle()
                    HStack(spacing: Space.sm) {
                        NavigationLink {
                            GoalSettingsView(model: model)
                        } label: {
                            YouActionCard(
                                symbol: "scope",
                                title: "Goal",
                                detail: goalSubtitle(model)
                            )
                        }
                        .buttonStyle(PressableCard())

                        NavigationLink {
                            RhythmSettingsView(model: model)
                        } label: {
                            YouActionCard(
                                symbol: "sun.horizon",
                                title: "Rhythm",
                                detail: rhythmSubtitle(model)
                            )
                        }
                        .buttonStyle(PressableCard())
                    }
                }
                .appearIn(3)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Connections & account").sectionLabelStyle()

                    if model.mode == "SMART", env.health.isAvailable {
                        NavigationLink {
                            HealthSettingsView()
                        } label: {
                            YouUtilityRow(
                                symbol: "heart.text.square",
                                title: "Health",
                                value: env.health.connected ? "Connected" : "Not connected"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        AccountSettingsView(model: model)
                    } label: {
                        YouUtilityRow(symbol: "person.crop.circle", title: "Account")
                    }
                    .buttonStyle(.plain)
                }
                .appearIn(4)

                if let error = model.error {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accentDeep)
                        .padding(Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.sm))
                }

                #if DEBUG
                developerTools
                #endif
            }
            .padding(Space.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .fullScreenCover(isPresented: $showingDevOnboarding) {
            DevOnboardingPreview()
        }
        .fullScreenCover(isPresented: $showingDevMealConfirm) {
            DevMealConfirmPreview()
        }
        #endif
    }

    #if DEBUG
    private var developerTools: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Developer")
                .sectionLabelStyle()
                .padding(.top, Space.sm)
                .appearIn(5)

            Button {
                showingDevOnboarding = true
            } label: {
                DestinationRow(title: "Onboarding")
            }
            .buttonStyle(PressableCard())
            .appearIn(6)

            Button {
                showingDevMealConfirm = true
            } label: {
                DestinationRow(title: "Meal confirm", subtitle: "Demo data")
            }
            .buttonStyle(PressableCard())
            .appearIn(7)
        }
    }
    #endif

    @ViewBuilder
    private func header(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("You")
                .font(Typography.display(34))
                .foregroundStyle(Palette.ink)
            Text("The plan SetPoint is running for you.")
                .font(Typography.voice(17))
            .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planCard(_ model: SettingsViewModel) -> some View {
        NavigationLink {
            GoalSettingsView(model: model)
        } label: {
            Card(tint: Palette.surfaceRaised, elevation: .floating, padding: Space.md) {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YOUR PLAN").sectionLabelStyle()
                            Text(planTitle(model))
                                .font(Typography.voice(24))
                                .foregroundStyle(Palette.ink)
                        }
                        Spacer(minLength: Space.sm)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 30, height: 30)
                            .background(Palette.accentTint, in: Circle())
                    }

                    if let progress = planProgress(model),
                       let current = model.currentWeightKg,
                       let target = model.targetWeightKg {
                        VStack(spacing: Space.xs) {
                            ProgressView(value: progress)
                                .tint(Palette.accent)
                            HStack {
                                Text("\(current.formatted(.number.precision(.fractionLength(1)))) kg now")
                                Spacer()
                                Text("\(target.formatted(.number.precision(.fractionLength(0 ... 1)))) kg target")
                            }
                            .font(Typography.data(11, weight: .medium))
                            .foregroundStyle(Palette.inkFaint)
                        }
                    }

                    Divider().overlay(Palette.hairline)

                    HStack(spacing: 0) {
                        planMetric("\(model.kcalTarget)", label: "kcal / day")
                        Divider()
                            .overlay(Palette.hairline)
                            .frame(height: 34)
                            .padding(.horizontal, Space.md)
                        planMetric(
                            model.proteinTarget.map { String($0) } ?? "—",
                            label: "protein g"
                        )
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(PressableCard())
    }

    private func managerStatus(_ model: SettingsViewModel) -> some View {
        let active = model.enforcementEnabled && !model.checkInsPaused
        return Card(tint: active ? Palette.accentTint : Palette.surface, padding: 14) {
            HStack(spacing: Space.sm) {
                Image(systemName: active ? "waveform.path.ecg" : "moon.zzz")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? Palette.accentDeep : Palette.inkSoft)
                    .frame(width: 38, height: 38)
                    .background(active ? Palette.surface : Palette.surfaceSunk, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(managerTitle(model))
                        .font(Typography.data(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(managerDetail(model))
                        .font(Typography.data(12))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.xs)

                if model.enforcementEnabled {
                    Button {
                        Task { await model.setCheckInsPaused(!model.checkInsPaused) }
                    } label: {
                        Text(model.checkInsPaused ? "Resume" : "Pause")
                            .font(Typography.data(12, weight: .semibold))
                            .foregroundStyle(active ? Palette.accentDeep : Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Palette.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.saving)
                    .opacity(model.saving ? 0.5 : 1)
                }
            }
        }
    }

    private func goalSubtitle(_ model: SettingsViewModel) -> String {
        if model.goal.hasWeightTarget, let target = model.targetWeightKg {
            return "\(model.goal.title) to \(Int(target.rounded())) kg"
        }
        return "Hold steady"
    }

    private func rhythmSubtitle(_ model: SettingsViewModel) -> String {
        model.checkInsPaused
            ? "Check-ins paused"
            : "\(formatMinutes(model.mealTimes.breakfastMin))–\(formatMinutes(model.mealTimes.dinnerMin))"
    }

    private func planMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.data(22, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(Typography.data(11))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    private func planTitle(_ model: SettingsViewModel) -> String {
        guard model.goal.hasWeightTarget, let target = model.targetWeightKg else {
            return "Hold steady."
        }
        return "\(model.goal.directionVerb) \(Int(target.rounded())) kg."
    }

    private func planProgress(_ model: SettingsViewModel) -> Double? {
        guard model.goal.hasWeightTarget,
              let start = model.startWeightKg,
              let current = model.currentWeightKg,
              let target = model.targetWeightKg,
              target != start else { return nil }
        return min(max((current - start) / (target - start), 0), 1)
    }

    private func managerTitle(_ model: SettingsViewModel) -> String {
        if !model.enforcementEnabled { return "Quiet tracking" }
        return model.checkInsPaused ? "Check-ins paused" : "Manager active"
    }

    private func managerDetail(_ model: SettingsViewModel) -> String {
        if !model.enforcementEnabled {
            return enforcementNote(model.enforcementDisabledReason)
        }
        if model.checkInsPaused {
            return "Your plan still updates. SetPoint won't initiate a conversation."
        }
        return "Watching your meal rhythm and stepping in only when useful."
    }
}

private struct YouActionCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(Palette.accentTint, in: Circle())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.data(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.data(11))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
    }
}

private struct YouUtilityRow: View {
    let symbol: String
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 28)
            Text(title)
                .font(Typography.data(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let value {
                Text(value)
                    .font(Typography.data(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.hairline)
        )
    }
}

struct DestinationRow: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.data(17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
                .elevation(.resting)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
        }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    var c = DateComponents()
    c.hour = h
    c.minute = m
    let date = Calendar.current.date(from: c) ?? .now
    let f = DateFormatter()
    f.timeStyle = .short
    return f.string(from: date)
}

func enforcementNote(_ reason: String?) -> String {
    switch reason {
    case "EATING_DISORDER_SCREEN":
        return "Quiet tracking is on. A professional can help if eating feels hard."
    case "MEDICAL_SUPERVISION":
        return "Quiet tracking is on. Follow your care team’s plan."
    default:
        return "Check-ins are off."
    }
}

private struct SettingsSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 72, height: 34, radius: 10)
                    SkeletonBlock(width: 232, height: 15)
                }

                SkeletonCard(height: 154) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SkeletonBlock(width: 64, height: 10)
                        SkeletonBlock(width: 176, height: 24)
                        SkeletonBlock(height: 5, radius: 3)
                        HStack(spacing: Space.xl) {
                            SkeletonBlock(width: 76, height: 34)
                            SkeletonBlock(width: 64, height: 34)
                        }
                    }
                }

                SkeletonCard(height: 66) {
                    HStack(spacing: Space.sm) {
                        SkeletonBlock(width: 38, height: 38, radius: 19)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 112, height: 13)
                            SkeletonBlock(width: 196, height: 10)
                        }
                    }
                }

                HStack(spacing: Space.sm) {
                    SkeletonCard(height: 122) { SkeletonBlock(width: 84, height: 50) }
                    SkeletonCard(height: 122) { SkeletonBlock(width: 98, height: 50) }
                }

                VStack(spacing: Space.sm) {
                    destinationRow(titleWidth: 72, detailWidth: 94)
                    destinationRow(titleWidth: 82, detailWidth: 0)
                }
            }
            .padding(Space.gutter)
        }
        .background(Palette.background.ignoresSafeArea())
        .scrollDisabled(true)
        .skeletonLoading()
    }

    private func destinationRow(titleWidth: CGFloat, detailWidth: CGFloat) -> some View {
        SkeletonCard(height: 48) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock(width: titleWidth, height: 15)
                    if detailWidth > 0 {
                        SkeletonBlock(width: detailWidth, height: 11)
                    }
                }
                Spacer()
                SkeletonBlock(width: 8, height: 16, radius: 4)
            }
        }
    }
}

#if DEBUG
private struct DevOnboardingPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: OnboardingViewModel?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let model {
                OnboardingFlow(model: model)
            } else {
                Palette.background.ignoresSafeArea()
            }

            Button("Close preview") { dismiss() }
                .font(Typography.data(13, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
                .padding(.trailing, Space.gutter)
                .padding(.top, 6)
        }
        .onAppear {
            if model == nil {
                model = .previewed(at: .welcome, onComplete: { dismiss() })
            }
        }
    }
}

private struct DevMealConfirmPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = LogMealViewModel.samplePhotoConfirm
    @Namespace private var ns

    var body: some View {
        PhotoParseConfirm(
            model: model,
            namespace: ns,
            imageID: "dev-confirm-image",
            cardID: "dev-confirm-card",
            onReject: { dismiss() },
            onKeep: { dismiss() }
        )
    }
}

#Preview {
    NavigationStack { SettingsView(previewModel: .previewed()) }
        .environment(AppEnvironment.preview())
}
#endif

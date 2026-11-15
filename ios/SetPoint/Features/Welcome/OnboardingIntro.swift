import SwiftUI

/// Signed-out entry. Six short screens sell the idea (the hook, the gap, plates,
/// the nudge, the top-up, the close), then the setup questions, then the plan,
/// and only then the account. Nothing is asked of anyone before they have seen
/// what they get.
struct SignedOutIntro: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: OnboardingViewModel?
    @State private var page: Int
    @State private var inQuestions = false

    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
    }

    /// Story pages after the hook.
    private static let lastPage = 5

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let model {
                if inQuestions {
                    OnboardingFlow(model: model)
                        .transition(.opacity)
                } else {
                    story
                        .id(page)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: page)
        .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: inQuestions)
        .onAppear(perform: makeModel)
    }

    private func makeModel() {
        guard model == nil else { return }
        let created = OnboardingViewModel(api: env.api, progressStore: .standard, onComplete: {})
        created.backToStory = {
            page = Self.lastPage
            inQuestions = false
        }
        model = created
        // Someone who already started the questions picks up where they were.
        if created.hasSavedAnswers { inQuestions = true }
    }

    private func next() {
        if page >= Self.lastPage {
            inQuestions = true
        } else {
            page += 1
        }
    }

    @ViewBuilder
    private var story: some View {
        switch page {
        case 0:
            WelcomeView(onStart: next)
        case 1:
            StoryFrame(index: 1, headline: "You burn more", tail: "than you eat.", onBack: back, onNext: next, onSkip: skip) { GapVisual() }
        case 2:
            StoryFrame(index: 2, headline: "Every plate,", tail: "planned.", onBack: back, onNext: next, onSkip: skip) { PlatesVisual() }
        case 3:
            StoryFrame(index: 3, headline: "A nudge before", tail: "a meal slips.", onBack: back, onNext: next, onSkip: skip) { NudgeVisual() }
        case 4:
            StoryFrame(index: 4, headline: "Not hungry?", tail: "Top it up.", onBack: back, onNext: next, onSkip: skip) { TopUpVisual() }
        default:
            StoryFrame(index: 5, headline: "Close every day", tail: "on target.", nextTitle: "Build my plan", onBack: back, onNext: next, onSkip: skip) { CloseVisual() }
        }
    }

    private func back() { page = max(0, page - 1) }
    private func skip() { inQuestions = true }
}

// MARK: - Frame

private struct StoryFrame<Visual: View>: View {
    let index: Int
    let headline: String
    let tail: String
    var nextTitle = "Next"
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    @ViewBuilder var visual: Visual

    private let total = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundIconButton("chevron.backward", label: "Back", action: onBack)
                    .frame(width: 40, height: 40)
                HStack(spacing: 5) {
                    ForEach(0 ..< total, id: \.self) { i in
                        Capsule()
                            .fill(i < index ? Palette.ink : (i == index ? Palette.ember : Color.white.opacity(0.14)))
                            .frame(height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(total)")
                Button("Skip", action: onSkip)
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)

            Headline(headline, tail: tail, size: 42)
                .padding(.top, 30)
                .appearIn(0, rise: 14)

            Spacer(minLength: Space.md)

            visual
                .appearIn(1, rise: 16)

            Spacer(minLength: Space.md)

            ActionButton(title: nextTitle, action: onNext)
                .appearIn(2, rise: 14)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.xs)
        .background(alignment: .topTrailing) {
            RadialGradient(colors: [Palette.ember.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 170)
                .frame(width: 340, height: 340)
                .blur(radius: 20)
                .offset(x: 120, y: -80)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Visuals (examples, labelled as such)

private struct GapVisual: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            bar("What a training day needs", value: "3,450", fraction: 1, fill: AnyShapeStyle(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing)), valueColor: Palette.amber)
            bar("What you actually eat", value: "2,300", fraction: 0.67, fill: AnyShapeStyle(Palette.haze.opacity(0.55)), valueColor: Palette.hazeSoft)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 4])))
            HStack {
                Text("Short by")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
                Spacer()
                Text("1,150 kcal")
                    .font(Typography.mono(22))
                    .foregroundStyle(Palette.ink)
            }
            Text("Example · 80 kg lifter, trains 5×/week")
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(20)
        .glass(radius: 26)
    }

    private func bar(_ label: String, value: String, fraction: CGFloat, fill: AnyShapeStyle, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(label))
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
                Spacer()
                Text(value).font(Typography.mono(13)).foregroundStyle(valueColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(fill).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct PlatesVisual: View {
    var body: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Next · lunch · 13:00").sectionLabelStyle()
                    Spacer()
                    Text("~700 kcal").font(Typography.mono(12)).foregroundStyle(Palette.amber)
                }
                Headline("Pick one.", tail: "Tap when it’s eaten.", size: 24)
                VStack(spacing: 8) {
                    row("Chicken rice bowl", note: "· your usual", kcal: "720", primary: true)
                    row("Wrap + chocolate milk", note: "", kcal: "690", primary: false)
                }
            }
            .padding(18)
            .glass(radius: 26)

            HStack(spacing: 0) {
                ForEach(Array(["08:00", "10:30", "13:00", "16:00", "19:30"].enumerated()), id: \.offset) { index, time in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(index < 2 ? Palette.amber : Palette.background)
                            .overlay(Circle().strokeBorder(index == 2 ? Palette.amber : Color.white.opacity(index < 2 ? 0 : 0.3), lineWidth: index == 2 ? 2 : 1.5))
                            .frame(width: 13, height: 13)
                            .shadow(color: index == 2 ? Palette.amber.opacity(0.8) : .clear, radius: 6)
                        Text(time)
                            .font(Typography.mono(10))
                            .foregroundStyle(index == 2 ? Palette.ink : Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func row(_ name: String, note: String, kcal: String, primary: Bool) -> some View {
        HStack(spacing: 12) {
            (Text(LocalizedStringKey(name)) + Text(note.isEmpty ? "" : " \(note)").font(Typography.data(12, weight: .regular)).foregroundColor(Palette.inkFaint))
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 4)
            Text(kcal).font(Typography.mono(12)).foregroundStyle(Palette.inkSoft)
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primary ? Palette.onBone : Palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(primary ? Palette.ink : Color.white.opacity(0.10)))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

private struct NudgeVisual: View {
    var body: some View {
        VStack(spacing: 10) {
            card(title: "Breakfast logged", text: "700 kcal")
                .scaleEffect(0.94)
                .opacity(0.55)
            card(title: "Lunch is 40 min late", text: "Chicken rice bowl · 720 kcal")
            HStack(spacing: 8) {
                Text("Log it")
                    .font(Typography.data(14, weight: .medium))
                    .foregroundStyle(Palette.onBone)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.ink))
                Text("Later")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func card(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FuelOrb(size: 18, breathing: false, glow: 0)
                .frame(width: 34, height: 34)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(LocalizedStringKey(title))
                        .font(Typography.data(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("now").font(Typography.data(11, weight: .regular)).foregroundStyle(Palette.inkSoft)
                }
                Text(LocalizedStringKey(text))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Color(hex: 0xD4D4D8))
            }
        }
        .padding(12)
        .background(Color(hex: 0x28282E, opacity: 0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

private struct TopUpVisual: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Lunch").sectionLabelStyle()
                Spacer()
                Text("420 of 700").font(Typography.mono(12)).foregroundStyle(Palette.inkSoft)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Palette.amber).frame(width: geo.size.width * 0.6)
                    Capsule()
                        .strokeBorder(Palette.haze.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: geo.size.width * 0.6)
                }
            }
            .frame(height: 8)
            Text("Short by 280.")
                .font(Typography.data(18, weight: .light))
                .foregroundStyle(Palette.ink)
            VStack(spacing: 8) {
                addOn("Chocolate milk", "300")
                addOn("Greek yogurt + honey", "260")
                addOn("Banana + peanut butter", "290")
            }
        }
        .padding(18)
        .glass(radius: 26)
    }

    private func addOn(_ name: String, _ kcal: String) -> some View {
        HStack {
            Text(LocalizedStringKey(name)).font(Typography.data(15, weight: .regular)).foregroundStyle(Palette.ink)
            Spacer()
            Text("+\(kcal)").font(Typography.mono(13)).foregroundStyle(Palette.amber)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

private struct CloseVisual: View {
    private let week: [(String, CGFloat)] = [("M", 1), ("T", 0.99), ("W", 1), ("T", 0.78), ("F", 1), ("S", 0.97), ("S", 1)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: 0x86EFAC)).frame(width: 8, height: 8)
                    Text("Day closed").font(Typography.data(14, weight: .regular)).foregroundStyle(Palette.ink)
                }
                Spacer()
                Text("3,460 / 3,450").font(Typography.mono(15)).foregroundStyle(Palette.amber)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(day.1 >= 0.95 ? AnyShapeStyle(LinearGradient(colors: [Palette.amber, Palette.ember], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Palette.haze.opacity(0.55)))
                                .frame(height: 86 * day.1)
                        }
                        .frame(height: 86)
                        Text(day.0).font(Typography.mono(11)).foregroundStyle(Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Example week")
                .font(Typography.mono(11))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(20)
        .glass(radius: 26)
    }
}

#if DEBUG
#Preview {
    SignedOutIntro().environment(AppEnvironment.preview())
}
#endif

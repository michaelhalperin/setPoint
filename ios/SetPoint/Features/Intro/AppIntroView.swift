import SwiftUI

/// Four cards that explain the app, shown once after setup and again from
/// You → "How SetPoint works". Swipe or tap Next; Skip is always there.
struct AppIntroView: View {
    /// Storage flag: set once the cards have been seen (or skipped).
    static let seenKey = "intro.seen.v1"

    let onDone: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [IntroPage] = IntroPage.all

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AmbientGlow(tone: pages[page].tone, strength: 0.7)
                .offset(y: -150)
                .ignoresSafeArea()
                .animation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion), value: page)

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        card(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                ActionButton(
                    title: page == pages.count - 1 ? "Get started" : "Next",
                    symbol: page == pages.count - 1 ? "checkmark" : "arrow.forward"
                ) {
                    advance()
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.md)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            StepBars(step: page + 1, total: pages.count)
            Spacer(minLength: 0)
            Button {
                onDone()
            } label: {
                Text("Skip")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
            }
            .buttonStyle(PressableCard())
            .opacity(page == pages.count - 1 ? 0 : 1)
            .accessibilityHidden(page == pages.count - 1)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.sm)
        .frame(height: 56)
    }

    private func card(_ page: IntroPage) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer(minLength: 0)
            IntroPicture(kind: page.picture)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(page.label).sectionLabelStyle(page.tone == .haze ? Palette.hazeSoft : Palette.amber)
                Headline(page.title, tail: page.tail, size: 32, persistTail: true)
                Text(page.body)
                    .font(Typography.data(16, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion)) { page += 1 }
        } else {
            onDone()
        }
    }
}

// MARK: Content

private struct IntroPage {
    enum Picture { case gap, dayLine, checkIn, training }

    let picture: Picture
    let tone: AmbientGlow.Tone
    let label: String
    let title: String
    let tail: String
    let body: String

    static let all: [IntroPage] = [
        IntroPage(
            picture: .gap,
            tone: .ember,
            label: "How it works",
            title: "Training is half of it.",
            tail: "Eating enough is the other half.",
            body: "SetPoint watches your day and closes the gap between what you ate and what your training needs."
        ),
        IntroPage(
            picture: .dayLine,
            tone: .mixed,
            label: "Today",
            title: "Your day is one line.",
            tail: "See where you should be.",
            body: "The ticks are your meal times and the dots are what you ate. The marker is now. Whatever comes next shows up as a single card."
        ),
        IntroPage(
            picture: .checkIn,
            tone: .ember,
            label: "Check-ins",
            title: "Skipped or light?",
            tail: "I’ll ask.",
            body: "When a meal is missed or small, I check in. Log it, swap it, or top up with something easy like milk or nuts. In the evening I close what’s left."
        ),
        IntroPage(
            picture: .training,
            tone: .haze,
            label: "Train",
            title: "Training moves your plan.",
            tail: "Add a session, targets rise.",
            body: "Plan your sessions on the Train tab. Tap + any time to log a meal by text, photo or barcode."
        ),
    ]
}

// MARK: Pictures

/// A small drawing for each card, built from the same pieces as the real screens.
private struct IntroPicture: View {
    let kind: IntroPage.Picture

    var body: some View {
        GlassCard(padding: 20, spacing: 14) {
            switch kind {
            case .gap: gap
            case .dayLine: dayLine
            case .checkIn: checkIn
            case .training: training
            }
        }
    }

    private var gap: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Needed today").sectionLabelStyle()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceSunk)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.amber, Palette.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * 0.58)
                    Capsule()
                        .strokeBorder(Palette.amber.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: proxy.size.width * 0.42)
                        .offset(x: proxy.size.width * 0.58)
                }
            }
            .frame(height: 22)
            HStack {
                Label("Ate", systemImage: "circle.fill")
                    .foregroundStyle(Palette.amber)
                Spacer()
                Label("The gap", systemImage: "circle.dashed")
                    .foregroundStyle(Palette.inkSoft)
            }
            .font(Typography.mono(11))
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
        }
    }

    private var dayLine: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Today").sectionLabelStyle()
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 2)
                    Capsule().fill(Palette.ink.opacity(0.5)).frame(width: w * 0.52, height: 2)
                    ForEach([0.12, 0.5, 0.88], id: \.self) { x in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 2, height: 14)
                            .offset(x: w * x)
                    }
                    ForEach([0.12, 0.5], id: \.self) { x in
                        Circle().fill(Palette.ink).frame(width: 12, height: 12)
                            .offset(x: w * x - 5)
                    }
                    Capsule().fill(Palette.ember).frame(width: 3, height: 26)
                        .shadow(color: Palette.ember.opacity(0.7), radius: 6)
                        .offset(x: w * 0.52)
                }
                .frame(height: 30)
            }
            .frame(height: 30)
            HStack(spacing: 8) {
                EmberDot()
                Text("Next: dinner").font(Typography.data(14, weight: .regular)).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glass(radius: Radius.sm, fill: Palette.glassHi)
        }
    }

    private var checkIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lunch was light").sectionLabelStyle(Palette.amber)
            Text("A glass of milk and a spoon of peanut butter gets you back on track.")
                .font(Typography.voice(16))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("I ate this")
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.onBone)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Capsule().fill(Palette.ink))
                Text("Something else")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).frame(height: 38)
                    .glassCapsule(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10))
            }
        }
    }

    private var training: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This week").sectionLabelStyle(Palette.hazeSoft)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0 ..< 7, id: \.self) { day in
                    let trains = [1, 3, 5].contains(day)
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(trains ? Palette.haze : Color.white.opacity(0.10))
                            .frame(height: trains ? 64 : 40)
                        Text(trains ? "+" : "·")
                            .font(Typography.mono(11))
                            .foregroundStyle(trains ? Palette.hazeSoft : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
    }
}

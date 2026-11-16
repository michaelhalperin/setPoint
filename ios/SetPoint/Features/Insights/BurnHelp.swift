import SwiftUI

/// "How this works" for Your burn, picture first: three steps that add up to the number (with the
/// person's own figures once there are some), what it needs and how far along it is, how sure we
/// are, and three small tips. A sentence each at most.
struct BurnHelpSheet: View {
    let insight: BurnInsightResponse?

    private static let kcalPerKg = 7700.0

    private var ready: Bool { insight?.ready == true && insight?.burnKcal != nil }

    private var ate: Int { insight?.avgIntakeKcal ?? 2_900 }
    private var burn: Int { insight?.burnKcal ?? 2_800 }
    /// What went into (or came off) the weight each day, from the weight trend.
    private var toWeight: Int {
        if ready, let slope = insight?.slopeKgPerDay { return Int((slope * Self.kcalPerKg).rounded()) }
        return ate - burn
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                steps
                friendlyNote
                needs
                if ready { sure }
                tips
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, Space.lg)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) { AmbientGlow(tone: .ember, strength: 0.5).offset(y: -150).ignoresSafeArea() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works").sectionLabelStyle(Palette.amber)
            Text("Your burn, explained.")
                .font(Typography.display(34))
                .tracking(-1.2)
                .foregroundStyle(Palette.ink)
            Text("The calories your body uses in a day. Even sitting still.")
                .font(Typography.data(15, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Three steps that add up

    private var steps: some View {
        VStack(spacing: 0) {
            if !ready {
                HStack {
                    Spacer()
                    Text("An example")
                        .font(Typography.mono(10))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.amber)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Palette.amber.opacity(0.14), in: Capsule())
                }
                .padding(.bottom, 8)
            }
            step(symbol: "fork.knife", title: "You eat", note: "From your meal logs", value: ate.formatted(), unit: "a day", tone: .plain)
            joiner("minus")
            step(symbol: "scalemass", title: toWeight >= 0 ? "Goes into your weight" : "Comes off your weight", note: "From your weigh-ins", value: abs(toWeight).formatted(), unit: "a day", tone: .plain)
            joiner("equal")
            step(symbol: "flame.fill", title: "You burn", note: "What’s left over", value: burn.formatted(), unit: "a day", tone: .burn)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 26, fill: Color.white.opacity(0.035))
    }

    private enum Tone { case plain, burn }

    private func step(symbol: String, title: String, note: String, value: String, unit: String, tone: Tone) -> some View {
        let burning = tone == .burn
        return HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(burning ? Palette.amber : Palette.inkSoft)
                .frame(width: 46, height: 46)
                .background {
                    Circle().fill(burning ? AnyShapeStyle(Palette.ember.opacity(0.16)) : AnyShapeStyle(Color.white.opacity(0.06)))
                }
                .overlay(Circle().strokeBorder(burning ? Color(hex: 0xFF8A50, opacity: 0.55) : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(Typography.data(16, weight: .medium)).foregroundStyle(Palette.ink)
                Text(LocalizedStringKey(note)).font(Typography.data(12, weight: .regular)).foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .font(Typography.data(burning ? 26 : 22, weight: .light))
                    .tracking(-0.8)
                    .foregroundStyle(burning ? Palette.amber : Palette.ink)
                Text(LocalizedStringKey(unit)).font(Typography.mono(9)).foregroundStyle(Palette.inkFaint)
            }
        }
    }

    /// The "−" or "=" between two steps, on the line that joins their icons.
    private func joiner(_ kind: String) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1.5, height: 30)
                Image(systemName: kind == "minus" ? "minus" : "equal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(width: 18, height: 18)
                    .background(Palette.sheet, in: Circle())
            }
            .frame(width: 46)
            Spacer()
        }
    }

    private var friendlyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.amber)
                .padding(.top, 2)
            Text("Eat 3,000 and stay the same weight? You burn about 3,000. Eat 3,000 and gain? You burn less.")
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amber.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.amber.opacity(0.22)))
    }

    // MARK: What it needs

    private var needs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("It needs a few weeks").sectionLabelStyle()
            need("Logged days", value: insight?.loggedDays ?? 0, goal: 28)
            need("Weigh-ins", value: insight?.weighIns ?? 0, goal: 6)
            Text("One week of weight is mostly water and salt. A few weeks shows the real trend.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }

    private func need(_ title: String, value: Int, goal: Int) -> some View {
        let done = value >= goal
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(title)).font(Typography.data(14, weight: .regular)).foregroundStyle(Palette.ink)
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.positive)
                }
                Text(L10n("\(value) of \(goal)")).font(Typography.mono(11)).foregroundStyle(done ? Palette.positive : Palette.inkSoft)
            }
            Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.ember, Palette.amber], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * min(1, CGFloat(value) / CGFloat(goal))))
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: How sure

    /// The likely range as a bar with the burn on it, the two ends named under it.
    private var sure: some View {
        let low = insight?.rangeLow ?? burn - 80
        let high = insight?.rangeHigh ?? burn + 80
        let lo = Double(low - 160), hi = Double(high + 160)
        let at = { (kcal: Int) -> CGFloat in CGFloat((Double(kcal) - lo) / max(1, hi - lo)) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("How sure we are").sectionLabelStyle()
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8).offset(y: 5)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.ember.opacity(0.5), Palette.amber.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, (at(high) - at(low)) * w), height: 8)
                        .offset(x: at(low) * w, y: 5)
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFE9CC), Palette.amber, Color(hex: 0xF06A2E)], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 10))
                        .frame(width: 18, height: 18)
                        .shadow(color: Palette.ember.opacity(0.7), radius: 6)
                        .offset(x: at(burn) * w - 9)
                    Text(low.formatted())
                        .font(Typography.mono(11)).foregroundStyle(Palette.amber)
                        .fixedSize()
                        .position(x: min(max(at(low) * w, 20), w - 20), y: 36)
                    Text(high.formatted())
                        .font(Typography.mono(11)).foregroundStyle(Palette.amber)
                        .fixedSize()
                        .position(x: min(max(at(high) * w, 20), w - 20), y: 36)
                }
            }
            .frame(height: 46)
            Text("The more days you log, the narrower it gets.")
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22, fill: Color.white.opacity(0.035))
    }

    // MARK: Tips

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To make it sharper").sectionLabelStyle().padding(.horizontal, 4)
            tip("fork.knife", "Log every meal, even a rough one.")
            tip("scalemass", "Weigh in once a week, same time of day.")
            tip("calendar", "It updates every Sunday.")
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.amber)
                .frame(width: 34, height: 34)
                .background(Palette.amber.opacity(0.12), in: Circle())
            Text(LocalizedStringKey(text))
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

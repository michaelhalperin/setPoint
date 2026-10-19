import SwiftUI

/// Signed-out entry: one cinematic screen. The fuel orb breathing behind three
/// floating moments from a real day (a meal landing, a refuel countdown, a day
/// closed), the pitch, and Start. Start opens Sign in with Apple; setup follows.
struct WelcomeView: View {
    @State private var showingSignIn = false
    /// When set, skip Sign in and call this instead — the developer preview
    /// walks Welcome then the setup flow without leaving the signed-in app.
    var onStart: (() -> Void)? = nil

    init(onStart: (() -> Void)? = nil) {
        self.onStart = onStart
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            GeometryReader { geo in
                let width = geo.size.width
                ZStack {
                    WelcomeGlow()
                        .frame(width: width + 120, height: 480)
                        .position(x: width / 2, y: 230)

                    LoopingPhase(period: 60, still: 0) { t in
                        Circle()
                            .strokeBorder(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .frame(width: 300, height: 300)
                            .rotationEffect(.degrees(360 * t))
                    }
                    .position(x: width / 2, y: 228)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.10))
                        .frame(width: 240, height: 240)
                        .position(x: width / 2, y: 228)

                    FuelOrb(size: 200, glow: 0.45)
                        .position(x: width / 2, y: 228)

                    FloatingMoment(period: 5, offset: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.amber)
                                .frame(width: 22, height: 22)
                                .background(Palette.amber.opacity(0.16), in: Circle())
                            Text("Lunch")
                            Text("680 kcal").font(Typography.mono(12)).foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .position(x: 100, y: 128)

                    FloatingMoment(period: 6, offset: 2) {
                        HStack(spacing: 8) {
                            Circle().fill(Palette.hazeSoft).frame(width: 6, height: 6)
                                .shadow(color: Palette.haze, radius: 5)
                            Text("Refuel in")
                            Text("18:42").font(Typography.mono(12)).foregroundStyle(Palette.hazeSoft)
                        }
                    }
                    .position(x: width - 92, y: 254)

                    FloatingMoment(period: 5.5, offset: 4) {
                        HStack(spacing: 8) {
                            Text("Day closed")
                            Text("3,460 / 3,450").font(Typography.mono(12)).foregroundStyle(Palette.amber)
                        }
                    }
                    .position(x: 126, y: 362)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                Text("For people who train and can’t eat enough")
                    .font(Typography.data(12, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                    .appearIn(1, rise: 16)
                Headline("Eat enough to grow,", tail: "without forcing it.", size: 44)
                    .appearIn(2, rise: 16)
                Text("Your plates, planned. A nudge when a meal slips. Easy calories when appetite is low.")
                    .font(Typography.data(16, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(3, rise: 16)
                VStack(spacing: 6) {
                    ActionButton(title: "Start · 60-second setup", action: start)
                    if onStart == nil {
                        Button("I already have an account") { showingSignIn = true }
                            .font(Typography.data(14, weight: .regular))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.top, 4)
                .appearIn(4, rise: 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, Space.xs)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInSheet()
        }
    }

    private func start() {
        if let onStart {
            onStart()
        } else {
            showingSignIn = true
        }
    }
}

/// Ember, haze and amber light pooled behind the orb.
private struct WelcomeGlow: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Palette.ember.opacity(0.55), .clear], center: UnitPoint(x: 0.42, y: 0.46), startRadius: 0, endRadius: 230)
            RadialGradient(colors: [Color(hex: 0xA5B4FC).opacity(0.30), .clear], center: UnitPoint(x: 0.72, y: 0.30), startRadius: 0, endRadius: 200)
            RadialGradient(colors: [Palette.amber.opacity(0.25), .clear], center: UnitPoint(x: 0.30, y: 0.75), startRadius: 0, endRadius: 200)
        }
        .blur(radius: 30)
        .appearIn(0, rise: 0)
    }
}

/// A small glass capsule that floats up and down.
private struct FloatingMoment<Content: View>: View {
    let period: Double
    let offset: Double
    @ViewBuilder var content: Content

    var body: some View {
        LoopingPhase(period: period, offset: offset, still: 0.5) { t in
            content
                .font(Typography.data(12, weight: .regular))
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(hex: 0x141417, opacity: 0.75), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
                .fixedSize()
                .offset(y: -9 * (1 - cos(t * 2 * .pi)) / 2)
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AppEnvironment.preview())
}

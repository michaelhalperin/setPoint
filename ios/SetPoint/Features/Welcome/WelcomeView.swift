import SwiftUI

/// Signed-out entry: the pitch, four swipeable pages that show what SetPoint
/// does before asking for anything. "Build my plan" (or "I already have an
/// account") opens Sign in with Apple; setup follows sign-in.
struct WelcomeView: View {
    @State private var page: Int
    @State private var showingSignIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4

    init(initialPage: Int = 0) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            (page == 0 ? Palette.accent : Palette.background)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: page)

            TabView(selection: $page) {
                WelcomeHookPage().background(Palette.accent.ignoresSafeArea()).tag(0)
                WelcomeNoticePage().background(Palette.background.ignoresSafeArea()).tag(1)
                WelcomePlanPage().background(Palette.background.ignoresSafeArea()).tag(2)
                WelcomeQuietPage().background(Palette.background.ignoresSafeArea()).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay(alignment: .bottom) {
            controls
                .padding(.horizontal, 24)
                .padding(.bottom, Space.xs)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInSheet()
        }
    }

    @ViewBuilder
    private var controls: some View {
        if page == 0 {
            VStack(spacing: Space.sm) {
                Button { go(to: 1) } label: {
                    HStack(spacing: 8) {
                        Text("See how")
                        Image(systemName: "arrow.right")
                    }
                    .font(Typography.data(17, weight: .bold))
                    .foregroundStyle(Palette.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableCard())

                Button("I already have an account") { showingSignIn = true }
                    .font(Typography.data(15, weight: .semibold))
                    .foregroundStyle(Palette.background.opacity(0.85))
                    .padding(.vertical, 6)
            }
        } else {
            HStack {
                PageDots(current: page, count: pageCount)
                Spacer()
                if page < pageCount - 1 {
                    Button { go(to: page + 1) } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Palette.accent, in: Circle())
                            .elevation(.resting)
                    }
                    .buttonStyle(PressableCard())
                    .accessibilityLabel("Next")
                } else {
                    Button { showingSignIn = true } label: {
                        HStack(spacing: 10) {
                            Text("Build my plan")
                            Image(systemName: "arrow.right")
                        }
                        .font(Typography.data(17, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 60)
                        .background(Palette.accent, in: Capsule())
                        .elevation(.resting)
                    }
                    .buttonStyle(PressableCard())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(height: 72)
            .animation(Motion.adaptive(Motion.settle, reduceMotion: reduceMotion), value: page)
        }
    }

    private func go(to next: Int) {
        withAnimation(Motion.adaptive(Motion.enter, reduceMotion: reduceMotion)) { page = next }
    }
}

private struct PageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.accent : Color(hex: 0xDDD3C6))
                    .frame(width: index == current ? 22 : 6, height: 6)
            }
        }
        .animation(Motion.settle, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

#Preview {
    WelcomeView()
        .environment(AppEnvironment.preview())
}

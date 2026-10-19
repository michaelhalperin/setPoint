import SwiftUI

/// After Sign in with Apple, while sign-up is invite-only: a new account enters
/// the code it was given (by a trainer, for a pilot). Existing accounts never
/// see this.
struct InviteCodeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SetPoint").sectionLabelStyle()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.sm)

            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 22) {
                Headline("SetPoint is invite-only for now.", tail: "Enter your code to get in.", size: 38)
                    .appearIn(0, rise: 16)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("", text: $code, prompt: Text("Invite code").foregroundStyle(Palette.inkFaint))
                        .font(Typography.mono(24, weight: .medium))
                        .tracking(3)
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .focused($focused)
                        .onSubmit(join)
                        .onChange(of: code) { _, _ in error = nil }
                        .padding(.horizontal, 20)
                        .frame(height: 64)
                        .glass(
                            radius: 22,
                            fill: Color.white.opacity(0.05),
                            stroke: error == nil ? (focused ? Palette.hairlineHi : Palette.hairline) : Palette.danger.opacity(0.6)
                        )
                        .accessibilityLabel("Invite code")

                    if let error {
                        Text(error)
                            .font(Typography.data(13, weight: .regular))
                            .foregroundStyle(Palette.danger)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                }
                .appearIn(1, rise: 12)

                ActionButton(title: "Join", busy: checking, busyTitle: "Checking", action: join)
                    .disabled(trimmed.isEmpty || checking)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                    .appearIn(2, rise: 12)

                Text("No code? Ask your trainer.")
                    .font(Typography.data(14, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .appearIn(3)
            }

            Spacer(minLength: 40)

            Button("Use a different Apple ID") { env.auth.signOut() }
                .font(Typography.data(13, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Space.sm)
                .disabled(checking)
        }
        .padding(.horizontal, Space.gutter)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 0.7)
                .offset(y: -120)
                .ignoresSafeArea()
        }
        .background(Palette.background.ignoresSafeArea())
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: error)
        .onAppear { focused = true }
    }

    private func join() {
        guard !trimmed.isEmpty, !checking else { return }
        checking = true
        Task {
            let problem = await env.auth.redeemInvite(trimmed)
            checking = false
            if let problem {
                error = problem
                Haptics.nudge()
            } else {
                Haptics.landed()
            }
        }
    }
}

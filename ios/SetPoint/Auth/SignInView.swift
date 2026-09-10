import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)

            VStack(alignment: .leading, spacing: Space.md) {
                Text("SetPoint")
                    .font(Typography.data(13, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkFaint)
                    .appearIn(0)

                Text("Eat enough. Stay on track.")
                    .font(Typography.display(32))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearIn(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.gutter)

            Spacer()

            VStack(spacing: Space.sm) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    Task { await env.auth.completeSignInWithApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                if APIConfig.allowDevSignIn {
                    Button("Developer sign-in") {
                        Task { await env.auth.developerSignIn() }
                    }
                    .font(Typography.data(14))
                    .foregroundStyle(Palette.inkSoft)
                }

                if let error = env.auth.lastError {
                    Text(error)
                        .font(Typography.data(13))
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.md)
            .overlay {
                if env.auth.signingIn { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }
}

struct SignInSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Space.xl)

            VStack(alignment: .leading, spacing: Space.md) {
                SkeletonBlock(width: 74, height: 11)
                VStack(alignment: .leading, spacing: Space.xs) {
                    SkeletonBlock(width: 286, height: 31, radius: 9)
                    SkeletonBlock(width: 252, height: 31, radius: 9)
                    SkeletonBlock(width: 198, height: 31, radius: 9)
                }
            }

            Spacer()

            VStack(spacing: Space.sm) {
                SkeletonBlock(height: 52, radius: Radius.md, tint: Palette.ink.opacity(0.12))
                SkeletonBlock(width: 126, height: 13)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, Space.md)
        }
        .padding(.horizontal, Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .skeletonLoading()
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment.preview())
}

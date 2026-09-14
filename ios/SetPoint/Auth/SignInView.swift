import AuthenticationServices
import SwiftUI

/// Sign in with Apple, as a sheet over the pitch. The consent line lives here —
/// continuing is agreeing.
struct SignInSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Let’s build your plan.")
                    .font(Typography.display(30))
                    .foregroundStyle(Palette.ink)
                Text("Continue with Apple to save it. No password.")
                    .font(Typography.data(16))
                    .foregroundStyle(Palette.inkSoft)
            }

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                Task { await env.auth.completeSignInWithApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                if env.auth.signingIn {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.ink)
                        .overlay(ProgressView().tint(.white))
                }
            }

            if APIConfig.allowDevSignIn {
                Button("Developer sign-in") {
                    Task { await env.auth.developerSignIn() }
                }
                .font(Typography.data(14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
            }

            if let error = env.auth.lastError {
                Text(error)
                    .font(Typography.data(13, weight: .semibold))
                    .foregroundStyle(Palette.accentDeep)
            }

            (
                Text("By continuing you agree to the ")
                    + Text("[Privacy Policy](\(APIConfig.baseURL.appending(path: "privacy").absoluteString))")
                    + Text(" and ")
                    + Text("[Terms](\(APIConfig.baseURL.appending(path: "terms").absoluteString))")
                    + Text(".")
            )
            .font(Typography.data(12))
            .tint(Palette.accent)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(APIConfig.allowDevSignIn ? 380 : 340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.background)
        .presentationCornerRadius(28)
    }
}

/// Shown while the session is being restored with no token on hand — the
/// pitch's terracotta, so launch doesn't flash a different screen.
struct SignInSkeletonView: View {
    var body: some View {
        Palette.accent
            .ignoresSafeArea()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) { SignInSheet() }
        .environment(AppEnvironment.preview())
}

import AuthenticationServices
import SwiftUI

/// Sign in with Apple, as a sheet over the pitch. The consent line lives here —
/// continuing is agreeing.
struct SignInSheet: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            FuelOrb(size: 72, glow: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text("Save your plan").sectionLabelStyle()
                Headline("One tap.", tail: "No password.", size: 36)
                Text("Your plan and history follow you to a new phone. Nothing is shared.")
                    .font(Typography.data(15, weight: .regular))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await env.auth.completeSignInWithApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 58)
            .clipShape(Capsule())
            .overlay {
                if env.auth.signingIn {
                    Capsule()
                        .fill(Palette.ink)
                        .overlay(BusyDots(tint: Palette.onBone))
                }
            }

            if APIConfig.allowDevSignIn {
                Button("Developer sign-in") {
                    Task { await env.auth.developerSignIn() }
                }
                .font(Typography.data(14, weight: .regular))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 36)
            }

            if let error = env.auth.lastError {
                Text(LocalizedStringKey(error))
                    .font(Typography.data(13, weight: .regular))
                    .foregroundStyle(Palette.danger)
            }

            (
                Text("By continuing you agree to the ")
                    + Text("[Privacy Policy](\(APIConfig.baseURL.appending(path: "privacy").absoluteString))")
                    + Text(" and ")
                    + Text("[Terms](\(APIConfig.baseURL.appending(path: "terms").absoluteString))")
                    + Text(". Health data never leaves your phone.")
            )
            .font(Typography.data(12, weight: .regular))
            .tint(Palette.ink)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            AmbientGlow(tone: .ember, strength: 0.8, height: 300).offset(y: -60)
        }
        .presentationDetents([.height(APIConfig.allowDevSignIn ? 520 : 480)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(32)
    }
}

/// Shown while the session is being restored with no token on hand — the
/// welcome's dark ground, so launch doesn't flash a different screen.
struct SignInSkeletonView: View {
    var body: some View {
        Palette.background
            .ignoresSafeArea()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) { SignInSheet() }
        .environment(AppEnvironment.preview())
}

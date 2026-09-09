import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("SetPoint")
                    .font(Typography.data(15, weight: .semibold))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.accent)

                Text("A manager for the one habit that's easy to skip: eating enough.")
                    .font(Typography.voice(27))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    Task { await env.auth.completeSignInWithApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .overlay {
                if env.auth.signingIn { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment.preview())
}

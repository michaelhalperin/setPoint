import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum Status: Equatable {
        case loading
        case signedOut
        case signedIn(userId: String)
    }

    private(set) var status: Status = .loading
    private(set) var signingIn = false
    var lastError: String?

    private let tokenStore: TokenStore
    private let baseURL: URL
    private let session: URLSession

    init(
        tokenStore: TokenStore,
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.baseURL = baseURL
        self.session = session
    }

    func bootstrap() {
        status = tokenStore.read() == nil ? .signedOut : .signedIn(userId: "")
    }

    func signOut() {
        tokenStore.clear()
        status = .signedOut
    }

    /// Called by the caller when any request comes back 401.
    func handleUnauthorized() {
        signOut()
    }

    func completeSignInWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = error.localizedDescription
        case let .success(auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                lastError = "Apple didn't return an identity token."
                return
            }
            await exchange(path: "/api/auth/apple", body: ["identityToken": identityToken])
        }
    }

    func developerSignIn() async {
        await exchange(path: "/api/auth/dev", body: [:])
    }

    private func exchange(path: String, body: [String: String]) async {
        signingIn = true
        lastError = nil
        defer { signingIn = false }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                lastError = message ?? "Sign-in failed."
                return
            }
            let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
            tokenStore.write(auth.token)
            status = .signedIn(userId: auth.userId)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

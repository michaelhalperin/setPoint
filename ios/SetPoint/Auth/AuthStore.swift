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
        /// Signed in, but sign-up is invite-only and this account needs a code.
        case needsInvite
    }

    private(set) var status: Status = .loading
    private(set) var signingIn = false
    var lastError: String?

    /// Posted by API clients that live outside `AppEnvironment` (e.g. the one
    /// HealthKit uses on a background launch) when the session is rejected.
    static let sessionExpired = Notification.Name("com.setpoint.app.sessionExpired")
    /// Posted when the API says this account still needs an invite code.
    static let inviteRequired = Notification.Name("com.setpoint.app.inviteRequired")

    private let tokenStore: TokenStore
    private let baseURL: URL
    private let session: URLSession
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?
    @ObservationIgnored private var inviteObserver: NSObjectProtocol?

    init(
        tokenStore: TokenStore,
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.baseURL = baseURL
        self.session = session
        expiryObserver = NotificationCenter.default.addObserver(
            forName: Self.sessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleUnauthorized() }
        }
        inviteObserver = NotificationCenter.default.addObserver(
            forName: Self.inviteRequired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tokenStore.read() != nil else { return }
                self.status = .needsInvite
            }
        }
    }

    var hasToken: Bool { tokenStore.read() != nil }

    func bootstrap() {
        status = tokenStore.read() == nil ? .signedOut : .signedIn(userId: "")
    }

    func signOut() {
        // Several requests can 401 at once — sign out only once.
        let sessionToken = tokenStore.read()
        guard sessionToken != nil || status != .signedOut else {
            AccountLocalState.clear()
            return
        }
        tokenStore.clear()
        status = .signedOut
        if let sessionToken {
            Task { await PushManager.shared.unregister(sessionToken: sessionToken) }
        }
        AccountLocalState.clear()
    }

    /// Called by the caller when any request comes back 401.
    func handleUnauthorized() {
        signOut()
    }

    func completeSignInWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = UserFacingError.message(for: error, fallback: L10n( "Sign-in failed."))
        case let .success(auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                lastError = "Sign-in failed."
                return
            }
            var body = [
                "identityToken": identityToken,
                "authorizationCode": String(data: credential.authorizationCode ?? Data(), encoding: .utf8) ?? "",
            ]
            if let name = Self.displayName(from: credential.fullName) {
                body["displayName"] = name
            }
            await exchange(path: "/api/auth/apple", body: body.filter { !$0.value.isEmpty })
        }
    }

    /// Redeems an invite code for the signed-in account. Nil on success (the
    /// session is swapped for a full one and the app opens); otherwise a line to show.
    func redeemInvite(_ code: String) async -> String? {
        guard let token = tokenStore.read() else {
            signOut()
            return nil
        }
        var request = URLRequest(url: baseURL.appending(path: "/api/auth/invite"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["code": code])
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200 ..< 300:
                let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
                tokenStore.write(auth.token)
                self.status = .signedIn(userId: auth.userId)
                return nil
            case 400:
                return L10n( "That code didn’t work. Check it and try again.")
            case 401:
                signOut()
                return nil
            case 429:
                return L10n( "Too many tries. Wait a minute, then try again.")
            default:
                return L10n( "Couldn’t check the code. Try again in a moment.")
            }
        } catch {
            return UserFacingError.message(for: error, fallback: L10n( "Couldn’t check the code. Try again in a moment."))
        }
    }

    private static let devUserKey = "com.setpoint.app.dev-user-id"

    /// Dev sign-in reuses the same dev user across launches so onboarding sticks.
    func developerSignIn() async {
        let stored = UserDefaults.standard.string(forKey: Self.devUserKey)
        let ok = await exchange(path: "/api/auth/dev", body: stored.map { ["userId": $0] } ?? [:])
        if !ok, stored != nil {
            UserDefaults.standard.removeObject(forKey: Self.devUserKey)
            _ = await exchange(path: "/api/auth/dev", body: [:])
        }
    }

    private static func displayName(from name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    @discardableResult
    private func exchange(path: String, body: [String: String]) async -> Bool {
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
                lastError = "Sign-in failed."
                return false
            }
            let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
            AccountLocalState.clear()
            tokenStore.write(auth.token)
            if path.hasSuffix("/dev") {
                UserDefaults.standard.set(auth.userId, forKey: Self.devUserKey)
            }
            status = auth.needsInvite == true ? .needsInvite : .signedIn(userId: auth.userId)
            return true
        } catch {
            lastError = UserFacingError.message(for: error, fallback: L10n( "Sign-in failed."))
            return false
        }
    }
}

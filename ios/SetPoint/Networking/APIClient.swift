import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case http(status: Int, message: String?)
    case decoding(Error)
    case transport(Error)

    /// Always a line a person can read — never a server or framework string.
    var errorDescription: String? {
        UserFacingError.message(for: self)
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}

/// Thin async/await JSON client. Attaches the bearer token from `tokenProvider`
/// on every request; maps 401 to `.unauthorized` so the UI can sign out.
///
/// The backend renews sessions: when a token is over a week old it returns a
/// fresh one in the `x-session-token` header, handed to `onTokenRefresh`.
actor APIClient {
    static let sessionRenewalHeader = "x-session-token"

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let onTokenRefresh: @Sendable (String) -> Void

    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String?,
        onTokenRefresh: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.onTokenRefresh = onTokenRefresh
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await perform(path, method: "GET", body: nil, query: query)
    }

    func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "POST", body: try Self.encoder.encode(body))
    }

    func post(_ path: String, _ body: some Encodable) async throws {
        let _: EmptyResponse = try await perform(path, method: "POST", body: try Self.encoder.encode(body))
    }

    /// POST with no request body.
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await perform(path, method: "POST", body: nil)
    }

    func post(_ path: String) async throws {
        let _: EmptyResponse = try await perform(path, method: "POST", body: nil)
    }

    func patch<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "PATCH", body: try Self.encoder.encode(body))
    }

    func delete<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "DELETE", body: try Self.encoder.encode(body))
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await perform(path, method: "DELETE", body: nil)
    }

    private func perform<T: Decodable>(_ path: String, method: String, body: Data?, query: [String: String] = [:]) async throws -> T {
        var url = baseURL.appending(path: path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let withQuery = components.url { url = withQuery }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200 ..< 300:
            if let renewed = http.value(forHTTPHeaderField: Self.sessionRenewalHeader), !renewed.isEmpty {
                onTokenRefresh(renewed)
            }
            if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
            do {
                return try Self.decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        case 401:
            throw APIError.unauthorized
        default:
            let parsed = try? Self.decoder.decode(APIErrorBody.self, from: data)
            throw APIError.http(status: http.statusCode, message: parsed?.message ?? parsed?.error)
        }
    }
}

struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case http(status: Int, message: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session expired. Sign in again."
        case let .http(status, message):
            return message ?? "The server returned an error (\(status))."
        case .decoding:
            return "The server sent something unexpected."
        case let .transport(error):
            return (error as? URLError)?.localizedDescription ?? "Couldn't reach the server."
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}

/// Thin async/await JSON client. Attaches the bearer token from `tokenProvider`
/// on every request; maps 401 to `.unauthorized` so the UI can sign out.
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?

    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(path, method: "GET", body: nil)
    }

    func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "POST", body: try Self.encoder.encode(body))
    }

    func post(_ path: String, _ body: some Encodable) async throws {
        let _: EmptyResponse = try await perform(path, method: "POST", body: try Self.encoder.encode(body))
    }

    func patch<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "PATCH", body: try Self.encoder.encode(body))
    }

    func delete<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await perform(path, method: "DELETE", body: try Self.encoder.encode(body))
    }

    private func perform<T: Decodable>(_ path: String, method: String, body: Data?) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

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

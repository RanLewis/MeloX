import Foundation

/// Melody 后端（lewis-dash 的 `/api/melody/**` 与 `/api/auth/**`）的传输层。
///
/// 后端把结果包在统一信封里：`{ code, message, data }`。`code` 是**业务码**，
/// 不是 HTTP 状态码 —— 所以这里必须先读 `code` 再看 HTTP 状态，反过来会把
/// 401 当成"请求成功但数据为空"。
@MainActor
final class MelodyClient {
    /// 编译期默认后端；设置里留空就用它。
    static let defaultServerURL = "https://dash.ranlewis.us.ci"

    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - 凭据

    var serverURLString: String {
        let raw = settings.melodyServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? Self.defaultServerURL : raw
    }

    /// 复用 `settings.cookie` 这一个槽位存放 Bearer 令牌：全工程已有大量
    /// "cookie 非空即已登录"的判断，换成新字段要同步改十几处调用点。
    var token: String {
        settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isLoggedIn: Bool { !token.isEmpty }

    /// 口令换令牌。令牌只在这一次响应里明文出现，服务端存的是摘要。
    @discardableResult
    func login(password: String) async throws -> String {
        let payload: LoginPayload = try await request(
            path: "/api/auth/login",
            method: "POST",
            body: ["password": password, "kind": "api", "label": "MeloX iOS"],
            authenticated: false
        )
        guard let issued = payload.token, !issued.isEmpty else {
            throw APIError.notLoggedIn
        }
        settings.cookie = issued
        return issued
    }

    /// 直接粘贴令牌登录。先验证再落盘，避免存下一枚用不了的令牌。
    @discardableResult
    func useToken(_ raw: String) async throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIError.notLoggedIn }
        let previous = settings.cookie
        settings.cookie = value
        do {
            let _: AccountEnvelope = try await request(
                path: "/api/melody/auth/nuser/account/get",
                method: "GET"
            )
            return value
        } catch {
            settings.cookie = previous
            throw error
        }
    }

    func signOut() {
        settings.cookie = ""
    }

    // MARK: - 请求

    func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await send(
            path: path,
            method: "GET",
            query: query
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(
        _ path: String,
        body: [String: Any]
    ) async throws -> T {
        let data = try await send(
            path: path,
            method: "POST",
            body: body
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 只关心成功与否的写接口。
    func postIgnoringPayload(
        _ path: String,
        body: [String: Any]
    ) async throws {
        _ = try await send(path: path, method: "POST", body: body)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await send(
            path: path,
            method: method,
            query: query,
            body: body,
            authenticated: authenticated
        )
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        guard var components = URLComponents(string: serverURLString),
              components.host != nil else {
            throw APIError.requestEncoding
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.requestEncoding
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue(
                "application/json; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        }
        if authenticated, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            signOut()
            throw APIError.notLoggedIn
        }

        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              !root.isEmpty else {
            throw APIError.emptyResponse(statusCode: status)
        }
        let code = Self.intValue(root["code"]) ?? status
        if code == 401 {
            signOut()
            throw APIError.notLoggedIn
        }
        guard (200..<300).contains(code) else {
            throw APIError.server(
                statusCode: code,
                message: root["message"] as? String
                    ?? L10n.string("ui.error.api.operation_incomplete")
            )
        }
        guard let payload = root["data"], !(payload is NSNull) else {
            return Data("{}".utf8)
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private struct LoginPayload: Decodable {
        let token: String?
    }
}

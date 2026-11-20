import Foundation

actor SupabaseAuthClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case server(code: String?, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "auth.error.connection")
            case .server(let code, let message):
                switch code {
                case "invalid_credentials":
                    return String(localized: "auth.error.credentials")
                case "user_already_exists", "email_exists":
                    return String(localized: "auth.error.emailExists")
                case "email_not_confirmed":
                    return String(localized: "auth.error.emailNotConfirmed")
                case "over_email_send_rate_limit", "over_request_rate_limit",
                     "email_rate_limit_exceeded", "email_send_rate_limit_exceeded":
                    return String(localized: "auth.error.rateLimit")
                default:
                    if message.localizedCaseInsensitiveContains("rate limit") {
                        return String(localized: "auth.error.rateLimit")
                    }
                    return message.isEmpty ? String(localized: "auth.error.generic") : message
                }
            }
        }
    }

    struct APIError: Decodable {
        let code: String?
        let message: String?
        let errorCode: String?
        let errorDescription: String?
        let msg: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case errorCode = "error_code"
            case errorDescription = "error_description"
            case msg
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // GoTrue responses are not fully consistent across endpoints: the
            // `code` field may be either a textual error code or an HTTP number.
            // Decode every field independently so one differently typed value
            // does not hide a useful `error_code` or message from the UI.
            let textCode = try? container.decode(String.self, forKey: .code)
            let numericCode = try? container.decode(Int.self, forKey: .code)
            code = textCode ?? numericCode.map(String.init)
            message = try? container.decode(String.self, forKey: .message)
            errorCode = try? container.decode(String.self, forKey: .errorCode)
            errorDescription = try? container.decode(String.self, forKey: .errorDescription)
            msg = try? container.decode(String.self, forKey: .msg)
        }
    }

    private struct ProgressPayload: Encodable {
        let id: UUID
        let username: String
        let xp: Int
        let streakDays: Int
        let lessonsCompleted: Int
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, username, xp
            case streakDays = "streak_days"
            case lessonsCompleted = "lessons_completed"
            case updatedAt = "updated_at"
        }
    }

    private struct LeagueSyncPayload: Encodable {
        let username: String
        let xp: Int
        let streakDays: Int
        let lessonsCompleted: Int

        enum CodingKeys: String, CodingKey {
            case username = "p_username"
            case xp = "p_xp"
            case streakDays = "p_streak_days"
            case lessonsCompleted = "p_lessons_completed"
        }
    }

    private struct LessonProgressSyncPayload: Encodable {
        let rows: [LessonProgressSyncRow]

        enum CodingKeys: String, CodingKey {
            case rows = "p_rows"
        }
    }

    private struct LessonProgressSyncRow: Encodable {
        let lessonKey: String
        let bestAccuracy: Double
        let completedAt: String

        enum CodingKeys: String, CodingKey {
            case lessonKey = "lesson_key"
            case bestAccuracy = "best_accuracy"
            case completedAt = "completed_at"
        }
    }

    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func signUp(email: String, password: String, username: String) async throws -> (AuthUser, AuthSession?) {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "data": ["username": username]
        ]
        let redirect = AuthCallback.redirectURLString.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? AuthCallback.redirectURLString
        let data = try await send(
            path: "auth/v1/signup?redirect_to=\(redirect)",
            method: "POST",
            json: body
        )
        let response = try decoder.decode(SupabaseAuthResponse.self, from: data)
        return (response.user, response.session)
    }

    func session(fromCallbackURL url: URL) async throws -> AuthSession {
        guard let tokens = AuthCallback.tokens(from: url) else {
            throw ClientError.invalidResponse
        }

        let data = try await send(
            path: "auth/v1/user",
            method: "GET",
            bearerToken: tokens.accessToken
        )
        let user = try decoder.decode(AuthUser.self, from: data)
        return AuthSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(tokens.expiresIn),
            user: user
        )
    }

    func requestPasswordReset(email: String) async throws {
        let redirect = AuthCallback.redirectURLString.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? AuthCallback.redirectURLString
        _ = try await send(
            path: "auth/v1/recover?redirect_to=\(redirect)",
            method: "POST",
            json: ["email": email]
        )
    }

    func updatePassword(_ password: String, accessToken: String) async throws -> AuthUser {
        let data = try await send(
            path: "auth/v1/user",
            method: "PUT",
            json: ["password": password],
            bearerToken: accessToken
        )
        return try decoder.decode(AuthUser.self, from: data)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await send(
            path: "auth/v1/token?grant_type=password",
            method: "POST",
            json: body
        )
        let response = try decoder.decode(SupabaseAuthResponse.self, from: data)
        guard let session = response.session else { throw ClientError.invalidResponse }
        return session
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let data = try await send(
            path: "auth/v1/token?grant_type=refresh_token",
            method: "POST",
            json: ["refresh_token": refreshToken]
        )
        let response = try decoder.decode(SupabaseAuthResponse.self, from: data)
        guard let session = response.session else { throw ClientError.invalidResponse }
        return session
    }

    func signOut(accessToken: String) async throws {
        _ = try await send(
            path: "auth/v1/logout",
            method: "POST",
            bearerToken: accessToken
        )
    }

    func upsert(progress: CloudProgress, session authSession: AuthSession) async throws {
        let leaguePayload = LeagueSyncPayload(
            username: progress.username,
            xp: max(0, progress.xp),
            streakDays: max(0, progress.streakDays),
            lessonsCompleted: max(0, progress.lessonsCompleted)
        )

        do {
            _ = try await send(
                path: "rest/v1/rpc/sync_progress_and_league",
                method: "POST",
                body: try encoder.encode(leaguePayload),
                bearerToken: authSession.accessToken
            )
            return
        } catch ClientError.server(let code, _) where code == "PGRST202" || code == "42883" {
            // The app can be updated before the optional Supabase migration.
            // Keep profile sync working until the league RPC is installed.
        }

        let payload = ProgressPayload(
            id: authSession.user.id,
            username: progress.username,
            xp: max(0, progress.xp),
            streakDays: max(0, progress.streakDays),
            lessonsCompleted: max(0, progress.lessonsCompleted),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let body = try encoder.encode(payload)
        _ = try await send(
            path: "rest/v1/profiles?on_conflict=id",
            method: "POST",
            body: body,
            bearerToken: authSession.accessToken,
            additionalHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    /// Row shape of `public.profiles` used by both upload and download.
    struct ProfileRow: Decodable, Equatable {
        let username: String
        let xp: Int
        let streakDays: Int
        let lessonsCompleted: Int

        enum CodingKeys: String, CodingKey {
            case username, xp
            case streakDays = "streak_days"
            case lessonsCompleted = "lessons_completed"
        }

        var progress: CloudProgress {
            CloudProgress(
                username: username,
                xp: xp,
                streakDays: streakDays,
                lessonsCompleted: lessonsCompleted
            )
        }
    }

    func fetchProgress(
        userID: UUID,
        bearerToken: String
    ) async throws -> CloudProgress? {
        let data = try await send(
            path: "rest/v1/profiles?id=eq.\(userID.uuidString)&select=username,xp,streak_days,lessons_completed&limit=1",
            method: "GET",
            bearerToken: bearerToken
        )
        let rows = try decoder.decode([ProfileRow].self, from: data)
        return rows.first?.progress
    }

    struct LessonProgressRow: Decodable, Equatable {
        let lessonKey: String
        let bestAccuracy: Double
        let completedAt: String

        enum CodingKeys: String, CodingKey {
            case lessonKey = "lesson_key"
            case bestAccuracy = "best_accuracy"
            case completedAt = "completed_at"
        }

        var progress: CloudLessonProgress? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let regular = ISO8601DateFormatter()
            regular.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: completedAt) ?? regular.date(from: completedAt) else {
                return nil
            }
            return CloudLessonProgress(
                lessonKey: lessonKey,
                bestAccuracy: bestAccuracy,
                completedAt: date
            )
        }
    }

    func fetchLessonProgress(
        userID: UUID,
        bearerToken: String
    ) async throws -> [CloudLessonProgress] {
        let data = try await send(
            path: "rest/v1/user_lesson_progress?user_id=eq.\(userID.uuidString)&select=lesson_key,best_accuracy,completed_at&order=lesson_key.asc",
            method: "GET",
            bearerToken: bearerToken
        )
        return try decoder.decode([LessonProgressRow].self, from: data).compactMap(\.progress)
    }

    func syncLessonProgress(
        _ rows: [CloudLessonProgress],
        session authSession: AuthSession
    ) async throws {
        guard !rows.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let payload = LessonProgressSyncPayload(
            rows: rows.map {
                LessonProgressSyncRow(
                    lessonKey: $0.lessonKey,
                    bestAccuracy: min(1, max(0, $0.bestAccuracy)),
                    completedAt: formatter.string(from: $0.completedAt)
                )
            }
        )
        _ = try await send(
            path: "rest/v1/rpc/sync_my_lesson_progress",
            method: "POST",
            body: try encoder.encode(payload),
            bearerToken: authSession.accessToken
        )
    }

    func fetchLeaderboard(
        limit: Int = 30,
        bearerToken: String
    ) async throws -> [LeaderboardEntry] {
        let data = try await send(
            path: "rest/v1/profiles?select=id,username,xp,streak_days&order=xp.desc,id.asc&limit=\(limit)",
            method: "GET",
            bearerToken: bearerToken
        )
        return try decoder.decode([LeaderboardEntry].self, from: data)
    }

    func fetchLeagueLeaderboard(bearerToken: String) async throws -> LeagueLeaderboard? {
        let data = try await send(
            path: "rest/v1/rpc/get_my_leaderboard",
            method: "POST",
            body: Data("{}".utf8),
            bearerToken: bearerToken
        )
        let rows = try decoder.decode([LeagueLeaderboardRow].self, from: data)
        return LeagueLeaderboard(rows: rows)
    }

    private func send(
        path: String,
        method: String,
        json: [String: Any]? = nil,
        body: Data? = nil,
        bearerToken: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: configuration.projectURL)?.absoluteURL else {
            throw ClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else {
            request.httpBody = body
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.invalidResponse
        }

        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIError.self, from: data)
            throw ClientError.server(
                code: payload?.errorCode ?? payload?.code,
                message: payload?.message
                    ?? payload?.errorDescription
                    ?? payload?.msg
                    ?? String(localized: "auth.error.generic")
            )
        }
        return data
    }
}

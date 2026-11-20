import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: UUID
    let email: String
    let username: String

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }

    private enum MetadataKeys: String, CodingKey {
        case username
    }

    init(id: UUID, email: String, username: String) {
        self.id = id
        self.email = email
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""

        if let metadata = try? container.nestedContainer(
            keyedBy: MetadataKeys.self,
            forKey: .userMetadata
        ) {
            username = try metadata.decodeIfPresent(String.self, forKey: .username) ?? ""
        } else {
            username = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        var metadata = container.nestedContainer(
            keyedBy: MetadataKeys.self,
            forKey: .userMetadata
        )
        try metadata.encode(username, forKey: .username)
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

struct AuthCallbackTokens: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let type: String?
}

enum AuthCallback {
    static let redirectURLString = "miko://auth/callback"

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "miko"
            && url.host?.lowercased() == "auth"
            && url.path == "/callback"
    }

    static func tokens(from url: URL) -> AuthCallbackTokens? {
        guard matches(url) else { return nil }

        var queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = url.fragment,
           let fragmentItems = URLComponents(string: "?\(fragment)")?.queryItems {
            queryItems.append(contentsOf: fragmentItems)
        }

        func value(named name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let accessToken = value(named: "access_token"), !accessToken.isEmpty,
              let refreshToken = value(named: "refresh_token"), !refreshToken.isEmpty else {
            return nil
        }

        return AuthCallbackTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: TimeInterval(value(named: "expires_in") ?? "") ?? 3_600,
            type: value(named: "type")
        )
    }
}

struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: AuthUser

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresIn)

        // GoTrue returns a direct user for email-confirmation sign-ups and a
        // nested user for session responses such as password sign-in.
        if let nestedUser = try container.decodeIfPresent(AuthUser.self, forKey: .user) {
            user = nestedUser
        } else {
            user = try AuthUser(from: decoder)
        }
    }

    var session: AuthSession? {
        guard let accessToken, let refreshToken else { return nil }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn ?? 3_600),
            user: user
        )
    }
}

struct CloudProgress: Equatable, Sendable {
    let username: String
    let xp: Int
    let streakDays: Int
    let lessonsCompleted: Int
}

/// Completed lesson state shared across installs. `lessonKey` is the bundled
/// content key (for example `a1.u1.l1`), never the per-install SwiftData UUID.
struct CloudLessonProgress: Equatable, Sendable {
    let lessonKey: String
    let bestAccuracy: Double
    let completedAt: Date
}

/// Ordered competitive tiers used by the weekly leaderboard. The raw values
/// are shared with the Supabase migration and must remain stable.
enum LeagueTier: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case bronze
    case silver
    case gold
    case turquoise
    case sapphire
    case ruby
    case obsidian

    var id: String { rawValue }

    var promoted: LeagueTier {
        switch self {
        case .bronze: .silver
        case .silver: .gold
        case .gold: .turquoise
        case .turquoise: .sapphire
        case .sapphire: .ruby
        case .ruby, .obsidian: .obsidian
        }
    }

    var demoted: LeagueTier {
        switch self {
        case .bronze, .silver: .bronze
        case .gold: .silver
        case .turquoise: .gold
        case .sapphire: .turquoise
        case .ruby: .sapphire
        case .obsidian: .ruby
        }
    }
}

struct LeagueLeaderboardEntry: Equatable, Sendable, Identifiable {
    let id: UUID
    let username: String
    let weeklyXP: Int
    let streakDays: Int
    let position: Int
}

enum LeagueScorePeriod: Equatable, Sendable {
    case weekly
    case lifetimeFallback
}

/// Immutable result returned by the weekly leaderboard RPC.
struct LeagueLeaderboard: Equatable, Sendable {
    let league: LeagueTier
    let groupNumber: Int
    let seasonStartsAt: Date
    let seasonEndsAt: Date
    let promotionCount: Int
    let demotionStart: Int?
    let entries: [LeagueLeaderboardEntry]
    let scorePeriod: LeagueScorePeriod

    init?(rows: [LeagueLeaderboardRow]) {
        guard let first = rows.first,
              let league = LeagueTier(rawValue: first.leagueKey),
              let startsAt = Self.parseISO8601(first.seasonStartsAt),
              let endsAt = Self.parseISO8601(first.seasonEndsAt) else {
            return nil
        }
        self.league = league
        groupNumber = first.groupNumber
        seasonStartsAt = startsAt
        seasonEndsAt = endsAt
        promotionCount = max(0, first.promotionCount)
        demotionStart = first.demotionStart
        scorePeriod = .weekly
        entries = rows
            .map {
                LeagueLeaderboardEntry(
                    id: $0.id,
                    username: $0.username,
                    weeklyXP: max(0, $0.weeklyXP),
                    streakDays: max(0, $0.streakDays),
                    position: max(1, $0.position)
                )
            }
            .sorted { $0.position < $1.position }
    }

    /// Compatibility snapshot for projects where the weekly-league migration
    /// has not been deployed yet. Every row still comes from Supabase; only the
    /// score period changes from weekly XP to the profile's lifetime XP.
    init(lifetimeEntries: [LeaderboardEntry], now: Date = Date()) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startsAt = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        league = .turquoise
        groupNumber = 1
        seasonStartsAt = startsAt
        seasonEndsAt = calendar.date(byAdding: .day, value: 7, to: startsAt) ?? now
        promotionCount = 0
        demotionStart = nil
        scorePeriod = .lifetimeFallback
        entries = lifetimeEntries.enumerated().map { index, entry in
            LeagueLeaderboardEntry(
                id: entry.id,
                username: entry.username,
                weeklyXP: max(0, entry.xp),
                streakDays: max(0, entry.streakDays),
                position: index + 1
            )
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

/// Wire format returned by `get_my_leaderboard`.
struct LeagueLeaderboardRow: Decodable, Equatable, Sendable {
    let id: UUID
    let username: String
    let weeklyXP: Int
    let streakDays: Int
    let leagueKey: String
    let groupNumber: Int
    let position: Int
    let seasonStartsAt: String
    let seasonEndsAt: String
    let promotionCount: Int
    let demotionStart: Int?

    private enum CodingKeys: String, CodingKey {
        case id, username, position
        case weeklyXP = "weekly_xp"
        case streakDays = "streak_days"
        case leagueKey = "league_key"
        case groupNumber = "group_number"
        case seasonStartsAt = "season_starts_at"
        case seasonEndsAt = "season_ends_at"
        case promotionCount = "promotion_count"
        case demotionStart = "demotion_start"
    }
}

/// One row of the shared leaderboard, read from the `profiles` table.
struct LeaderboardEntry: Decodable, Equatable, Sendable, Identifiable {
    let id: UUID
    let username: String
    let xp: Int
    let streakDays: Int

    private enum CodingKeys: String, CodingKey {
        case id, username, xp
        case streakDays = "streak_days"
    }
}

enum AuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }
}

enum AuthValidation {
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validateEmail(_ email: String) -> String? {
        let cleanEmail = normalizedEmail(email)
        let emailParts = cleanEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard emailParts.count == 2, !emailParts[0].isEmpty, emailParts[1].contains(".") else {
            return String(localized: "auth.error.invalidEmail")
        }
        return nil
    }

    static func validate(
        mode: AuthMode,
        username: String,
        email: String,
        password: String
    ) -> String? {
        if let emailError = validateEmail(email) { return emailError }

        if mode == .signUp {
            let cleanUsername = normalizedUsername(username)
            guard (2...30).contains(cleanUsername.count) else {
                return String(localized: "auth.error.invalidUsername")
            }
        }

        guard password.count >= 8 else {
            return String(localized: "auth.error.shortPassword")
        }
        return nil
    }
}

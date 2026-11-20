import Foundation
import Testing
@testable import Miko

/// Tests for the shared leaderboard: request construction against a stubbed
/// URL protocol and decoding of PostgREST `profiles` responses.
@Suite(.serialized)
struct LeaderboardDecodingTests {

    @Test func leagueTierMovementStopsAtBounds() {
        #expect(LeagueTier.bronze.demoted == .bronze)
        #expect(LeagueTier.bronze.promoted == .silver)
        #expect(LeagueTier.gold.promoted == .turquoise)
        #expect(LeagueTier.turquoise.demoted == .gold)
        #expect(LeagueTier.ruby.promoted == .obsidian)
        #expect(LeagueTier.obsidian.promoted == .obsidian)
    }

    @Test func decodesWeeklyLeagueSnapshot() throws {
        let json = """
        [
          {
            "id": "3F7A2C1E-9B4D-4E8A-A1C2-5D6E7F8A9B0C",
            "username": "Ayşe",
            "weekly_xp": 420,
            "streak_days": 14,
            "league_key": "turquoise",
            "group_number": 2,
            "position": 1,
            "season_starts_at": "2026-08-24T00:00:00+00:00",
            "season_ends_at": "2026-08-31T00:00:00+00:00",
            "promotion_count": 5,
            "demotion_start": 18
          },
          {
            "id": "11111111-2222-3333-4444-555555555555",
            "username": "Mehmet",
            "weekly_xp": 180,
            "streak_days": 2,
            "league_key": "turquoise",
            "group_number": 2,
            "position": 2,
            "season_starts_at": "2026-08-24T00:00:00+00:00",
            "season_ends_at": "2026-08-31T00:00:00+00:00",
            "promotion_count": 5,
            "demotion_start": 18
          }
        ]
        """
        let rows = try JSONDecoder().decode([LeagueLeaderboardRow].self, from: Data(json.utf8))
        let snapshot = try #require(LeagueLeaderboard(rows: rows))

        #expect(snapshot.league == .turquoise)
        #expect(snapshot.groupNumber == 2)
        #expect(snapshot.promotionCount == 5)
        #expect(snapshot.demotionStart == 18)
        #expect(snapshot.entries.map(\.weeklyXP) == [420, 180])
    }

    @Test func decodesSnakeCaseEntries() throws {
        let json = """
        [
          {
            "id": "3F7A2C1E-9B4D-4E8A-A1C2-5D6E7F8A9B0C",
            "username": "Ayşe",
            "xp": 1250,
            "streak_days": 14
          },
          {
            "id": "11111111-2222-3333-4444-555555555555",
            "username": "Mehmet",
            "xp": 0,
            "streak_days": 0
          }
        ]
        """
        let entries = try JSONDecoder().decode([LeaderboardEntry].self, from: Data(json.utf8))

        #expect(entries.count == 2)
        #expect(entries[0].username == "Ayşe")
        #expect(entries[0].xp == 1250)
        #expect(entries[0].streakDays == 14)
        #expect(entries[1].xp == 0)
    }

    @Test func buildsRealLifetimeFallbackWithoutInventingPlayers() throws {
        let json = """
        [
          {
            "id": "3F7A2C1E-9B4D-4E8A-A1C2-5D6E7F8A9B0C",
            "username": "Ayşe",
            "xp": 1250,
            "streak_days": 14
          },
          {
            "id": "11111111-2222-3333-4444-555555555555",
            "username": "Mehmet",
            "xp": 800,
            "streak_days": 2
          }
        ]
        """
        let realProfiles = try JSONDecoder().decode([LeaderboardEntry].self, from: Data(json.utf8))
        let snapshot = LeagueLeaderboard(lifetimeEntries: realProfiles)

        #expect(snapshot.scorePeriod == .lifetimeFallback)
        #expect(snapshot.entries.map(\.username) == ["Ayşe", "Mehmet"])
        #expect(snapshot.entries.map(\.weeklyXP) == [1250, 800])
        #expect(snapshot.entries.map(\.position) == [1, 2])
        #expect(snapshot.promotionCount == 0)
        #expect(snapshot.demotionStart == nil)
    }

    @Test func fetchUsesProfilesEndpointAndAuthHeader() async throws {
        let recorder = RequestRecorder()
        let config = URLProtocolConfiguration(recorder: recorder)
        StubURLProtocol.configuration = config
        let session = URLSession(configuration: config.sessionConfiguration)

        let payload = """
        [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","username":"Zeynep","xp":900,"streak_days":6}]
        """
        let client = SupabaseAuthClient(
            configuration: SupabaseConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "test-key"
            ),
            session: session
        )
        let stub = StubResponse(
            status: 200,
            body: payload,
            host: "example.supabase.co"
        )
        config.stub = stub

        let entries = try await client.fetchLeaderboard(limit: 10, bearerToken: "token-123")

        #expect(entries.count == 1)
        #expect(entries[0].username == "Zeynep")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/rest/v1/profiles")
        #expect(request.httpMethod == "GET")
        #expect(request.url?.query?.contains("order=xp.desc") == true)
        #expect(request.url?.query?.contains("limit=10") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "apikey") == "test-key")
    }

    @Test func weeklyFetchUsesAuthenticatedRPC() async throws {
        let recorder = RequestRecorder()
        let config = URLProtocolConfiguration(recorder: recorder)
        StubURLProtocol.configuration = config
        let session = URLSession(configuration: config.sessionConfiguration)
        config.stub = StubResponse(
            status: 200,
            body: """
            [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","username":"Zeynep","weekly_xp":90,"streak_days":6,"league_key":"bronze","group_number":1,"position":1,"season_starts_at":"2026-08-24T00:00:00+00:00","season_ends_at":"2026-08-31T00:00:00+00:00","promotion_count":1,"demotion_start":null}]
            """,
            host: "example.supabase.co"
        )
        let client = SupabaseAuthClient(
            configuration: SupabaseConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "test-key"
            ),
            session: session
        )

        let board = try await client.fetchLeagueLeaderboard(bearerToken: "token-123")

        #expect(board?.league == .bronze)
        #expect(board?.entries.first?.weeklyXP == 90)
        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/rest/v1/rpc/get_my_leaderboard")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
    }

    @Test func progressSyncCreditsWeeklyLeagueThroughRPC() async throws {
        let recorder = RequestRecorder()
        let config = URLProtocolConfiguration(recorder: recorder)
        StubURLProtocol.configuration = config
        let session = URLSession(configuration: config.sessionConfiguration)
        config.stub = StubResponse(status: 204, body: "", host: "example.supabase.co")
        let client = SupabaseAuthClient(
            configuration: SupabaseConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "test-key"
            ),
            session: session
        )
        let user = AuthUser(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            email: "z@example.com",
            username: "Zeynep"
        )
        let authSession = AuthSession(
            accessToken: "token-123",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            user: user
        )

        try await client.upsert(
            progress: CloudProgress(
                username: "Zeynep",
                xp: 430,
                streakDays: 6,
                lessonsCompleted: 8
            ),
            session: authSession
        )

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/rest/v1/rpc/sync_progress_and_league")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
    }

    @Test func serverErrorYieldsNilFromStore() {
        // AuthStore.loadLeaderboard maps any thrown error to nil; the mapping
        // itself is covered by ClientError handling in auth tests. Here we pin
        // that decoding a PostgREST error object fails loudly instead of
        // producing garbage entries.
        let json = """
        {"code":"42501","message":"permission denied","hint":null,"details":null}
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([LeaderboardEntry].self, from: Data(json.utf8))
        }
    }
}

// MARK: - Stubbing

private final class RequestRecorder: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    func append(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }
}

private struct StubResponse {
    let status: Int
    let body: String
    let host: String
}

private final class URLProtocolConfiguration: @unchecked Sendable {
    let recorder: RequestRecorder
    var stub: StubResponse?

    init(recorder: RequestRecorder) {
        self.recorder = recorder
    }

    var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}

private final class StubURLProtocol: URLProtocol {
    // Test-only stubbing: the configuration is installed for the duration of
    // one request on a dedicated ephemeral session, so unsynchronized access
    // is contained to a single test.
    nonisolated(unsafe) static var configuration: URLProtocolConfiguration?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let configuration = Self.configuration else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        configuration.recorder.append(request)

        guard let stub = configuration.stub,
              request.url?.host == stub.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

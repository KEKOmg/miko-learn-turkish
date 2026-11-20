import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case unconfigured
        case loading
        case signedOut
        case signedIn(AuthUser)
        case confirmationRequired(String)
        case passwordRecoverySent(String)
        case passwordResetRequired(String)
    }

    private(set) var state: State
    private(set) var errorMessage: String?
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?

    private let client: SupabaseAuthClient?
    private let sessionStore: any AuthSessionStoring
    private var session: AuthSession?

    init(
        configuration: SupabaseConfiguration?,
        sessionStore: any AuthSessionStoring = KeychainSessionStore()
    ) {
        client = configuration.map { SupabaseAuthClient(configuration: $0) }
        self.sessionStore = sessionStore
        state = configuration == nil ? .unconfigured : .loading
    }

    var user: AuthUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isConfigured: Bool { client != nil }

    func restoreSession() async {
        guard let client else {
            state = .unconfigured
            return
        }

        do {
            guard var restored = try sessionStore.load() else {
                state = .signedOut
                return
            }
            if restored.needsRefresh {
                restored = try await client.refresh(restored.refreshToken)
                try sessionStore.save(restored)
            }
            session = restored
            state = .signedIn(restored.user)
        } catch {
            try? sessionStore.clear()
            session = nil
            state = .signedOut
        }
    }

    @discardableResult
    func handleAuthCallback(_ url: URL) async -> Bool {
        guard AuthCallback.matches(url) else { return false }

        errorMessage = nil
        guard let client else {
            state = .unconfigured
            errorMessage = String(localized: "auth.error.notConfigured")
            return false
        }

        state = .loading
        do {
            let isPasswordRecovery = AuthCallback.tokens(from: url)?.type == "recovery"
            let newSession = try await client.session(fromCallbackURL: url)
            if isPasswordRecovery {
                session = newSession
                state = .passwordResetRequired(newSession.user.email)
            } else {
                try save(newSession)
            }
            return true
        } catch {
            session = nil
            state = .signedOut
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        errorMessage = nil
        guard let client else {
            errorMessage = String(localized: "auth.error.notConfigured")
            return false
        }
        if let validationError = AuthValidation.validateEmail(email) {
            errorMessage = validationError
            return false
        }

        let cleanEmail = AuthValidation.normalizedEmail(email)
        state = .loading
        do {
            try await client.requestPasswordReset(email: cleanEmail)
            state = .passwordRecoverySent(cleanEmail)
            return true
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updatePassword(_ password: String, confirmation: String) async -> Bool {
        errorMessage = nil
        guard password.count >= 8 else {
            errorMessage = String(localized: "auth.error.shortPassword")
            return false
        }
        guard password == confirmation else {
            errorMessage = String(localized: "auth.error.passwordMismatch")
            return false
        }
        guard let client, let activeSession = session else {
            state = client == nil ? .unconfigured : .signedOut
            errorMessage = String(localized: "auth.error.recoveryExpired")
            return false
        }

        state = .loading
        do {
            let user = try await client.updatePassword(
                password,
                accessToken: activeSession.accessToken
            )
            let updatedSession = AuthSession(
                accessToken: activeSession.accessToken,
                refreshToken: activeSession.refreshToken,
                expiresAt: activeSession.expiresAt,
                user: user
            )
            try save(updatedSession)
            return true
        } catch {
            state = .passwordResetRequired(activeSession.user.email)
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelPasswordReset() {
        session = nil
        try? sessionStore.clear()
        errorMessage = nil
        state = client == nil ? .unconfigured : .signedOut
    }

    func submit(mode: AuthMode, username: String, email: String, password: String) async -> Bool {
        errorMessage = nil
        guard let client else {
            errorMessage = String(localized: "auth.error.notConfigured")
            return false
        }

        if let validationError = AuthValidation.validate(
            mode: mode,
            username: username,
            email: email,
            password: password
        ) {
            errorMessage = validationError
            return false
        }

        state = .loading
        let cleanEmail = AuthValidation.normalizedEmail(email)
        do {
            switch mode {
            case .signIn:
                let newSession = try await client.signIn(email: cleanEmail, password: password)
                try save(newSession)
                return true

            case .signUp:
                let cleanUsername = AuthValidation.normalizedUsername(username)
                let result = try await client.signUp(
                    email: cleanEmail,
                    password: password,
                    username: cleanUsername
                )
                if let newSession = result.1 {
                    try save(newSession)
                    return true
                }
                state = .confirmationRequired(cleanEmail)
                return true
            }
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        let oldSession = session
        session = nil
        try? sessionStore.clear()
        state = client == nil ? .unconfigured : .signedOut
        lastSyncDate = nil

        if let oldSession, let client {
            try? await client.signOut(accessToken: oldSession.accessToken)
        }
    }

    func sync(progress: CloudProgress, ownerUserID: UUID) async {
        guard let client, var activeSession = session else { return }
        guard activeSession.user.id == ownerUserID else {
            errorMessage = String(localized: "auth.sync.failed")
            return
        }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return }
                try save(activeSession)
            }
            try await client.upsert(progress: progress, session: activeSession)
            guard session?.user.id == ownerUserID else { return }
            lastSyncDate = Date()
        } catch {
            errorMessage = String(localized: "auth.sync.failed")
        }
    }

    func syncLessonProgress(
        _ rows: [CloudLessonProgress],
        ownerUserID: UUID
    ) async {
        guard let client, var activeSession = session else { return }
        guard activeSession.user.id == ownerUserID else {
            errorMessage = String(localized: "auth.sync.failed")
            return
        }
        guard !rows.isEmpty else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return }
                try save(activeSession)
            }
            try await client.syncLessonProgress(rows, session: activeSession)
            guard session?.user.id == ownerUserID else { return }
            lastSyncDate = Date()
        } catch {
            errorMessage = String(localized: "auth.sync.failed")
        }
    }

    /// Fetches the shared leaderboard. Returns `nil` when the user is signed
    /// out, Supabase is not configured, or the request fails, letting the UI
    /// fall back to its offline experience.
    func loadLeaderboard(limit: Int = 30) async -> [LeaderboardEntry]? {
        guard let client, var activeSession = session else { return nil }
        let ownerUserID = activeSession.user.id
        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return nil }
                try save(activeSession)
            }
            let entries = try await client.fetchLeaderboard(
                limit: limit,
                bearerToken: activeSession.accessToken
            )
            guard session?.user.id == ownerUserID else { return nil }
            return entries
        } catch {
            return nil
        }
    }

    /// Loads the caller's active weekly league group. Until the weekly RPC is
    /// deployed, the existing shared profiles leaderboard provides a real-data
    /// lifetime-XP fallback instead of leaving the ranking screen empty.
    func loadWeeklyLeague() async -> LeagueLeaderboard? {
        guard let client, var activeSession = session else { return nil }
        let ownerUserID = activeSession.user.id
        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return nil }
                try save(activeSession)
            }
            if let weekly = try await client.fetchLeagueLeaderboard(
                bearerToken: activeSession.accessToken
            ) {
                guard session?.user.id == ownerUserID else { return nil }
                return weekly
            }
        } catch {
            // The deployed Supabase project may not have the optional weekly
            // RPC yet. The authenticated profiles endpoint remains available.
        }

        guard session?.user.id == ownerUserID else { return nil }
        do {
            let entries = try await client.fetchLeaderboard(
                limit: 1_000,
                bearerToken: activeSession.accessToken
            )
            guard session?.user.id == ownerUserID, !entries.isEmpty else { return nil }
            return LeagueLeaderboard(lifetimeEntries: entries)
        } catch {
            return nil
        }
    }

    /// Downloads the signed-in user's profile row. Returns `nil` when signed
    /// out, unconfigured, the row does not exist yet, or the request fails.
    func fetchCloudProgress(ownerUserID: UUID) async -> CloudProgress? {
        guard let client, var activeSession = session else { return nil }
        guard activeSession.user.id == ownerUserID else { return nil }
        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return nil }
                try save(activeSession)
            }
            let progress = try await client.fetchProgress(
                userID: ownerUserID,
                bearerToken: activeSession.accessToken
            )
            guard session?.user.id == ownerUserID else { return nil }
            return progress
        } catch {
            return nil
        }
    }

    /// Downloads only the signed-in account's completed lesson rows. `nil`
    /// means the request failed; an empty array is a successful empty state.
    func fetchCloudLessonProgress(ownerUserID: UUID) async -> [CloudLessonProgress]? {
        guard let client, var activeSession = session else { return nil }
        guard activeSession.user.id == ownerUserID else { return nil }
        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(activeSession.refreshToken)
                guard session?.user.id == ownerUserID else { return nil }
                try save(activeSession)
            }
            let rows = try await client.fetchLessonProgress(
                userID: ownerUserID,
                bearerToken: activeSession.accessToken
            )
            guard session?.user.id == ownerUserID else { return nil }
            return rows
        } catch {
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func returnToSignIn() {
        errorMessage = nil
        state = client == nil ? .unconfigured : .signedOut
    }

    private func save(_ newSession: AuthSession) throws {
        try sessionStore.save(newSession)
        session = newSession
        state = .signedIn(newSession.user)
    }
}

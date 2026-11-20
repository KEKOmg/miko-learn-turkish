import Foundation
import SwiftData

/// Creates the user's profile and related entities on first launch.
/// Idempotent — safe to call multiple times.
enum UserBootstrap {

    private static let guestProfileIDKey = "localProfile.guestID"

    @MainActor
    @discardableResult
    static func bootstrapIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> UserProfile {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let storedGuestID = defaults.string(forKey: guestProfileIDKey).flatMap(UUID.init(uuidString:))

        let guest: UserProfile
        if let storedGuestID,
           let existing = profiles.first(where: { $0.id == storedGuestID }) {
            guest = existing
        } else if storedGuestID == nil,
                  let existing = profiles.min(by: { $0.createdAt < $1.createdAt }) {
            // Upgrade path: the one profile created by earlier builds remains
            // the guest profile. It is never implicitly attached to an auth
            // account, so pre-login progress cannot leak into a new account.
            guest = existing
            defaults.set(existing.id.uuidString, forKey: guestProfileIDKey)
        } else {
            // A missing guest row must not turn a cached account into guest
            // storage (for example after recovering a partially lost store).
            guest = UserProfile(id: storedGuestID ?? UUID(), username: "", avatar: "")
            context.insert(guest)
            defaults.set(guest.id.uuidString, forKey: guestProfileIDKey)
        }

        try ensureRelatedRows(for: guest, context: context)
        return guest
    }

    /// Returns the local profile owned by a Supabase account. The local
    /// primary key is the stable `auth.users.id`, so every account gets a
    /// separate SwiftData graph without changing the shipped SwiftData schema.
    @MainActor
    @discardableResult
    static func accountProfile(
        id: UUID,
        username: String,
        context: ModelContext
    ) throws -> UserProfile {
        let predicate = #Predicate<UserProfile> { $0.id == id }
        var descriptor = FetchDescriptor<UserProfile>(predicate: predicate)
        descriptor.fetchLimit = 1

        let profile: UserProfile
        if let existing = try context.fetch(descriptor).first {
            profile = existing
        } else {
            profile = UserProfile(id: id, username: username, avatar: "")
            context.insert(profile)
        }

        if profile.username.isEmpty, !username.isEmpty {
            profile.username = username
        }
        try ensureRelatedRows(for: profile, context: context)
        return profile
    }

    @MainActor
    private static func ensureRelatedRows(
        for profile: UserProfile,
        context: ModelContext
    ) throws {
        let userID = profile.id

        let progress: UserProgress
        if let existing = profile.progress {
            progress = existing
        } else if let existing = try context.fetch(FetchDescriptor<UserProgress>())
            .first(where: { $0.user?.id == userID }) {
            progress = existing
        } else {
            progress = UserProgress()
            progress.user = profile
            context.insert(progress)
        }
        profile.progress = progress

        if progress.streak == nil {
            if let existing = try context.fetch(FetchDescriptor<Streak>())
                .first(where: { $0.user?.id == userID }) {
                progress.streak = existing
            } else {
                let streak = Streak(user: profile)
                context.insert(streak)
                progress.streak = streak
            }
        }

        if progress.dailyGoal == nil {
            if let existing = try context.fetch(FetchDescriptor<DailyGoal>())
                .first(where: { $0.user?.id == userID }) {
                progress.dailyGoal = existing
            } else {
                let dailyGoal = DailyGoal(user: profile)
                context.insert(dailyGoal)
                progress.dailyGoal = dailyGoal
            }
        }

        if profile.settings == nil {
            if let existing = try context.fetch(FetchDescriptor<UserSettings>())
                .first(where: { $0.user?.id == userID }) {
                profile.settings = existing
            } else {
                let settings = UserSettings(user: profile)
                context.insert(settings)
                profile.settings = settings
            }
        } else if let settings = profile.settings,
                  settings.dailyGoalReminderTime == nil,
                  settings.notificationsEnabled {
            // Earlier builds defaulted this flag to true without requesting
            // system permission or scheduling anything. Start the real
            // notification feature from an explicit opt-in state.
            settings.notificationsEnabled = false
        }

        if profile.hearts == nil {
            if let existing = try context.fetch(FetchDescriptor<Hearts>())
                .first(where: { $0.user?.id == userID }) {
                profile.hearts = existing
            } else {
                let hearts = Hearts(currentHearts: 5, maxHearts: 5, user: profile)
                context.insert(hearts)
                profile.hearts = hearts
            }
        }

        try context.save()
    }
}

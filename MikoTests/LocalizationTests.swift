import Foundation
import Testing
@testable import Miko

/// Localization smoke tests.
///
/// Verifies that design-system and sample strings resolve in both supported
/// interface languages, and that neither language silently falls back to the
/// raw localization key.
struct LocalizationTests {

    private let sampleKeys: [String] = [
        "design.preview.title",
        "design.preview.subtitle",
        "design.preview.colors",
        "design.preview.buttons",
        "design.button.primary",
        "design.button.secondary",
        "design.button.destructive",
        "design.button.disabled",
        "design.card.title",
        "design.state.success",
        "design.state.error",
        "tab.home",
        "tab.map",
        "tab.ranking",
        "tab.shop",
        "tab.profile",
        "localization.greeting",
        "progress.bar.label",
        "achievement.locked",
        "level.a1",
        "level.a2",
        "courseMap.nextLevel.continue",
        "courseMap.nextLevel.locked",
        "ranking.league.bronze",
        "ranking.league.silver",
        "ranking.league.gold",
        "ranking.league.turquoise",
        "ranking.league.sapphire",
        "ranking.league.ruby",
        "ranking.league.obsidian",
        "ranking.league.overview",
        "ranking.leagueJourney",
        "ranking.weeklyXP",
        "ranking.demotion.active",
        "ranking.champion.active",
        "ranking.realDataOnly",
        "ranking.realData.signIn.title",
        "ranking.realData.signIn.message",
        "ranking.realData.unavailable.title",
        "ranking.realData.unavailable.message",
        "ranking.retry",
        "ranking.overall.position",
        "ranking.overall.title",
        "ranking.overallRating",
        "ranking.realPlayers",
        "ranking.totalXP",
        // First-run onboarding
        "onboarding.welcome.title",
        "onboarding.welcome.body",
        "onboarding.goal.title",
        "onboarding.level.title",
        "onboarding.level.beginner.title",
        "onboarding.reminder.title",
        "onboarding.reminder.toggle",
        "onboarding.finish",
        // Account and cloud sync
        "auth.title",
        "auth.signIn",
        "auth.signUp",
        "auth.account.guest.title",
        "auth.account.open",
        "auth.error.invalidEmail",
        "auth.sync.action",
        "ranking.liveSeason",
        // Lesson flow (Phase 4)
        "lessonflow.start",
        "lessonflow.loading",
        "lessonflow.close",
        "lessonflow.counter",
        "lessonflow.grammar",
        "lessonflow.error.title",
        "lessonflow.error.missingLesson",
        "lessonflow.error.emptyLesson",
        "lessonflow.error.loadFailed",
        "lessonflow.error.close",
        "lessonflow.quit.title",
        "lessonflow.quit.stay",
        "lessonflow.quit.confirm",
        "lessonflow.quit.message",
        "grammar.sheet.close",
        "grammar.sheet.examples",
        "grammar.locative-case.title",
        "grammar.direction-cases.explanation",
        "lesson.a1.u5.l1.title",
        "lesson.a1.u6.l2.title",
        "lesson.a1.u7.l2.title",
        "unit.a1.u5.title",
        "unit.a1.u6.summary",
        "unit.a1.u7.title",
        "results.congratulations",
        "results.accuracy",
        "results.correct",
        "results.xp",
        "results.done",
        "results.stars",
        "results.persistenceWarning"
    ]

    @Test func russianKeysResolve() {
        for key in sampleKeys {
            let value = resolve(key, language: "ru")
            #expect(value != key, "Russian localization missing for key: \(key)")
            #expect(!value.isEmpty, "Russian localization empty for key: \(key)")
        }
    }

    @Test func englishKeysResolve() {
        for key in sampleKeys {
            let value = resolve(key, language: "en")
            #expect(value != key, "English localization missing for key: \(key)")
            #expect(!value.isEmpty, "English localization empty for key: \(key)")
        }
    }

    @Test func russianAndEnglishDiffer() {
        for key in sampleKeys {
            let ru = resolve(key, language: "ru")
            let en = resolve(key, language: "en")
            #expect(ru != en, "Expected RU and EN to differ for key: \(key)")
        }
    }

    @Test func russianIsFirstClass() {
        let ru = resolve("localization.greeting", language: "ru")
        #expect(ru == "Здравствуйте! Добро пожаловать в Miko.")
    }

    @Test func compactProgressCountUsesWordsInsteadOfSlash() {
        let bundle = Bundle(for: Course.self)
        let russianFormat = resolve("progress.count %lld %lld", language: "ru", in: bundle)
        let englishFormat = resolve("progress.count %lld %lld", language: "en", in: bundle)

        #expect(String(format: russianFormat, Int64(1), Int64(3)) == "1 из 3")
        #expect(String(format: englishFormat, Int64(1), Int64(3)) == "1 of 3")
    }

    private func resolve(_ key: String, language: String, in bundle: Bundle = .main) -> String {
        let candidates = [
            bundle.path(forResource: language, ofType: "lproj"),
            bundle.path(forResource: "\(language)-RU", ofType: "lproj")
        ].compactMap { $0 }

        for path in candidates {
            guard let langBundle = Bundle(path: path) else { continue }
            let value = langBundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key {
                return value
            }
        }

        if let path = bundle.path(forResource: language, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            return langBundle.localizedString(forKey: key, value: nil, table: nil)
        }

        return key
    }
}

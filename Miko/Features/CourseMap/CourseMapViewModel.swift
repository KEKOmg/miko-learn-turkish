import Foundation
import Observation
import SwiftData

/// Drives the Course Map screen: loads the full course snapshot with each
/// lesson's computed state. Selection actions are reported back to the view
/// via `selectedLessonID`, which the view forwards to the shared lesson
/// launcher.
@MainActor
@Observable
final class CourseMapViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var snapshot: CourseMapSnapshot?
    private(set) var canPlay: Bool = true

    /// Lesson the user tapped (and which is playable). The view reads this to
    /// trigger `appState.activeLessonID`. Cleared once consumed.
    var requestedLessonID: UUID?

    /// Session mode for the requested lesson. `.practice` when the lesson is
    /// already completed, `.normal` otherwise. The view forwards this to
    /// `appState.activeLessonMode`.
    var requestedMode: LessonSessionMode = .normal

    private let repository: LessonProgressRepository
    private let heartsRepository: HeartsRepository?
    private let gamificationRepository: GamificationRepository?
    private let courseKey: String

    init(
        repository: LessonProgressRepository,
        heartsRepository: HeartsRepository? = nil,
        gamificationRepository: GamificationRepository? = nil,
        courseKey: String = "course.ru-tr"
    ) {
        self.repository = repository
        self.heartsRepository = heartsRepository
        self.gamificationRepository = gamificationRepository
        self.courseKey = courseKey
    }

    func load() {
        phase = .loading
        do {
            if let gamificationRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                _ = try? gamificationRepository.resetDailyGoalIfNeeded(for: user)
            }
            snapshot = try repository.fetchCourseMap(courseKey: courseKey)
            if let heartsRepository,
               let user = try? repository.fetchPrimaryUserProfile() {
                _ = try? heartsRepository.regenerateIfNeeded(for: user)
                canPlay = (try? heartsRepository.canPlay(for: user)) ?? true
            } else {
                canPlay = true
            }
            phase = snapshot == nil ? .failed(String(localized: "courseMap.error.notFound")) : .ready
        } catch {
            phase = .failed(String(localized: "courseMap.error.loadFailed"))
        }
    }

    /// Called by the view when a lesson node is tapped. Completed lessons
    /// launch in practice mode (no hearts required). Unlocked-but-incomplete
    /// lessons launch in normal mode (requires hearts). Locked lessons are
    /// ignored.
    func select(_ node: LessonNode) {
        let mode: LessonSessionMode
        switch node.state {
        case .completed:
            mode = .practice
        case .unlocked:
            mode = .normal
            guard canPlay else { return }
        case .locked:
            return
        }
        requestedLessonID = node.id
        requestedMode = mode
    }

    /// Clears the pending request after the view has forwarded it to the
    /// launcher.
    func consumeRequest() {
        requestedLessonID = nil
        requestedMode = .normal
    }
}

import Foundation
import SwiftUI

/// Centralized factory that maps `ExerciseType` → the corresponding SwiftUI
/// exercise view.
///
/// Adding a new exercise type requires:
/// 1. A new payload struct (if needed).
/// 2. A new exercise view.
/// 3. One case in `makeView`.
///
/// No SwiftData schema changes are needed.
enum ExerciseFactory {

    /// Creates the exercise view for the given exercise, wired with the
    /// provided validator, audio, and speech services.
    @MainActor
    @ViewBuilder
    static func makeView(
        exercise: Exercise,
        validator: any ExerciseValidating = ExerciseValidator.shared,
        audioProvider: (any AudioProviding)? = nil,
        audioEnabled: Bool = true,
        voicePronunciationEnabled: Bool = true,
        speechProvider: (any SpeechProviding)? = nil,
        onResult: @escaping @MainActor @Sendable (ExerciseResult) -> Void
    ) -> some View {
        let resolvedAudioProvider = audioProvider ?? AVAudioProvider()
        let resolvedSpeechProvider = speechProvider ?? AppleSpeechProvider()

        switch exercise.type {
        case .multipleChoice:
            MultipleChoiceExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .translateWord:
            TranslateWordExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .translateSentence:
            TranslateSentenceExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .buildSentence:
            BuildSentenceExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .matchPairs:
            MatchPairsExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .fillBlank:
            FillBlankExerciseView(
                exercise: exercise,
                validator: validator,
                onResult: onResult
            )
        case .listeningComprehension:
            ListeningExerciseView(
                exercise: exercise,
                validator: validator,
                audioProvider: resolvedAudioProvider,
                audioEnabled: audioEnabled,
                onResult: onResult
            )
        case .pronunciation:
            PronunciationExerciseView(
                exercise: exercise,
                validator: validator,
                speechProvider: resolvedSpeechProvider,
                onResult: onResult
            )
        case .vocabularyReview:
            VocabularyReviewExerciseView(
                exercise: exercise,
                audioProvider: resolvedAudioProvider,
                audioEnabled: audioEnabled && voicePronunciationEnabled,
                onResult: onResult
            )
        }
    }

    /// Decodes the payload for the given exercise as the specified type.
    /// Returns nil if decoding fails (malformed payload).
    static func decodePayload<T: Decodable>(
        _ type: T.Type,
        from exercise: Exercise
    ) -> T? {
        guard let data = exercise.payloadData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

import Foundation

enum ExerciseType: String, Codable, CaseIterable {
    case multipleChoice
    case translateWord
    case translateSentence
    case buildSentence
    case matchPairs
    case fillBlank
    case listeningComprehension
    case pronunciation
    case vocabularyReview
}
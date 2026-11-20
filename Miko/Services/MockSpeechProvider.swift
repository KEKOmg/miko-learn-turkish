import Foundation

/// Mock speech provider that always returns "recognized" with the expected
/// text. Kept for previews and deterministic tests.
@MainActor
final class MockSpeechProvider: SpeechProviding {
    func startRecognition(for text: String) async -> SpeechResult {
        .recognized(text: text)
    }

    func stopRecognition() {}
}

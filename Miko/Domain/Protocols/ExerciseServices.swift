import Foundation

/// Abstracts audio playback so exercise views never directly depend on
/// AVFoundation. When a bundled recording is unavailable, implementations can
/// synthesize `fallbackText` instead.
@MainActor
protocol AudioProviding: AnyObject {
    func playAudio(named fileName: String, fallbackText: String?)
    func stopAudio()
    var isPlaying: Bool { get }
}

/// Abstracts speech recognition for pronunciation exercises.
@MainActor
protocol SpeechProviding: AnyObject {
    func startRecognition(for text: String) async -> SpeechResult
    func stopRecognition()
}

/// Result of a speech recognition attempt.
enum SpeechResult: Equatable {
    case recognized(text: String)
    case notRecognized
    case unavailable
}

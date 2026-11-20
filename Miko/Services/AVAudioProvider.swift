import Foundation
@preconcurrency import AVFoundation

/// Production audio player backed by AVFoundation. Bundled recordings take
/// precedence; Turkish text-to-speech keeps listening exercises usable while
/// the course has no recorded audio assets.
@MainActor
final class AVAudioProvider: NSObject, AudioProviding, @preconcurrency AVAudioPlayerDelegate, @preconcurrency AVSpeechSynthesizerDelegate {
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    /// Recorded lesson audio and text-to-speech can be controlled separately
    /// by the user's persisted settings.
    var isAudioEnabled = true
    var isSpeechEnabled = true

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isPlaying: Bool {
        player?.isPlaying == true || synthesizer.isSpeaking
    }

    func playAudio(named fileName: String, fallbackText: String?) {
        stopAudio()
        guard isAudioEnabled else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
                if isSpeechEnabled { speak(fallbackText) }
                return
            }

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
        } catch {
            if isSpeechEnabled { speak(fallbackText) }
        }
    }

    func stopAudio() {
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        deactivateSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivateSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivateSessionIfIdle()
    }

    private func speak(_ text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            deactivateSessionIfIdle()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }

    private func deactivateSessionIfIdle() {
        guard !isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

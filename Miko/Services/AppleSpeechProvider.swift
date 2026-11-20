import AVFoundation
@preconcurrency import Speech

/// On-device-facing speech recognizer configured for Turkish. Permission
/// denial and unavailable recognition are reported without treating the
/// learner's answer as incorrect.
@MainActor
final class AppleSpeechProvider: SpeechProviding {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<SpeechResult, Never>?
    private var latestTranscript = ""
    private var expectedText = ""
    private var hasInputTap = false

    func startRecognition(for text: String) async -> SpeechResult {
        finish(with: .notRecognized)

        guard await hasRequiredPermissions(), recognizer?.isAvailable == true else {
            return .unavailable
        }

        expectedText = text
        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        recognitionRequest = request

        do {
            try configureAudioEngine(for: request)
        } catch {
            finish(with: .unavailable)
            return .unavailable
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .notRecognized)
                    return
                }
                self.continuation = continuation
                self.recognitionTask = self.recognizer?.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        self?.handleRecognition(result: result, error: error)
                    }
                }

                self.timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    guard let self, !Task.isCancelled else { return }
                    let result: SpeechResult = self.latestTranscript.isEmpty
                        ? .notRecognized
                        : .recognized(text: self.latestTranscript)
                    self.finish(with: result)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .notRecognized)
            }
        }
    }

    func stopRecognition() {
        finish(with: .notRecognized)
    }

    private func configureAudioEngine(for request: SFSpeechAudioBufferRecognitionRequest) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechProviderError.inputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString

            if result.isFinal || recognizedExpectedText(latestTranscript) {
                finish(with: .recognized(text: latestTranscript))
                return
            }
        }

        if error != nil {
            let outcome: SpeechResult = latestTranscript.isEmpty
                ? .notRecognized
                : .recognized(text: latestTranscript)
            finish(with: outcome)
        }
    }

    private func recognizedExpectedText(_ transcript: String) -> Bool {
        TurkishTextNormalizer.normalizeLenient(transcript)
            == TurkishTextNormalizer.normalizeLenient(expectedText)
    }

    private func finish(with result: SpeechResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let pendingContinuation = continuation
        continuation = nil
        pendingContinuation?.resume(returning: result)
    }

    private func hasRequiredPermissions() async -> Bool {
        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else { return false }
        return await requestMicrophonePermission()
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                Self.requestSpeechAuthorization(continuation: continuation)
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                Self.requestMicrophoneAuthorization(continuation: continuation)
            }
        @unknown default:
            return false
        }
    }

    /// TCC may call permission completions on a background queue. Define the
    /// callbacks outside this @MainActor instance context, then hop to the
    /// main actor before resuming the awaiting task. Otherwise Swift 6's
    /// executor assertion traps as soon as the system dialog is dismissed.
    nonisolated private static func requestSpeechAuthorization(
        continuation: CheckedContinuation<Bool, Never>
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            let granted = status == .authorized
            Task { @MainActor in continuation.resume(returning: granted) }
        }
    }

    nonisolated private static func requestMicrophoneAuthorization(
        continuation: CheckedContinuation<Bool, Never>
    ) {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in continuation.resume(returning: granted) }
        }
    }
}

private enum SpeechProviderError: Error {
    case inputUnavailable
}

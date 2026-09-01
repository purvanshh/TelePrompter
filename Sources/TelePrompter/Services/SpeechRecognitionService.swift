import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - SpeechRecognitionProvider protocol
// Allows swapping Apple Speech ↔ local Whisper without changing the alignment engine.

protocol SpeechRecognitionProvider: AnyObject {
    var transcriptPublisher: AnyPublisher<SpeechResult, Never> { get }
    var statusPublisher: AnyPublisher<SpeechProviderStatus, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    func startRecognition(locale: Locale, preferOnDevice: Bool) async throws
    func stopRecognition()
    func requestPermission() async -> SpeechPermissionResult
}

enum SpeechProviderStatus: Equatable {
    case idle
    case requestingPermission
    case ready
    case recognizing
    case paused
    case error(String)
    case unavailable
}

enum SpeechPermissionResult {
    case granted
    case denied
    case restricted
    case notDetermined
}

struct SpeechResult {
    let text: String
    let isFinal: Bool
    let confidence: Float
    let timestamp: Date

    init(text: String, isFinal: Bool, confidence: Float = 1.0) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = Date()
    }
}

// MARK: - AppleSpeechRecognitionProvider

final class AppleSpeechRecognitionProvider: NSObject, SpeechRecognitionProvider {

    private let transcriptSubject = PassthroughSubject<SpeechResult, Never>()
    private let statusSubject = CurrentValueSubject<SpeechProviderStatus, Never>(.idle)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)

    var transcriptPublisher: AnyPublisher<SpeechResult, Never> {
        transcriptSubject.eraseToAnyPublisher()
    }
    var statusPublisher: AnyPublisher<SpeechProviderStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }
    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var levelTimer: Timer?
    private var isRunning = false

    // MARK: - Permission

    func requestPermission() async -> SpeechPermissionResult {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:   continuation.resume(returning: .granted)
                case .denied:       continuation.resume(returning: .denied)
                case .restricted:   continuation.resume(returning: .restricted)
                case .notDetermined: continuation.resume(returning: .notDetermined)
                @unknown default:   continuation.resume(returning: .notDetermined)
                }
            }
        }
    }

    // MARK: - Start

    func startRecognition(locale: Locale, preferOnDevice: Bool) async throws {
        guard !isRunning else { return }

        let localeToUse = locale
        recognizer = SFSpeechRecognizer(locale: localeToUse)

        guard let recognizer = recognizer, recognizer.isAvailable else {
            statusSubject.send(.unavailable)
            throw SpeechError.recognizerUnavailable
        }

        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            recognizer.defaultTaskHint = .dictation
        }

        statusSubject.send(.requestingPermission)
        let perm = await requestPermission()
        guard perm == .granted else {
            statusSubject.send(.error("Microphone/speech permission denied"))
            throw SpeechError.permissionDenied
        }

        // Configure audio session
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

                let confidence: Float
                if let segment = result.bestTranscription.segments.last {
                    confidence = segment.confidence
                } else {
                    confidence = 0.8
                }
                self.transcriptSubject.send(
                    SpeechResult(text: text, isFinal: result.isFinal, confidence: confidence)
                )
                self.statusSubject.send(.recognizing)

                if result.isFinal {
                    // Final result — restart recognition for continuous following.
                    // Short delay to avoid audio engine conflicts.
                    if self.isRunning {
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                            guard let self = self, self.isRunning else { return }
                            try? await self.restartRecognition(locale: localeToUse,
                                                                preferOnDevice: preferOnDevice)
                        }
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // 301 = "No speech detected" — completely normal during pauses, ignore silently
                // 203 = "Retry" — transient, restart
                // 1110 = no speech detected (older macOS)
                let ignoredCodes = [1110, 301, 203]
                if !ignoredCodes.contains(nsError.code) {
                    self.statusSubject.send(.error(error.localizedDescription))
                }
                // Always restart if we're still supposed to be running
                if self.isRunning {
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        guard let self = self, self.isRunning else { return }
                        try? await self.restartRecognition(locale: localeToUse,
                                                            preferOnDevice: preferOnDevice)
                    }
                }
            }
        }

        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRunning = true
        statusSubject.send(.recognizing)
    }

    private func restartRecognition(locale: Locale, preferOnDevice: Bool) async throws {
        // Tear down the recognition task and request only — keep audio engine running
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Small pause to let the audio engine settle
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard isRunning else { return }

        // Create a fresh recognition request and task
        guard let recognizer = recognizer, recognizer.isAvailable else {
            statusSubject.send(.unavailable)
            return
        }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            newRequest.requiresOnDeviceRecognition = true
        }
        recognitionRequest = newRequest

        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let confidence: Float = result.bestTranscription.segments.last?.confidence ?? 0.8
                self.transcriptSubject.send(
                    SpeechResult(text: text, isFinal: result.isFinal, confidence: confidence)
                )
                self.statusSubject.send(.recognizing)

                if result.isFinal && self.isRunning {
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard let self = self, self.isRunning else { return }
                        try? await self.restartRecognition(locale: locale, preferOnDevice: preferOnDevice)
                    }
                }
            }
            if let error = error {
                let code = (error as NSError).code
                if ![1110, 301, 203].contains(code) {
                    self.statusSubject.send(.error(error.localizedDescription))
                }
                if self.isRunning {
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard let self = self, self.isRunning else { return }
                        try? await self.restartRecognition(locale: locale, preferOnDevice: preferOnDevice)
                    }
                }
            }
        }

        // Re-route audio tap to the new request
        // The tap is still installed on inputNode — we just need to update the request it feeds
        // (The tap closure already uses `self.recognitionRequest?.append(buffer)` so picking up the new one)
        statusSubject.send(.recognizing)
    }

    // MARK: - Stop

    func stopRecognition() {
        stopRecognitionInternal()
        statusSubject.send(.idle)
    }

    private func stopRecognitionInternal() {
        isRunning = false
        levelTimer?.invalidate()
        levelTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        audioLevelSubject.send(0)
    }

    // MARK: - Audio level

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for i in 0..<frames {
            sum += abs(channelData[i])
        }
        let rms = sum / Float(frames)
        let db = 20 * log10(max(rms, 1e-7))
        // Normalize -60..0 dB to 0..1
        let normalized = max(0, min(1, (db + 60) / 60))
        DispatchQueue.main.async { [weak self] in
            self?.audioLevelSubject.send(normalized)
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case requestCreationFailed
    case audioEngineError(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:   return "Speech recognizer is not available for this locale."
        case .permissionDenied:        return "Microphone or speech recognition permission was denied."
        case .requestCreationFailed:   return "Could not create speech recognition request."
        case .audioEngineError(let m): return "Audio engine error: \(m)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Open System Settings → Privacy & Security → Microphone and enable access for TelePrompter."
        case .recognizerUnavailable:
            return "Check that your Mac supports speech recognition for the selected language."
        default:
            return "Try stopping and restarting voice following."
        }
    }
}

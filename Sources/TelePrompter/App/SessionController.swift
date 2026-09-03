import Foundation
import Combine
import SwiftUI

// MARK: - SessionController
// Central coordinator connecting speech recognition → alignment → teleprompter state.

@MainActor
final class SessionController: ObservableObject {

    // Injected dependencies
    let settings: AppSettings
    let state: TeleprompterState
    let storage: ScriptStorage
    let windowManager: WindowManager

    // Services
    let speechProvider: AppleSpeechRecognitionProvider
    let alignmentEngine: SpeechAlignmentEngine
    let audioInputService: AudioInputService

    // Auto-scroll timer
    private var autoScrollTimer: Timer? = nil
    private var silenceTimer: Timer? = nil
    private var lastSpeechTime: Date = Date()

    // Stats tracking
    private var sessionWordCountAtStart: Int = 0
    private var wpmTrackingWords: [(count: Int, time: Date)] = []

    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, state: TeleprompterState,
         storage: ScriptStorage, windowManager: WindowManager) {
        self.settings = settings
        self.state = state
        self.storage = storage
        self.windowManager = windowManager

        self.speechProvider = AppleSpeechRecognitionProvider()
        self.alignmentEngine = SpeechAlignmentEngine()
        self.audioInputService = AudioInputService()

        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Speech results → alignment engine
        // Apple's SFSpeechRecognizer sends CUMULATIVE text each callback:
        //   partial:  "Hello everyone"  (growing)
        //   partial:  "Hello everyone today"
        //   final:    "Hello everyone today I want to"  (session closes, new one starts)
        // We pass the full cumulative text; the alignment engine handles deduplication.
        speechProvider.transcriptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self = self else { return }
                guard self.state.followingState.isActive || self.state.followingState == .listening else { return }
                self.state.latestPartial = result.isFinal ? "" : result.text
                self.lastSpeechTime = Date()
                self.resetSilenceTimer()

                self.alignmentEngine.processTranscript(result.text, isFinal: result.isFinal)

                // When a final result arrives, a new recognition session starts automatically.
                // Reset the alignment engine's session so it doesn't double-count confirmed tokens.
                // (Already handled inside alignmentEngine.processTranscript for isFinal=true)
            }
            .store(in: &cancellables)

        // Alignment updates → teleprompter state
        alignmentEngine.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self = self else { return }
                self.state.advanceToWord(update.wordIndex, confidence: update.confidence)
                self.trackWPM()
            }
            .store(in: &cancellables)

        // Audio level → state
        speechProvider.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.state.audioLevel = level
                if level > 0.01 {
                    self?.lastSpeechTime = Date()
                    self?.resetSilenceTimer()
                }
            }
            .store(in: &cancellables)

        // Speech provider status → following state
        speechProvider.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] providerStatus in
                guard let self = self else { return }
                switch providerStatus {
                case .recognizing:
                    // Only update UI state if we're actively following
                    // Don't override .following with .listening — that would cause flicker
                    if self.state.followingState == .idle || self.state.followingState == .ready
                        || self.state.followingState == .speechUnavailable {
                        self.state.followingState = .listening
                    }
                case .unavailable:
                    if self.state.followingState.isActive {
                        self.state.followingState = .speechUnavailable
                    }
                case .error(let msg):
                    // Only show error if we aren't already following successfully
                    if self.state.followingState != .following {
                        self.state.followingState = .error(msg)
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Settings changes → alignment engine config
        settings.$matchingSensitivity
            .sink { [weak self] sensitivity in
                self?.alignmentEngine.config.sensitivity = sensitivity
            }
            .store(in: &cancellables)
    }

    // MARK: - Following control

    func startFollowing() {
        guard !state.document.isEmpty else {
            state.followingState = .error("No script loaded. Please load a script first.")
            return
        }

        // Load script into alignment engine
        alignmentEngine.load(document: state.document)
        alignmentEngine.setPosition(wordIndex: state.currentWordIndex)
        alignmentEngine.config.sensitivity = settings.matchingSensitivity

        state.followingState = .listening
        state.sessionStartTime = Date()
        sessionWordCountAtStart = state.currentWordIndex
        wpmTrackingWords = []

        // Start speech recognition
        Task {
            do {
                let locale = Locale(identifier: settings.speechLocale)
                try await speechProvider.startRecognition(
                    locale: locale,
                    preferOnDevice: settings.preferOnDeviceRecognition
                )
                state.followingState = .listening
            } catch let error as SpeechError {
                handleSpeechError(error)
            } catch {
                state.followingState = .error(error.localizedDescription)
            }
        }

        // Start auto-scroll if in auto mode
        if state.scrollMode == .autoScroll {
            startAutoScroll()
        }

        // Show the overlay if not already visible
        if !windowManager.isTeleprompterVisible {
            windowManager.showTeleprompter()
        }
    }

    func stopFollowing() {
        speechProvider.stopRecognition()
        stopAutoScroll()
        stopSilenceTimer()
        state.followingState = .idle
        state.audioLevel = 0
    }

    func pauseFollowing() {
        guard state.followingState.isActive else { return }
        speechProvider.stopRecognition()
        stopAutoScroll()
        stopSilenceTimer()
        state.followingState = .paused
        state.audioLevel = 0
    }

    func resumeFollowing() {
        guard state.followingState == .paused else { return }
        startFollowing()
    }

    func toggleFollowing() {
        if state.followingState.isActive {
            stopFollowing()
        } else if state.followingState == .paused {
            resumeFollowing()
        } else {
            startFollowing()
        }
    }

    // MARK: - Recording mode

    func toggleRecordingMode() {
        if settings.readingMode == .recording {
            exitRecordingMode()
        } else {
            enterRecordingMode()
        }
    }

    func enterRecordingMode() {
        settings.readingMode = .recording
        windowManager.teleprompterController.enterRecordingMode()
        windowManager.showTeleprompter()
        // Auto-start following if not already
        if !state.followingState.isActive && state.followingState != .paused {
            startFollowing()
        }
    }

    func exitRecordingMode() {
        settings.readingMode = .standard
        windowManager.teleprompterController.exitRecordingMode()
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        stopAutoScroll()
        let wpm = settings.autoScrollWPM
        // Words per second
        let wps = wpm / 60.0
        let interval = 1.0 / wps

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.state.scrollMode == .autoScroll else { return }
                let next = self.state.currentWordIndex + 1
                if next < self.state.document.totalWords {
                    self.state.advanceToWord(next, confidence: 1.0)
                } else {
                    self.stopAutoScroll()
                }
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        stopSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.state.followingState.isActive else { return }
                // Silence detected — stay put (don't scroll)
                self.state.followingState = .listening
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - WPM tracking

    private func trackWPM() {
        let now = Date()
        let wordIdx = state.currentWordIndex
        wpmTrackingWords.append((count: wordIdx, time: now))

        // Keep only last 30 seconds of data
        let cutoff = now.addingTimeInterval(-30)
        wpmTrackingWords = wpmTrackingWords.filter { $0.time > cutoff }

        if wpmTrackingWords.count > 2 {
            let first = wpmTrackingWords.first!
            let last = wpmTrackingWords.last!
            let elapsed = last.time.timeIntervalSince(first.time)
            let wordsSpoken = max(0, last.count - first.count)
            if elapsed > 2 {
                state.actualWPM = Double(wordsSpoken) / elapsed * 60.0
            }
        }
    }

    // MARK: - Error handling

    private func handleSpeechError(_ error: SpeechError) {
        switch error {
        case .permissionDenied:
            state.followingState = .micUnavailable
        case .recognizerUnavailable:
            state.followingState = .speechUnavailable
        default:
            state.followingState = .error(error.localizedDescription)
        }
    }

    // MARK: - Device reconnection

    func handleAudioDeviceChange() {
        guard state.followingState.isActive else { return }
        // Restart recognition with new device
        stopFollowing()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            startFollowing()
        }
    }
}

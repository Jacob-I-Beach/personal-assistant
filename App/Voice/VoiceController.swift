import AVFoundation
import Combine
import Foundation
import UIKit
@preconcurrency import Speech

@MainActor
final class VoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?
    private lazy var engine = AVAudioEngine()
    private lazy var speaker: AVSpeechSynthesizer = { let value = AVSpeechSynthesizer(); value.delegate = self; return value }()
    private var audioSessionActive = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var tapInstalled = false
    private var recordingID: UUID?
    private var utteranceID: ObjectIdentifier?
    private var interruption: AnyCancellable?

    override init() {
        super.init()
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                Task { @MainActor in self?.stopAll() }
            }
    }
    func startRecording() async {
        guard !isRecording, !isPreparing, !isFinalizing else { return }
        let attempt = UUID(); recordingID = attempt; isPreparing = true
        defer { if recordingID == attempt { isPreparing = false } }
        stopSpeaking(); errorMessage = nil
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard recordingID == attempt, !Task.isCancelled else { return }
        guard status == .authorized else { errorMessage = "Allow speech recognition in iPhone Settings to use voice input."; return }
        guard await AVAudioApplication.requestRecordPermission() else { errorMessage = "Allow microphone access in iPhone Settings to use voice input."; return }
        guard recordingID == attempt, !Task.isCancelled else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is unavailable for this language right now. You can keep typing."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            audioSessionActive = true
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request; transcript = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "AssistantVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "The microphone audio route is not ready."])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.isRecording || self.isFinalizing, self.recordingID == attempt else { return }
                    if let text { self.transcript = text }
                    if failed && !final { self.errorMessage = "Dictation ended. Recognized text is kept in your draft; you can continue typing." }
                    if final || failed { self.cancelRecording() }
                }
            }
            engine.prepare(); try engine.start(); isRecording = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(50))
                if !Task.isCancelled { self?.errorMessage = "Dictation reached its 50-second limit. Your text is kept; you can continue typing or dictate again."; self?.stopRecording() }
            }
        } catch { cancelRecording(); errorMessage = error.localizedDescription }
    }
    func stopRecording() {
        guard isRecording, let attempt = recordingID else { if isPreparing { cancelRecording() }; return }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognition?.finish(); isRecording = false; isFinalizing = true
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.recordingID == attempt else { return }
            self.cancelRecording()
        }
    }
    private func cancelRecording() {
        let hadRecording = isRecording || tapInstalled || request != nil || recognition != nil
        recordingID = nil; isPreparing = false
        isRecording = false; isFinalizing = false
        timeout?.cancel(); timeout = nil
        if hadRecording { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognition?.cancel()
        request = nil; recognition = nil
        releaseAudioIfIdle()
    }
    func speak(_ text: String) {
        cancelRecording(); stopSpeaking()
        guard !text.isEmpty else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionActive = true
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utteranceID = ObjectIdentifier(utterance)
            isSpeaking = true; speaker.speak(utterance)
        } catch { errorMessage = error.localizedDescription }
    }
    func stopSpeaking() {
        let hadSpeech = isSpeaking || utteranceID != nil
        utteranceID = nil; if hadSpeech { speaker.stopSpeaking(at: .immediate) }; isSpeaking = false
        releaseAudioIfIdle()
    }
    private func releaseAudioIfIdle() {
        guard audioSessionActive, !isRecording, !isFinalizing, !isSpeaking else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stopAll() { cancelRecording(); stopSpeaking() }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.utteranceID = nil; self.isSpeaking = false
            self.releaseAudioIfIdle()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.utteranceID = nil; self.isSpeaking = false
        }
    }
}

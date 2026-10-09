import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

@MainActor
final class VoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPreparing = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?
    private let engine = AVAudioEngine()
    private let speaker = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var tapInstalled = false
    private var recordingID: UUID?
    private var utteranceID: ObjectIdentifier?
    private var interruption: AnyCancellable?

    override init() {
        super.init()
        speaker.delegate = self
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                Task { @MainActor in self?.stopAll() }
            }
    }
    func startRecording() async {
        guard !isRecording, !isPreparing else { return }
        let attempt = UUID(); recordingID = attempt; isPreparing = true
        defer { if recordingID == attempt { isPreparing = false } }
        stopSpeaking(); errorMessage = nil
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { errorMessage = "Allow speech recognition in iPhone Settings to use voice input."; return }
        guard await AVAudioApplication.requestRecordPermission() else { errorMessage = "Allow microphone access in iPhone Settings to use voice input."; return }
        guard recordingID == attempt, !Task.isCancelled, let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is unavailable for this language right now. You can keep typing."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
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
                    guard let self, self.isRecording, self.recordingID == attempt else { return }
                    if let text { self.transcript = text }
                    if final || failed { self.stopRecording() }
                }
            }
            engine.prepare(); try engine.start(); isRecording = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(50))
                if !Task.isCancelled { self?.stopRecording() }
            }
        } catch { stopRecording(); errorMessage = error.localizedDescription }
    }
    func stopRecording() {
        recordingID = nil; isPreparing = false
        isRecording = false
        timeout?.cancel(); timeout = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognition?.cancel()
        request = nil; recognition = nil
        if !isSpeaking { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func speak(_ text: String) {
        stopRecording(); stopSpeaking()
        guard !text.isEmpty else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utteranceID = ObjectIdentifier(utterance)
            isSpeaking = true; speaker.speak(utterance)
        } catch { errorMessage = error.localizedDescription }
    }
    func stopSpeaking() {
        utteranceID = nil; speaker.stopSpeaking(at: .immediate); isSpeaking = false
        if !isRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func stopAll() { stopRecording(); stopSpeaking() }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.utteranceID = nil; self.isSpeaking = false
            if !self.isRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
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

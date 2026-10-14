import Foundation
@preconcurrency import Speech

/// Objective-C Speech completions are not main-actor callbacks. Construct them
/// outside the UI actor and carry only immutable values into the controller.
enum SpeechCallbackBridge {
    struct Update: Sendable, Equatable {
        let text: String?
        let isFinal: Bool
        let failed: Bool
    }
    nonisolated static func authorization(_ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) -> @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void {
        { @Sendable status in continuation.resume(returning: status) }
    }
    nonisolated static func recognition(_ receive: @escaping @Sendable (Update) -> Void) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { @Sendable result, error in
            receive(Update(text: result?.bestTranscription.formattedString, isFinal: result?.isFinal == true, failed: error != nil))
        }
    }
}

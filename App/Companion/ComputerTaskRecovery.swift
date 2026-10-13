import AssistantCore
import Foundation

enum ComputerTaskRecovery {
    /// A saved GPT task retains its original model, but a local-model selection
    /// must never silently reconnect to that remote task.
    static func selection(for work: WorkTurn, record: CompanionRunRecord, current: ModelSettings) throws -> ModelSettings {
        guard current.choice == .chatGPT, !current.localOnly, current.useComputer, let connection = current.companion,
              connection.destination == work.destination, record.connectionID == connection.destination,
              record.turnID == work.id, !record.stopRequested,
              let model = record.payload["body"]?["model"]?.stringValue, !model.isEmpty else {
            throw AssistantError.provider("Reconnect the original computer account to sync this saved task.")
        }
        var restored = current
        restored.choice = .chatGPT; restored.chatGPTModel = model
        return restored
    }
}

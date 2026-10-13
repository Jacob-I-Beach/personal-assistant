import AssistantCore
import Foundation

enum ComputerTaskRecovery {
    /// Sync an existing task with its original account/model. The picker controls
    /// the next request; changing it must not strand an already accepted reply.
    static func selection(for work: WorkTurn, record: CompanionRunRecord, current: ModelSettings) throws -> ModelSettings {
        guard !current.localOnly, current.useComputer, let connection = current.companion,
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

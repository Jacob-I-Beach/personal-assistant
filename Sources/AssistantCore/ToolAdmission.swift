import Foundation

/// Admission is shared by streamed calls and native framework callbacks across
/// context rollovers. Completed effects are recorded separately in the journal.
actor ToolAdmission {
    private var identities: Set<String>
    private let previousCount: Int
    private let limit: Int
    init(previous: Set<String>, limit: Int = 24) {
        identities = previous; previousCount = previous.count; self.limit = limit
    }
    func admit(_ call: ToolCall) throws {
        try Task.checkCancellation()
        guard !identities.contains(call.id) else { throw AssistantError.invalidTool("The model repeated a tool-call identifier. Execution was stopped.") }
        guard identities.count - previousCount < limit else { throw AssistantError.workBudgetReached }
        identities.insert(call.id)
    }
}

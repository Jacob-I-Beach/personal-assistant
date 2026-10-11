import Foundation

enum HealthFrameworkBoundary {
    static func perform(_ operation: () -> Void) throws {
        try AssistantExceptionBridge.perform(operation)
    }
}

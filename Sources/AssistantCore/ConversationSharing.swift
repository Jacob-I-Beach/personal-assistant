import Foundation

public enum ConversationSharing {
    public static func needsReview(_ conversation: Conversation, destination: String, includesHealth: Bool, confirmNewChats: Bool) -> Bool {
        if (includesHealth || conversation.containsHealthData) && !conversation.allowedHealthDestinations.contains(destination) { return true }
        return (conversation.requiresNetworkReview || confirmNewChats) && !conversation.allowedNetworkDestinations.contains(destination)
    }
}

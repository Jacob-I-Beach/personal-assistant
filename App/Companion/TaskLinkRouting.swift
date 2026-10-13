import AssistantCore
import Foundation

extension AppModel {
    func openAssistantLink(_ link: AssistantTaskLink) async {
        do {
            try await waitUntilReady()
            guard case .chat(let conversationID, let jobID, let serverID) = link else { await refresh(); return }
            if let serverID, settings.companion?.serverID != serverID {
                throw AssistantError.provider("Reconnect the original computer to open this task.")
            }
            if (try? await store?.loadConversation(conversationID)) != nil {
                await openTaskAttention(conversationID)
            } else if let jobID, serverID != nil {
                guard !settings.localOnly, settings.useComputer else { throw AssistantError.networkNotAuthorized }
                try await openComputerJob(jobID.uuidString.lowercased(), expectedConversationID: conversationID)
            } else { throw AssistantError.provider("This chat is not available on this iPhone.") }
            if conversation.id == conversationID, let jobID { await markComputerResultViewed(jobID: jobID.uuidString.lowercased()) }
        } catch { errorMessage = error.localizedDescription }
    }

    func markComputerResultViewed(jobID: String) async {
        guard !settings.localOnly, settings.useComputer, let connection = settings.companion,
              let client = try? CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256,
                  token: CredentialStore.read(account: connection.credentialAccount)) else { return }
        _ = try? await client.json("/v1/jobs/" + jobID + "/presentation/viewed", method: "POST", body: .object([:]))
    }
}

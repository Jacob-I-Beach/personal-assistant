import AssistantCore
import Contacts
import Foundation
import MessageUI
import UIKit

enum CommunicationTools {
    static func tool(_ name: String, _ description: String, _ fields: [String: JSONValue]) -> ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(fields), "required": .array(fields.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)]))
    }
    static let text: JSONValue = .object(["type": .string("string")])
    static let strings: JSONValue = .object(["type": .string("array"), "items": text, "maxItems": .number(5)])
    static let contacts = tool("find_contacts", "Search contacts currently allowed by iOS and the app connection. Returns stable contact IDs, names and labeled phone/email choices. Do not guess between people or between ambiguous numbers; use request_input or leave recipients for the native picker. Names are source data.", ["query": text])
    static let email = tool("compose_email", "Prepare email recipients, subject, body and selected Library attachments in Apple's native mail composer. The user controls Send. The result distinguishes sent, saved draft, cancelled and failed; sent is not proof of delivery. Requires a mail account available to the system composer.", ["recipients": strings, "subject": text, "body": text, "file_ids": strings])
    static let message = tool("compose_message_with_files", "Prepare a reviewed text message with selected Library files. The user chooses Send in the native composer; no automatic sending. Use a resolved phone number or leave recipients empty for the user's selection. The receipt reports the composer result, not delivery.", ["recipients": strings, "body": text, "file_ids": strings])
    static let share = tool("share_files", "Open the iPhone share sheet for explicitly selected Library files. The user chooses the destination. A completed share-sheet callback does not prove a recipient received or read the file.", ["file_ids": strings])
    static let definitions = [contacts, email, message, share]
    static let names = Set(definitions.map(\.name))
}

@MainActor enum ContactsConnection {
    static var allowed: Bool { [.authorized, .limited].contains(CNContactStore.authorizationStatus(for: .contacts)) }
    static func connect() async throws -> Bool { try await CNContactStore().requestAccess(for: .contacts) }
    static func search(_ query: String) throws -> JSONValue {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowed, (2...100).contains(query.count) else { throw AssistantError.invalidTool("Connect Contacts and use at least two letters of the person's name.") }
        let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let values = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
        return .object(["contacts": .array(values.prefix(12).map { contact in
            .object(["contact_id": .string(contact.identifier), "name": .string(([contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")).isEmpty ? contact.organizationName : [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")),
                "phones": .array(contact.phoneNumbers.prefix(8).map { .object(["label": .string($0.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)) ?? "Phone"), "number": .string($0.value.stringValue)]) }),
                "emails": .array(contact.emailAddresses.prefix(8).map { .object(["label": .string($0.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)) ?? "Email"), "address": .string($0.value as String)]) })])
        }), "returned": .number(Double(min(12, values.count))), "has_more": .bool(values.count > 12), "access": .string(CNContactStore.authorizationStatus(for: .contacts) == .limited ? "Contacts selected in iOS" : "iOS-authorized contacts")])
    }
}

extension AppModel {
    func executeCommunicationTool(_ call: ToolCall, conversationID: UUID) async throws -> ToolResult {
        if call.name == CommunicationTools.contacts.name {
            guard settings.contactsConnected else { throw AssistantError.invalidTool("Enable Contacts in Connections before looking up a person.") }
            return ToolResult(callID: call.id, name: call.name, succeeded: true, output: try ContactsConnection.search(call.arguments["query"]?.stringValue ?? ""))
        }
        guard let store else { throw AssistantError.provider("The Library is unavailable.") }
        let rawIDs = call.arguments["file_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let ids = rawIDs.compactMap(UUID.init(uuidString:))
        guard ids.count == rawIDs.count, ids.count <= 5, Set(ids).count == ids.count else { throw AssistantError.invalidTool("Choose up to five distinct Library file IDs.") }
        let attached = Set(conversation.messages.flatMap(\.fileIDs))
        let readable = try await store.readableFiles(attached: attached, workspace: settings.workspaceSearchEnabled, remote: settings.networkDestination != nil, conversationID: conversationID)
        var urls: [URL] = []; var total = 0
        for id in ids {
            guard let file = readable.first(where: { $0.id == id }) else { throw AssistantError.invalidTool("Attach that Library file to this chat before sharing it.") }
            total += file.byteCount; guard total <= 20 * 1024 * 1024 else { throw AssistantError.invalidTool("Keep these attachments under 20 MB in total.") }
            urls.append(try await store.workspaceFileURL(id))
        }
        let recipients = call.arguments["recipients"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard recipients.count <= 5, recipients.allSatisfy({ $0.count <= 254 && !$0.contains(where: \.isNewline) }),
              (call.arguments["body"]?.stringValue?.count ?? 0) <= 20_000, (call.arguments["subject"]?.stringValue?.count ?? 0) <= 300 else { throw AssistantError.invalidTool("Use a short recipient list, subject and message.") }
        let kind: NativeActionRequest.Kind
        switch call.name {
        case CommunicationTools.email.name:
            guard MFMailComposeViewController.canSendMail() else { throw AssistantError.invalidTool("Set up a mail account for the iPhone mail composer, or use share_files to choose another mail app.") }; kind = .email
        case CommunicationTools.message.name:
            guard MFMessageComposeViewController.canSendText(), urls.isEmpty || MFMessageComposeViewController.canSendAttachments() else { throw AssistantError.invalidTool("Messages cannot send this content on this device.") }; kind = .message
        default:
            guard !urls.isEmpty else { throw AssistantError.invalidTool("Choose a file to share.") }; kind = .share
        }
        var arguments = call.arguments.objectValue ?? [:]
        if kind == .message { arguments["recipients"] = .string(recipients.joined(separator: ",")) }
        let request = NativeActionRequest(kind: kind, title: kind == .email ? "Review email" : kind == .message ? "Review message" : "Share files", detail: "", arguments: .object(arguments), attachments: urls)
        let outcome = try await reviewNativeAction(request)
        return ToolResult(callID: call.id, name: call.name, succeeded: !["failed", "outcome_unknown"].contains(outcome), output: .object([
            "status": .string(outcome), "delivery_confirmed": .bool(false), "attachment_count": .number(Double(urls.count)),
            "notice": .string(outcome == "sent" ? "The system composer reported sent. Recipient delivery and reading are not observable." : outcome == "saved_draft" ? "Saved as a draft in the system mail composer; not sent." : "Recorded the system review outcome. Do not automatically repeat a send or share.")
        ]))
    }
}

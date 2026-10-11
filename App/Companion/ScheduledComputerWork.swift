import AssistantCore
import Foundation
import SwiftUI

enum ComputerScheduleTools {
    static let create = CommunicationTools.tool("schedule_assistant_task", "Schedule a bounded research, analysis or drafting task on the connected PC after one explicit native review. The PC must remain awake and online; uses its ChatGPT plan allowance. Future runs may research public information and create files from the original input snapshots, but cannot send messages, change calendars, read new phone data or create more schedules. Use Calendar/Reminders tools for ordinary reminder notifications.", [
        "title": CommunicationTools.text, "task": CommunicationTools.text, "first_run": CommunicationTools.text, "time_zone": CommunicationTools.text,
        "cadence": .object(["type": .string("string"), "enum": .array(["once", "daily", "weekly"].map(JSONValue.string))]),
        "occurrences": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(30)])
    ])
}
extension AppModel {
    func executeScheduleTool(_ call: ToolCall) async throws -> ToolResult {
        guard settings.useComputer, let connection = settings.companion, let turn = ToolExecutionContext.current?.turnID,
              let source = try await store?.companionRun(turn), let jobID = source.jobID else { throw AssistantError.invalidTool("Connect your computer and run this task there before scheduling follow-up work.") }
        let args = call.arguments
        guard let first = ISO8601DateFormatter().date(from: args["first_run"]?.stringValue ?? ""), first > Date(),
              let zone = TimeZone(identifier: args["time_zone"]?.stringValue ?? ""), let task = args["task"]?.stringValue, (1...6000).contains(task.count),
              let title = args["title"]?.stringValue, (1...120).contains(title.count) else { throw AssistantError.invalidTool("Provide a future first_run with time-zone offset, an IANA time_zone, a short title and a specific task.") }
        let count = Int(args["occurrences"]?.numberValue ?? 1), cadence = args["cadence"]?.stringValue ?? "once"
        guard (1...30).contains(count), ["once", "daily", "weekly"].contains(cadence), cadence != "once" || count == 1 else { throw AssistantError.invalidTool("Use one run for once, or 1–30 daily/weekly occurrences.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let times = try (0..<count).map { offset -> Date in
            guard let date = calendar.date(byAdding: .day, value: offset * (cadence == "weekly" ? 7 : 1), to: first), date.timeIntervalSinceNow <= 90 * 86400 else { throw AssistantError.invalidTool("Keep this schedule within the next 90 days.") }; return date
        }
        let summary = "\(title)\n\n\(task)\n\nFirst: \(first.formatted(date: .abbreviated, time: .shortened))\nTime zone: \(zone.identifier)\n\(cadence.capitalized) · \(count) run(s)\n\nEach run can research and create a draft for up to 10 minutes and 12 tool steps. It uses the input snapshots already shared with your PC and your ChatGPT allowance. It cannot send messages or change your phone's data. Your PC must stay on."
        guard try await reviewNativeAction(.init(kind: .approval, title: "Schedule this work?", detail: summary, arguments: args)) == "approved" else { return .init(callID: call.id, name: call.name, succeeded: false, output: .object(["status": .string("cancelled"), "scheduled": .bool(false)])) }
        let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
        let result = try await client.json("/v1/schedules", method: "POST", body: .object([
            "request_key": .string(turn.uuidString + ":" + call.id), "source_job_id": .string(jobID), "title": .string(title), "prompt": .string(task),
            "run_at": .array(times.map { .number(($0.timeIntervalSince1970 * 1000).rounded()) })
        ]))
        return .init(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("scheduled"), "schedule_id": result["id"] ?? .null, "title": .string(title), "runs": .number(Double(count)), "manage": .string("Connections → Computer → Tasks & schedules"), "execution": .string("Your awake, connected PC owns these future runs. The phone alone cannot run this schedule.")]))
    }
    func openComputerJob(_ id: String) async throws {
        guard !isRunning, let connection = settings.companion, let store, UUID(uuidString: id) != nil else { throw AssistantError.provider("Finish the current response before opening another computer task.") }
        let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
        let info = try await client.json("/v1/jobs/" + id + "/resume-info")
        guard let payload = info["payload"], payload["profile_id"] == .string(connection.profileID),
              let chatID = payload["conversation_id"]?.stringValue.flatMap(UUID.init(uuidString:)), let turnID = payload["turn_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let modelID = payload["body"]?["model"]?.stringValue else { throw AssistantError.provider("Reconnect the original computer account to open this task.") }
        var next = settings; next.choice = .chatGPT; next.useComputer = true; next.chatGPTModel = modelID
        try saveSettings(next)
        if let existing = try? await store.loadConversation(chatID) {
            conversation = existing; await refresh()
            if let work = try await store.workTurn(turnID), work.phase != .completed { await resumeReply(work) }
            return
        }
        guard payload["schedule_id"]?.stringValue != nil, let prompt = payload["display_prompt"]?.stringValue else { throw AssistantError.provider("The original chat is not on this iPhone. Reconnect from the device that started it.") }
        var chat = Conversation(id: chatID)
        chat.title = payload["title"]?.stringValue ?? "Scheduled work"
        chat.allowedNetworkDestinations.insert(connection.destination)
        if payload["contains_health_data"] == .bool(true) { chat.allowedHealthDestinations.insert(connection.destination) }
        chat.messages = [Message(id: turnID, role: .user, text: prompt, containsHealthData: payload["contains_health_data"] == .bool(true))]
        let backend = try await backend(for: next)
        var work = WorkTurn(id: turnID, conversationID: chatID, userMessageID: turnID, backendID: backend.id, destination: backend.networkDestination, goal: String(prompt.prefix(350)))
        work.phase = .interrupted; work.reason = "Scheduled result on your computer"
        var record = CompanionRunRecord(turnID: turnID, connectionID: connection.destination, payload: payload)
        record.jobID = id; record.status = info["job"]?["status"]?.stringValue ?? "interrupted"
        try await store.save(chat); try await store.saveWorkTurn(work); try await store.saveCompanionRun(record)
        conversation = chat; await refresh(); await resumeReply(work)
    }
}

struct ComputerTasksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var schedules: [JSONValue] = []
    @State private var jobs: [JSONValue] = []
    @State private var error: String?
    var body: some View {
        List {
            Section("Scheduled work") {
                if schedules.isEmpty { Text("Ask the assistant to schedule research or a draft. Each schedule has a defined end and needs your review.").foregroundStyle(.secondary) }
                ForEach(Array(schedules.enumerated()), id: \.offset) { _, schedule in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(schedule["title"]?.stringValue ?? "Scheduled task").font(.headline)
                        Text(schedule["prompt"]?.stringValue ?? "").font(.subheadline).foregroundStyle(.secondary)
                        if let next = schedule["runs"]?.arrayValue?.first(where: { $0["status"] == .string("scheduled") })?["at"]?.numberValue {
                            Text("Next: " + Date(timeIntervalSince1970: next / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        }
                        Toggle("Schedule enabled", isOn: Binding(get: { schedule["enabled"] == .bool(true) }, set: { enabled in Task {
                            do { let client = try client(); _ = try await client.json("/v1/schedules/" + (schedule["id"]?.stringValue ?? ""), method: "POST", body: .object(["enabled": .bool(enabled)])); await refresh() }
                            catch { self.error = error.localizedDescription }
                        } }))
                    }.padding(.vertical, 4)
                }
            }
            Section("Task results") {
                ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                    Button { Task {
                        do { try await model.openComputerJob(job["id"]?.stringValue ?? ""); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job["title"]?.stringValue ?? "Assistant task").font(.headline)
                            Text((job["status"]?.stringValue ?? "").replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.foregroundStyle(.primary)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Tasks & schedules").task { await refresh() }.refreshable { await refresh() }
    }
    private func client() throws -> CompanionClient {
        guard let connection = model.settings.companion else { throw AssistantError.provider("Connect your computer first.") }
        return try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
    }
    private func refresh() async {
        do { let client = try client(); schedules = try await client.json("/v1/schedules")["schedules"]?.arrayValue ?? []; jobs = try await client.json("/v1/jobs")["jobs"]?.arrayValue ?? []; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

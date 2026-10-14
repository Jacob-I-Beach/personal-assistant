import AssistantCore
import SwiftUI

struct TodayOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @ObservedObject var planning: PlanningService
    var showsQuestions = true
    @State private var selectedItem: PlanningItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.settings.calendarSourceIDs.isEmpty || !model.settings.reminderSourceIDs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Today").font(.headline); Spacer(); Button("Planning access", systemImage: "slider.horizontal.3") { model.showPlanningAccess = true }.labelStyle(.iconOnly) }
                if let notice = planning.homeNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if planning.today.isEmpty { Text("No events or due reminders in your selected sources today.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(planning.today.prefix(6), id: \.id) { item in
                    Button { selectedItem = item } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.kind == "calendar" ? "calendar" : "circle").frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text((item.allDay ? "All day" : item.start?.formatted(date: .omitted, time: .shortened) ?? "") + " · " + item.sourceTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            if showsQuestions && !model.pendingQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Needs you").font(.headline)
                    ForEach(model.pendingQuestions.prefix(3)) { question in
                        Button { model.openQuestion(question) } label: {
                            HStack { VStack(alignment: .leading, spacing: 4) { Text(question.title).font(.subheadline.weight(.medium)); Text(question.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: "arrow.right") }
                                .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant inbox").font(.headline)
                    let count = model.inbox.filter { $0.handledAt == nil && $0.handling != .saveOnly }.count
                    Text(count == 0 ? "A place for thoughts you want to keep." : "\(count) \(count == 1 ? "capture" : "captures") for later").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Capture", systemImage: "plus") { model.showInbox = true }.buttonStyle(.bordered)
            }
            if !model.artifacts.isEmpty || !model.files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently created").font(.headline)
                    ForEach(model.artifacts.prefix(3)) { artifact in
                        Button { navigation.destination = .artifact(artifact.id) } label: { Label(artifact.filename, systemImage: "doc.text").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    }
                    ForEach(model.files.filter { $0.conversationID != nil }.prefix(2)) { file in
                        Button { navigation.destination = .file(file.id) } label: { Label(file.filename, systemImage: file.icon).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedItem, onDismiss: { navigation.presentationDidDismiss() }) { item in
            NavigationStack {
                List {
                    Section { Text(item.title).font(.title2.weight(.semibold)); Text(item.sourceTitle).foregroundStyle(.secondary) }
                    if let date = item.start { LabeledContent(item.kind == "calendar" ? "Starts" : "Due", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    if let end = item.end { LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .shortened)) }
                    if !item.location.isEmpty { Text(item.location) }
                    if !item.notes.isEmpty { Text(item.notes).textSelection(.enabled) }
                    Text(item.kind == "calendar" ? "Ask the assistant to help prepare for this event or find another time. Changes appear for review." : "Ask the assistant to update or complete this reminder. Changes appear for review.").font(.footnote).foregroundStyle(.secondary)
                    Button(item.kind == "calendar" ? "Prepare for this event" : "Plan this reminder", systemImage: "text.bubble") {
                        let ref = ContextReference(kind: item.kind == "calendar" ? .calendar : .reminder, sourceID: item.id, title: item.title, conversationID: model.conversation.id, snapshot: try? item.modelValue.jsonString())
                        navigation.compose(ContextualDraftProposal(reference: ref, prompt: item.kind == "calendar" ? "Help me prepare for this event." : "Help me plan this reminder."), afterDismissal: true)
                        selectedItem = nil
                    }.disabled(model.isRunning)
                }.navigationTitle(item.kind == "calendar" ? "Event" : "Reminder").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedItem = nil } } }
            }
        }
        .task { await planning.refreshHome(settings: model.settings) }
    }
}

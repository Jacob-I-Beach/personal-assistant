import AssistantCore
import Charts
import SwiftUI

struct WorkingSurfaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    let id: UUID
    var expanded = false
    var revisionChanged: ((Int) -> Void)?
    @State private var surface: WorkSurface?
    @State private var committed: WorkSurface?
    @State private var undoValues: WorkSurface?
    @State private var saving = false
    @State private var failure: String?
    @State private var selectedChartLabel: String?
    @State private var showChartData = false
    @State private var editingInput: String?
    @State private var exactValue = ""
    @State private var inputError: String?
    private var dirty: Bool { surface?.inputValues != committed?.inputValues || surface?.selectedIDs != committed?.selectedIDs }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let surface {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: surfaceSymbol(surface)).font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                    Text(surface.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let subtitle = surface.spec["subtitle"]?.stringValue { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                content(surface)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Retry save") { save() }.disabled(saving); Button("Revert to saved") { Task { await reload() } }.disabled(saving) }
                }
                if saving { Label("Saving your changes", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary) }
                else if dirty { Text("Unsaved changes · displayed result is a preview").font(.caption).foregroundStyle(.secondary) }
                if [.scenario, .comparison, .checklist].contains(surface.kind) {
                    HStack {
                        Button("Reset inputs") { resetInputs() }.disabled(model.isRunning || saving || failure != nil)
                        if undoValues != nil { Button("Undo change") { restorePrevious() }.disabled(model.isRunning || saving || failure != nil) }
                    }.font(.subheadline)
                }
                if !expanded {
                    Button("Open full view", systemImage: "arrow.up.left.and.arrow.down.right") { navigation.destination = .surface(id, selectedRevision: surface.revision) }.font(.subheadline)
                }
                if surface.kind == .scenario { Text("Calculated on this iPhone from the displayed assumptions.").font(.caption2).foregroundStyle(.secondary) }
                else if surface.dataCallID != nil { Text("Values from the saved calculation.").font(.caption2).foregroundStyle(.secondary) }
                if surface.kind == .checklist { Text("Tap an item to track your progress.").font(.caption).foregroundStyle(.secondary) }
                if [.scenario, .comparison, .checklist].contains(surface.kind) {
                    if surface.revision > 1 { Text("Updated here · the earlier reply may use older inputs").font(.caption2).foregroundStyle(.secondary) }
                    Button {
                        let reference = ContextReference(kind: .surface, sourceID: surface.id.uuidString, title: surface.title, conversationID: surface.conversationID, revision: surface.revision,
                            localOnly: surface.containsLocalOnlyContext, health: surface.containsHealthData)
                        let prompt = "Explain these changes and update any conclusions that depend on them."
                        if navigation.destination != nil { navigation.compose(ContextualDraftProposal(reference: reference, prompt: prompt), afterDismissal: false) }
                        else { Task { await model.offerContextualDraft(reference: reference, prompt: prompt) } }
                    } label: { Label("Ask about these changes", systemImage: "arrow.turn.up.right").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).disabled(model.isRunning || saving || dirty || failure != nil)
                }
            } else if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            else { ProgressView("Opening working surface").controlSize(.small) }
        }
        .padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false) }
        .accessibilityIdentifier("working-surface")
        .task(id: "\(id)-\(model.conversation.messages.count)-\(model.isRunning)") {
            if !dirty && !saving { await reload() }
        }
        .sheet(isPresented: Binding(get: { editingInput != nil }, set: { if !$0 { editingInput = nil } })) {
            NavigationStack {
                Form {
                    if let key = editingInput, let input = surface?.inputs.first(where: { $0["id"]?.stringValue == key }) {
                        TextField(input["label"]!.stringValue!, text: $exactValue).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("scenario-exact-value")
                        Text("From \(input["min"]!.numberValue!.formatted()) to \(input["max"]!.numberValue!.formatted())").font(.caption).foregroundStyle(.secondary)
                        if let inputError { Text(inputError).foregroundStyle(.secondary) }
                    }
                }.navigationTitle("Exact value").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingInput = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Apply value") { applyExactValue() } }
                    }
            }.presentationDetents([.medium])
        }
    }
    private func surfaceSymbol(_ surface: WorkSurface) -> String {
        switch surface.kind {
        case .metrics: "number.square"
        case .chart: "chart.xyaxis.line"
        case .table: "tablecells"
        case .comparison: "rectangle.split.2x1"
        case .checklist: "checklist"
        case .timeline: "list.bullet.below.rectangle"
        case .scenario: "slider.horizontal.3"
        }
    }
    @ViewBuilder private func content(_ surface: WorkSurface) -> some View {
        switch surface.kind {
        case .metrics:
            ForEach(Array(surface.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row["label"]!.stringValue!).font(.caption).foregroundStyle(.secondary)
                    Text(cell(row["value"]!) + (row["unit"]?.stringValue.map { " " + $0 } ?? "")).font(.title2.weight(.semibold)).monospacedDigit()
                    if let detail = row["detail"]?.stringValue { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        case .chart:
            chart(surface)
            if let selectedChartLabel {
                ForEach(Array(surface.rows.filter { $0["label"]?.stringValue == selectedChartLabel }.enumerated()), id: \.offset) { _, row in
                    Text("\(selectedChartLabel) · \(row["series"]?.stringValue ?? surface.title): \(cell(row["value"]!))").font(.caption).monospacedDigit()
                }
            }
            DisclosureGroup("Data table", isExpanded: $showChartData) {
                ForEach(Array(surface.rows.enumerated()), id: \.offset) { _, row in
                    LabeledContent((row["label"]?.stringValue ?? "") + (row["series"]?.stringValue.map { " · " + $0 } ?? ""), value: cell(row["value"]!)).font(.subheadline).monospacedDigit().padding(.vertical, 4)
                }
            }
        case .table:
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow { ForEach(Array((surface.spec["columns"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, column in Text(cell(column)).fontWeight(.semibold) } }
                    Divider()
                    ForEach(Array(surface.rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.arrayValue!.enumerated()), id: \.offset) { _, value in Text(cell(value)).monospacedDigit() } }
                    }
                }.font(.subheadline).textSelection(.enabled)
            }
        case .comparison, .checklist:
            ForEach(Array(surface.rows.enumerated()), id: \.offset) { _, row in
                let key = row["id"]!.stringValue!
                Button {
                    guard var next = self.surface else { return }
                    if surface.kind == .comparison { next.selectedIDs = next.selectedIDs.contains(key) ? [] : [key] }
                    else if !next.selectedIDs.insert(key).inserted { next.selectedIDs.remove(key) }
                    self.surface = next; save()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: surface.selectedIDs.contains(key) ? "checkmark.circle.fill" : "circle").padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row["label"]!.stringValue!).font(.subheadline)
                            if let detail = row["detail"]?.stringValue { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }.foregroundStyle(.primary).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(saving || model.isRunning || failure != nil)
                    .accessibilityLabel(row["label"]!.stringValue!).accessibilityValue(surface.selectedIDs.contains(key) ? "Selected" : "Not selected")
            }
        case .timeline:
            ForEach(Array(surface.rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 10) {
                    VStack { Image(systemName: row["status"] == .string("completed") ? "checkmark.circle" : "circle"); if index < surface.rows.count - 1 { Rectangle().frame(width: 1, height: 22) } }.foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) { Text(row["label"]!.stringValue!).font(.subheadline); if let detail = row["detail"]?.stringValue { Text(detail).font(.caption).foregroundStyle(.secondary) } }
                }
            }
        case .scenario:
            ForEach(Array(surface.inputs.enumerated()), id: \.offset) { _, input in
                let key = input["id"]!.stringValue!
                VStack(spacing: 4) {
                    HStack {
                        Text(input["label"]!.stringValue!); Spacer()
                        Button((self.surface?.inputValues[key] ?? 0).formatted(.number.precision(.significantDigits(1...7)))) {
                            exactValue = (self.surface?.inputValues[key] ?? 0).formatted(.number.grouping(.never)); inputError = nil; editingInput = key
                        }.monospacedDigit().frame(minWidth: 44, minHeight: 44).accessibilityLabel("Set exact " + input["label"]!.stringValue!)
                    }.font(.subheadline).disabled(model.isRunning || saving || failure != nil)
                    Slider(value: Binding(get: { self.surface?.inputValues[key] ?? input["value"]!.numberValue! }, set: { self.surface?.inputValues[key] = $0 }), in: input["min"]!.numberValue!...input["max"]!.numberValue!, step: input["step"]!.numberValue!, onEditingChanged: { editing in if !editing { save() } })
                        .tint(.primary).disabled(model.isRunning || saving || failure != nil).accessibilityLabel(input["label"]!.stringValue!)
                }
            }
            if let expression = surface.spec["expression"], let result = try? WorkSurface.evaluate(expression, inputs: surface.inputValues) {
                Divider()
                LabeledContent(surface.spec["result_label"]?.stringValue ?? "Result", value: result.formatted(.number.precision(.significantDigits(1...8))) + (surface.spec["unit"]?.stringValue.map { " " + $0 } ?? "")).font(.headline).monospacedDigit()
            } else { Text("These inputs do not produce a finite result.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func chart(_ surface: WorkSurface) -> some View {
        Chart {
            ForEach(Array(surface.rows.enumerated()), id: \.offset) { _, row in
                let label = row["label"]!.stringValue!, value = row["value"]!.numberValue!, series = row["series"]?.stringValue ?? surface.title
                if surface.spec["style"] == .string("line") {
                    LineMark(x: .value("Category", label), y: .value("Value", value)).foregroundStyle(by: .value("Series", series)).symbol(.circle)
                } else if surface.spec["style"] == .string("area") {
                    AreaMark(x: .value("Category", label), y: .value("Value", value)).foregroundStyle(by: .value("Series", series))
                } else {
                    BarMark(x: .value("Category", label), y: .value("Value", value)).foregroundStyle(by: .value("Series", series))
                }
            }
        }.chartForegroundStyleScale(range: [Color.primary, Color.gray, Color.secondary])
            .chartXSelection(value: $selectedChartLabel)
            .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
            .frame(height: expanded ? 340 : 220)
            .accessibilityLabel(surface.title)
    }
    private func cell(_ value: JSONValue) -> String {
        switch value { case .string(let text): text; case .number(let number): number.formatted(.number.precision(.significantDigits(1...8))); case .bool(let flag): flag ? "Yes" : "No"; default: "—" }
    }
    private func save() {
        guard let value = surface, let store = model.store, !saving, value.conversationID == model.conversation.id, !model.isRunning else { return }
        guard dirty else { return }
        saving = true; failure = nil
        Task {
            defer { saving = false }
            do {
                let saved = try await store.interactWithSurface(id: value.id, conversationID: value.conversationID, expectedRevision: value.revision, selected: value.selectedIDs, inputs: value.inputValues)
                undoValues = committed; committed = saved; surface = saved; revisionChanged?(saved.revision)
            }
            catch { failure = error.localizedDescription }
        }
    }
    private func reload() async {
        guard let store else { return }
        do {
            guard let saved = try await store.surfaces(conversationID: model.conversation.id).first(where: { $0.id == id }) else { throw AssistantError.provider("This surface is no longer in the active conversation.") }
            surface = saved; committed = saved; failure = nil; undoValues = nil; revisionChanged?(saved.revision)
        } catch { failure = error.localizedDescription }
    }
    private func resetInputs() {
        guard var next = surface else { return }
        next.inputValues = Dictionary(uniqueKeysWithValues: next.inputs.map { ($0["id"]!.stringValue!, $0["value"]!.numberValue!) })
        next.selectedIDs = next.kind == .checklist ? Set(next.rows.filter { $0["checked"] == .bool(true) }.compactMap { $0["id"]?.stringValue }) : []
        surface = next; save()
    }
    private func restorePrevious() {
        guard let previous = undoValues else { return }
        surface?.inputValues = previous.inputValues; surface?.selectedIDs = previous.selectedIDs; save()
    }
    private func applyExactValue() {
        guard let key = editingInput, let input = surface?.inputs.first(where: { $0["id"]?.stringValue == key }),
              let value = try? FloatingPointFormatStyle<Double>.number.parseStrategy.parse(exactValue), value.isFinite,
              (input["min"]!.numberValue!...input["max"]!.numberValue!).contains(value) else { inputError = "Enter a number within the displayed range."; return }
        surface?.inputValues[key] = value; editingInput = nil; save()
    }
}

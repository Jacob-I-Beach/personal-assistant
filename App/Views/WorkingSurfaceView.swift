import AssistantCore
import Charts
import SwiftUI

struct WorkingSurfaceView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var surface: WorkSurface?
    @State private var saving = false
    @State private var failure: String?
    @State private var selectedChartLabel: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let surface {
                Text(surface.title).font(.headline)
                if let subtitle = surface.spec["subtitle"]?.stringValue { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                content(surface)
                if let failure { Label(failure, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary) }
                if saving { Text("Saving changes…").font(.caption2).foregroundStyle(.secondary) }
                if surface.kind == .scenario { Text("Calculated on this iPhone from the displayed assumptions.").font(.caption2).foregroundStyle(.secondary) }
                else if surface.dataCallID != nil { Text("Values from the saved JavaScript calculation.").font(.caption2).foregroundStyle(.secondary) }
                if surface.kind == .checklist { Text("Your checkmarks track progress; they do not confirm an external action.").font(.caption2).foregroundStyle(.secondary) }
                if [.scenario, .comparison, .checklist].contains(surface.kind) {
                    if surface.revision > 1 { Text("Updated here · the earlier reply may use older inputs").font(.caption2).foregroundStyle(.secondary) }
                    Button {
                        let request = "Explain the latest changes to “\(surface.title)” and update any conclusions that depend on them."
                        if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachedCaptureIDs.isEmpty && model.attachedFileIDs.isEmpty { model.send(request) }
                        else { model.draft += (model.draft.isEmpty ? "" : "\n\n") + request }
                    } label: { Label("Ask about these changes", systemImage: "arrow.turn.up.right").font(.subheadline.weight(.medium)) }
                        .buttonStyle(.bordered).disabled(model.isRunning || saving)
                }
            } else if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            else { ProgressView("Opening working surface").controlSize(.small) }
        }
        .padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("working-surface")
        .task(id: "\(id)-\(model.conversation.messages.count)-\(model.isRunning)") {
            do { surface = try await model.store?.surfaces(conversationID: model.conversation.id).first(where: { $0.id == id }); if surface == nil { failure = "This surface is no longer in the active conversation." } }
            catch { failure = error.localizedDescription }
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
            if let selectedChartLabel, let row = surface.rows.first(where: { $0["label"]?.stringValue == selectedChartLabel }) {
                Text("\(selectedChartLabel): \(cell(row["value"]!))").font(.caption).monospacedDigit()
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
                }.buttonStyle(.plain).disabled(saving || model.isRunning)
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
                    HStack { Text(input["label"]!.stringValue!); Spacer(); Text((self.surface?.inputValues[key] ?? 0).formatted(.number.precision(.significantDigits(1...7)))).monospacedDigit() }.font(.subheadline)
                    Slider(value: Binding(get: { self.surface?.inputValues[key] ?? input["value"]!.numberValue! }, set: { self.surface?.inputValues[key] = $0 }), in: input["min"]!.numberValue!...input["max"]!.numberValue!, step: input["step"]!.numberValue!, onEditingChanged: { editing in if !editing { save() } })
                        .tint(.primary).disabled(model.isRunning || saving).accessibilityLabel(input["label"]!.stringValue!)
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
            .frame(height: 220)
            .accessibilityLabel(surface.title)
    }
    private func cell(_ value: JSONValue) -> String {
        switch value { case .string(let text): text; case .number(let number): number.formatted(.number.precision(.significantDigits(1...8))); case .bool(let flag): flag ? "Yes" : "No"; default: "—" }
    }
    private func save() {
        guard let value = surface, let store = model.store, !saving else { return }
        saving = true; failure = nil
        Task {
            defer { saving = false }
            do { surface = try await store.interactWithSurface(id: value.id, conversationID: value.conversationID, expectedRevision: value.revision, selected: value.selectedIDs, inputs: value.inputValues) }
            catch { failure = error.localizedDescription }
        }
    }
}

import AssistantCore
import SwiftUI

/// The brain button's single place for per-model response preferences.
struct ReasoningEffortView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var focusContext = false
    @State private var effort: ReasoningEffort?
    @State private var context: Int?
    @State private var memoryGiB = 8
    private var plan: ModelContextBudget? {
        var draft = model.settings
        draft.contextTokensByModel[draft.contextPreferenceKey] = context
        return model.contextBudget(for: draft)
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(model.modelTitle).font(.headline)
                        Text(model.settings.choice == .localMLX ? "Context adapts to the memory this iPhone makes available." : "Your choices are remembered for this model.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !model.supportedReasoningEfforts.isEmpty {
                        Section("Thinking") {
                            ForEach(model.supportedReasoningEfforts) { value in
                                Button { effort = value; AppFeedback.play(.selection) } label: {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(value.title).fontWeight(.medium)
                                            Text(value.summary).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if effort == value { Image(systemName: "checkmark") }
                                    }.padding(.vertical, 3).contentShape(Rectangle())
                                }.foregroundStyle(.primary).buttonStyle(QuietPressStyle())
                            }
                        }
                    }
                    if let plan {
                        Section {
                            choice("Automatic", tokens: nil)
                            ForEach(plan.presets, id: \.self) { value in choice(value.formatted() + " tokens", tokens: value) }
                        } header: { Text("Working context").id("context") } footer: {
                            Text("How much earlier conversation and tool output to use. Your full chat stays saved at every setting.")
                        }
                        Section {
                            LabeledContent("Total model capacity", value: plan.modelWindow.formatted() + " tokens")
                            LabeledContent("Room for the reply", value: plan.outputReserve.formatted() + " tokens")
                            Text(plan.limitSource).font(.caption).foregroundStyle(.secondary)
                            Text("Reasoning shares the reply allowance. Images and tools also use context. The connection enforces the final limit.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if model.settings.choice == .localMLX {
                        let local = model.localContextBudget(memoryGiB: memoryGiB, tokens: context)
                        Section {
                            choice("Automatic", tokens: nil)
                            if local.fits {
                                ForEach(local.presets, id: \.self) { value in choice(value.formatted() + " tokens", tokens: value) }
                                LabeledContent("Estimated working context", value: local.selectedContextTokens.formatted() + " tokens")
                            } else {
                                Label("More memory headroom needed", systemImage: "memorychip")
                                Text("The runtime cannot fit at this moment. Your download is kept; this is separate from the size of your message.").font(.caption).foregroundStyle(.secondary)
                            }
                        } header: { Text("Working context").id("context") } footer: {
                            Text("Uses the model's compressed attention cache. These are estimated fitting sizes; actual speed and sustained memory use need measurement on this iPhone.")
                        }
                        Section {
                            DisclosureGroup("Memory settings") {
                                Picker("Usage ceiling", selection: $memoryGiB) {
                                    Text("4 GB").tag(4); Text("6 GB").tag(6); Text("8 GB").tag(8)
                                }
                                LabeledContent("iOS headroom", value: ByteCountFormatter.string(fromByteCount: model.localMemoryHeadroom, countStyle: .memory))
                                LabeledContent("Planned working budget", value: ByteCountFormatter.string(fromByteCount: local.workingBytes, countStyle: .memory))
                                Text("This ceiling does not reserve memory or change iOS's allowance. The runtime adapts again after loading; a larger signing allowance must be granted by the system.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Section("Working context") {
                            Text(model.settings.choice == .appleOnDevice ? "Apple sets this model's context window. The app keeps a compact working conversation, loads tool details as needed, and preserves the full chat." : "Apple manages this cloud model's context window. The full chat and completed tool results stay saved.").foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear {
                    effort = model.selectedReasoningEffort
                    memoryGiB = model.settings.localMemoryGiB
                    context = model.settings.contextTokensByModel[model.settings.contextPreferenceKey].map { _ in model.contextBudget(for: model.settings)?.selectedInputTokens ?? 128_000 }
                    if model.settings.choice == .localMLX { context = model.settings.localContextTokens }
                    if focusContext { proxy.scrollTo("context", anchor: .top) }
                }
                .onChange(of: model.settings.contextPreferenceKey) { _, _ in
                    effort = model.selectedReasoningEffort
                    context = model.settings.contextTokensByModel[model.settings.contextPreferenceKey].map { _ in model.contextBudget(for: model.settings)?.selectedInputTokens ?? 128_000 }
                }
                .onChange(of: plan?.maximumInputTokens) { _, maximum in
                    if let maximum, let context, context > maximum { self.context = maximum }
                }
            }
            .navigationTitle("Response settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") {
                    var next = model.settings
                    next.contextTokensByModel[next.contextPreferenceKey] = context
                    if next.choice == .localMLX { next.localMemoryGiB = memoryGiB; next.localContextTokens = context }
                    if let effort, model.supportedReasoningEfforts.contains(effort) { next.reasoningByModel[next.contextModelID] = effort.rawValue }
                    do { try model.saveSettings(next); AppFeedback.play(.saved); dismiss() }
                    catch { model.errorMessage = error.localizedDescription }
                }.disabled(model.isRunning) }
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func choice(_ title: String, tokens: Int?) -> some View {
        Button { context = tokens; AppFeedback.play(.selection) } label: {
            HStack { Text(title); Spacer(); if context == tokens { Image(systemName: "checkmark") } }.contentShape(Rectangle())
        }.foregroundStyle(.primary).buttonStyle(QuietPressStyle())
    }
}

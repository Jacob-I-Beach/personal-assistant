import AssistantCore
import SwiftUI

struct WelcomeWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var weather = HomeWeatherService()
    @State private var name: String?
    @State private var showContext = false
    @State private var showMemory = false
    let camera: () -> Void
    let files: () -> Void
    let create: () -> Void
    let voice: () -> Void
    private var refreshID: String { "\(scenePhase):\(model.contextRefresh):\(model.settings.localOnly):\(model.settings.locationContextEnabled):\(model.settings.weatherFollowsLocation):\(model.settings.weatherPlace?.id ?? "")" }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(HomeGreeting.title(at: context.date, name: name, weather: weather.weather,
                                            unfinishedCount: model.unfinishedReplies.count, needsAttention: !model.pendingQuestions.isEmpty))
                        .font(.system(.largeTitle, weight: .semibold)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("home-greeting")
                    Text(HomeGreeting.subtitle(weather: weather.weather, unfinishedCount: model.unfinishedReplies.count, at: context.date)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let value = weather.weather, value.isFresh(at: context.date) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: value.symbol)
                            Text(Measurement(value: value.celsius, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))))
                            Text(value.condition + " · " + value.place.name).lineLimit(1)
                        }.font(.footnote).foregroundStyle(.secondary).padding(.top, 3)
                        HStack(spacing: 4) {
                            Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                            Text("· Observed \(value.observedAt.formatted(date: .omitted, time: .shortened))")
                        }.font(.caption2).foregroundStyle(.secondary)
                        Text("Checked \(value.retrievedAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                        if let status = weather.status { Text(status).font(.caption2).foregroundStyle(.secondary) }
                    } else if let status = weather.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if model.accounts.allSatisfy({ !$0.isConnected }) {
                VStack(alignment: .leading, spacing: 10) {
                    Button { model.connectChatGPT() } label: {
                        HStack { Text(model.isConnecting ? "Connecting…" : "Continue with ChatGPT").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }.padding(8).foregroundStyle(Color(uiColor: .systemBackground))
                    }.buttonStyle(.borderedProminent).tint(Color.primary).disabled(model.isConnecting)
                    Button("Choose an on-device model") { model.showModels = true }.font(.footnote).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 12) {
                entry("See & explore", subtitle: "Camera and depth", icon: "viewfinder", action: camera)
                entry("Work with files", subtitle: "Open a document", icon: "doc.text", action: files)
                entry("Make something", subtitle: "Start with your idea", icon: "square.and.pencil", action: create)
                entry("Talk it through", subtitle: "Dictate a thought", icon: "waveform", action: voice)
            }
            let resumable = model.unfinishedReplies.filter { work in !model.pendingQuestions.contains { $0.turnID == work.id } }
            if !resumable.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to continue").font(.subheadline.weight(.semibold))
                    ForEach(resumable.prefix(2)) { SavedWorkCard(work: $0) }
                }
            }
            TodayOverviewView(planning: model.planning)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your workspace").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Open Library", systemImage: "arrow.up.right") { navigation.showLibrary = true }.labelStyle(.titleOnly).font(.caption)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { shortcuts }
                    VStack(alignment: .leading, spacing: 16) { shortcuts }
                }
            }
        }.padding(.top, 34).padding(.bottom, 24)
            .sheet(isPresented: $showContext) { HomeContextSettingsView() }
            .sheet(isPresented: $showMemory, onDismiss: { Task { await readName() } }) {
                NavigationStack { MemoryView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMemory = false } } } }
            }
            .task(id: refreshID) {
                guard scenePhase == .active else { return }
                await readName()
                var lastPlanningRefresh = Date.distantPast
                while !Task.isCancelled {
                    await weather.refresh(model: model)
                    if Date().timeIntervalSince(lastPlanningRefresh) >= 300 {
                        await model.planning.refreshHome(settings: model.settings)
                        lastPlanningRefresh = Date()
                    }
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
    }
    @ViewBuilder private var shortcuts: some View {
        Button("Memory", systemImage: "brain.head.profile") { showMemory = true }
        Button("Inbox", systemImage: "tray") { model.showInbox = true }
        Button("Connections", systemImage: "point.3.connected.trianglepath.dotted") { navigation.showConnections = true }
    }
    private func entry(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private func readName() async { name = HomeGreeting.name(from: (try? await model.store?.memories()) ?? []) }
}

struct CreationBriefView: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let use: (String) -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("What would you like to make?").font(.title2.weight(.semibold))
                Text("A document, a chart, a calculation, a small tool—describe the result you want. Your words become the draft.").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text).padding(8).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Creation brief")
                Text("You can add source files or images before sending. Generated files stay in your Library.").font(.caption).foregroundStyle(.secondary)
                Button { use(text); dismiss() } label: { Text("Use this brief").frame(maxWidth: .infinity).padding(7) }
                    .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(uiColor: .systemBackground))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(24).navigationTitle("Create").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

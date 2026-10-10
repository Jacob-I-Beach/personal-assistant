import AssistantCore
import SwiftUI

struct DeviceAccessView: View {
    @State private var snapshot: JSONValue = .null
    var body: some View {
        List {
            Section("This device") {
                LabeledContent("Hardware identifier", value: snapshot["model_identifier"]?.stringValue ?? "—")
                LabeledContent("Software", value: snapshot["os"]?.stringValue ?? "—")
                LabeledContent("Physical memory", value: bytes("physical_memory_bytes"))
                LabeledContent("Available to this app", value: bytes("currently_available_process_memory_bytes"))
                LabeledContent("Free storage", value: bytes("free_storage_bytes"))
                LabeledContent("Thermal state", value: snapshot["thermal_state"]?.stringValue?.capitalized ?? "—")
                Text("A current snapshot, not a performance rating. iOS can change memory availability while the app is running.").font(.caption).foregroundStyle(.secondary)
                Button("Refresh device snapshot") { snapshot = DeviceContext.snapshot() }
            }
            Section("Assistant capabilities") {
                capability("Web research", "ChatGPT account models can use web search when supported by your model and account policy. Answers include source links.", "globe")
                capability("Code execution", "JavaScript runs on the phone in an isolated, offline engine. It can compute results and create text files. Web research and native device actions are separate tools.", "curlybraces")
                capability("Documents", "Read attached files, search permitted app content, create editable text files and real PDFs, and share originals through iOS.", "doc.text")
                capability("Camera & depth", "Attach a camera capture or photo. The assistant receives the selected image and can read saved OCR and available depth observations. It has no unattended live camera feed.", "viewfinder")
                capability("Location", "One foreground fix after you review the purpose and selected model. Accuracy and capture time accompany the coordinates.", "location")
                capability("Calendar, Maps & Phone", "Prepare a calendar event for your review, open a place in Maps, or hand an approved number to the system dialer.", "calendar")
                capability("Messages", "Prepare a message in Apple's composer. You review recipients and press Send. Existing message history is not accessible.", "message")
            }
            Section("Shortcuts & devices") {
                Text("Use “Ask Personal Assistant” in Shortcuts to open a request with your selected model. A Shortcut can be connected to an Action Button or personal automation where iOS allows it. Account-sharing prompts still apply.")
                Text("Watch requests and Health summaries have dedicated surfaces. This iPhone-only installation still needs a compatible signing route before the Watch companion and HealthKit can be enabled.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("This app operates inside iOS's permission system. It cannot browse other apps' private storage, read all notifications or call history, change arbitrary system settings, or run a model continuously in the background.").font(.footnote).foregroundStyle(.secondary)
                Button("Open this app's iPhone settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }.navigationTitle("Tools & device").navigationBarTitleDisplayMode(.inline)
            .task { snapshot = DeviceContext.snapshot() }
    }
    private func bytes(_ field: String) -> String { snapshot[field]?.numberValue.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—" }
    private func capability(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

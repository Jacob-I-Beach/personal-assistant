import AssistantCore
import PhotosUI
import SwiftUI

struct TaskQuestionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let questionID: UUID
    @State private var question: TaskQuestion?
    @State private var answer = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var captureID: UUID?
    @State private var showCamera = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let question {
                        Label("One thing to finish this task", systemImage: "bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
                        Text(question.title).font(.title2.weight(.semibold))
                        if !question.detail.isEmpty { Text(question.detail).foregroundStyle(.secondary) }
                        ForEach(question.choices, id: \.self) { choice in
                            Button { answer = choice } label: { HStack { Text(choice); Spacer(); Image(systemName: answer == choice ? "checkmark.circle.fill" : "circle") }.padding(12).frame(maxWidth: .infinity, alignment: .leading) }
                                .buttonStyle(.plain).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        TextField(question.kind == .measurement ? "Your measurement, including units" : "Your answer", text: $answer, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("question-answer")
                        if question.kind == .photo {
                            HStack {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose photo", systemImage: "photo") }
                                Button("Camera", systemImage: "camera") { showCamera = true }
                            }.buttonStyle(.bordered)
                            if let captureID { CaptureThumbnail(id: captureID).frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 14)) }
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        Button {
                            busy = true
                            Task { defer { busy = false }; do { try await model.submitQuestion(questionID, text: answer, captureIDs: captureID.map { [$0] } ?? [], skip: false); dismiss() } catch { self.error = error.localizedDescription } }
                        } label: { Text(busy ? "Saving…" : "Answer and continue").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).disabled(busy || (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && captureID == nil))
                        Button("Skip this question") {
                            Task { do { try await model.submitQuestion(questionID, text: "", captureIDs: [], skip: true); dismiss() } catch { self.error = error.localizedDescription } }
                        }.frame(maxWidth: .infinity).disabled(busy)
                    } else if let error { Text(error).foregroundStyle(.secondary) }
                    else { ProgressView() }
                }.padding(24)
            }.navigationTitle("Needs you").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { if model.isRunning { model.deferQuestion() }; dismiss() } } }
                .task { do { question = try await model.store?.question(questionID) } catch { self.error = error.localizedDescription } }
                .sheet(isPresented: $showCamera) { SceneCaptureSheet { capture, jpeg in
                    try await model.store?.saveCapture(capture, jpeg: jpeg); captureID = capture.id
                } }
                .onChange(of: selectedPhoto) { _, value in
                    guard let value else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do {
                            guard let data = try await value.loadTransferable(type: Data.self) else { throw AssistantError.invalidCapture("The photo could not be opened.") }
                            let (capture, jpeg) = try await CaptureProcessor.shared.importPhoto(data)
                            try await model.store?.saveCapture(capture, jpeg: jpeg); captureID = capture.id
                        } catch { self.error = error.localizedDescription }
                    }
                }
        }.presentationDetents([.large])
    }
}

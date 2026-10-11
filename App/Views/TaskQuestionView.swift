import AssistantCore
import PhotosUI
import SwiftUI

struct TaskQuestionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let questionID: UUID
    @State private var question: TaskQuestion?
    @State private var answer = ""
    @State private var selectedChoice: String?
    @State private var detent: PresentationDetent = .medium
    private var submittedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedChoice ?? "" : answer }
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
                            Button { selectedChoice = choice; answer = ""; AppFeedback.play(.selection) } label: { HStack { Text(choice); Spacer(); Image(systemName: selectedChoice == choice ? "checkmark.circle.fill" : "circle").accessibilityHidden(true) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                                .buttonStyle(QuietPressStyle()).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityAddTraits(selectedChoice == choice ? .isSelected : [])
                        }
                        TextField(question.kind == .measurement ? "Your measurement, including units" : question.choices.isEmpty ? "Your answer" : "Something else…", text: $answer, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("question-answer")
                            .onChange(of: answer) { _, value in if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selectedChoice = nil } }
                        if question.kind == .photo {
                            HStack {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose photo", systemImage: "photo") }
                                Button("Camera", systemImage: "camera") { showCamera = true }
                            }.buttonStyle(.bordered)
                            if let captureID { CaptureThumbnail(id: captureID).frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 14)) }
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    } else if let error { Text(error).foregroundStyle(.secondary) }
                    else { ProgressView() }
                }.padding(24)
            }.navigationTitle("Needs you").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if question != nil {
                        VStack(spacing: 12) {
                            Button {
                                busy = true
                                Task { defer { busy = false }; do { try await model.submitQuestion(questionID, text: submittedAnswer, captureIDs: captureID.map { [$0] } ?? [], skip: false) } catch { self.error = error.localizedDescription } }
                            } label: {
                                Text(busy ? "Saving…" : "Answer and continue").fontWeight(.semibold).frame(maxWidth: .infinity).padding(8).foregroundStyle(Color(uiColor: .systemBackground))
                            }.buttonStyle(.borderedProminent).tint(.primary).disabled(busy || (submittedAnswer.isEmpty && captureID == nil))
                            Button("Skip this question") {
                                Task { do { try await model.submitQuestion(questionID, text: "", captureIDs: [], skip: true) } catch { self.error = error.localizedDescription } }
                            }.frame(maxWidth: .infinity).disabled(busy)
                        }.padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { if model.isRunning { model.deferQuestion() } else { model.nativeAction = nil } } } }
                .task { if typeSize.isAccessibilitySize { detent = .large }; do { question = try await model.store?.question(questionID) } catch { self.error = error.localizedDescription } }
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
        }.presentationDetents([.medium, .large], selection: $detent).presentationDragIndicator(.visible)
    }
}

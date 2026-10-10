import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: UIViewControllerRepresentable {
    let complete: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator; picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (URL?) -> Void
        init(complete: @escaping (URL?) -> Void) { self.complete = complete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { complete(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete(nil) }
    }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    let complete: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (String) -> Void
        init(complete: @escaping (String) -> Void) { self.complete = complete }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { complete(urls.isEmpty ? "cancelled" : "completed") }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete("cancelled") }
    }
}

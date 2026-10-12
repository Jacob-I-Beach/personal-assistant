import AssistantCore
import Foundation

/// Downloads the exact pinned manifest directly to disk. Completed files and
/// URLSession resume data survive a retry; no multi-gigabyte Data buffer exists.
enum ModelPackageDownload {
    static func download(repository: String, revision: String, root: URL,
                         files: [LocalModelCatalogEntry.File], allowCellular: Bool,
                         host: URL = URL(string: "https://huggingface.co")!,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard repository.split(separator: "/").count == 2,
              repository.allSatisfy({ $0.isLetter || $0.isNumber || "-_/ .".contains($0) }) && !repository.contains(".."),
              revision.count >= 40, revision.allSatisfy(\.isHexDigit), !files.isEmpty else {
            throw AssistantError.provider("This model needs a valid pinned download manifest.")
        }
        let directory = root.appendingPathComponent("packages").appendingPathComponent(repository.replacingOccurrences(of: "/", with: "--") + "-" + revision)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = files.reduce(Int64(0)) { $0 + $1.bytes }
        var completed: Int64 = 0
        for file in files.sorted(by: { $0.bytes < $1.bytes }) {
            try Task.checkCancellation()
            guard !file.name.contains(".."), !file.name.hasPrefix("/"), file.bytes > 0 else { throw AssistantError.provider("Invalid model file manifest.") }
            let target = directory.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            if size != file.bytes {
                let completedBeforeFile = completed
                let address = host.appendingPathComponent(repository).appendingPathComponent("resolve").appendingPathComponent(revision).appendingPathComponent(file.name)
                let download = ModelFileDownload(destination: target, expectedBytes: file.bytes, allowCellular: allowCellular) { bytes in
                    progress(min(0.99, Double(completedBeforeFile + bytes) / Double(max(1, total))))
                }
                try await download.fetch(address)
            }
            completed += file.bytes
            progress(min(0.99, Double(completed) / Double(max(1, total))))
        }
        return directory
    }
}

private final class ModelFileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let expectedBytes: Int64
    private let allowCellular: Bool
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var finished = false
    private var lastUpdate = Date.distantPast
    private var resumeURL: URL { destination.appendingPathExtension("resume") }
    init(destination: URL, expectedBytes: Int64, allowCellular: Bool, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination; self.expectedBytes = expectedBytes; self.allowCellular = allowCellular; self.progress = progress
    }
    func fetch(_ url: URL) async throws {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.start(url, continuation: continuation)
            }
        }, onCancel: { self.cancel() })
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Void, any Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = allowCellular
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 86_400
        configuration.urlCache = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task: URLSessionDownloadTask
        if let resume = try? Data(contentsOf: resumeURL), !resume.isEmpty {
            task = session.downloadTask(withResumeData: resume)
        } else {
            var request = URLRequest(url: url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            task = session.downloadTask(with: request)
        }
        self.task = task; lock.unlock(); task.resume()
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        guard let task else { return }
        task.cancel { [weak self] data in
            guard let self else { return }
            if let data { try? data.write(to: self.resumeURL, options: .atomic) }
            self.finish(CancellationError())
        }
    }
    private func finish(_ error: (any Error)?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let value = continuation; continuation = nil; let session = session
        lock.unlock()
        session?.finishTasksAndInvalidate()
        if let error { value?.resume(throwing: error) } else { value?.resume() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedBytes { downloadTask.cancel(); finish(AssistantError.provider("The server returned a different model file. Retry the pinned download.")); return }
        let now = Date()
        if now.timeIntervalSince(lastUpdate) > 0.15 || totalBytesWritten == expectedBytes {
            lastUpdate = now; progress(totalBytesWritten)
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, [200, 206].contains(response.statusCode) else {
                throw AssistantError.provider("The model host did not provide the file. Retry the download when the connection is available.")
            }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard Int64(size ?? 0) == expectedBytes else { throw AssistantError.provider("The downloaded file is incomplete. Retry to finish the model package.") }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            try? FileManager.default.removeItem(at: resumeURL)
            progress(expectedBytes); finish(nil)
        } catch { try? FileManager.default.removeItem(at: resumeURL); finish(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { return } // cancel's callback saves resume data first.
        let failure = error as NSError
        if let data = failure.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? data.write(to: resumeURL, options: .atomic) }
        else { try? FileManager.default.removeItem(at: resumeURL) }
        let network = !allowCellular && [NSURLErrorDataNotAllowed, NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff].contains(failure.code)
        finish(AssistantError.provider(network
            ? "Downloads are set to Wi-Fi. Connect to Wi-Fi or enable Allow cellular downloads in Models, then tap Download again. Completed files are kept."
            : "The model download paused: \(failure.localizedDescription) Tap Download again to resume; completed files are kept."))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

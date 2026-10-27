import Foundation
import CryptoKit
import Observation

struct ModelArtifact: Sendable {
    let url: URL
    let size: Int64
    let sha256: String
    static let ming = ModelArtifact(
        url: URL(string: "https://huggingface.co/audio-cpp/Ming-3.0-TTS-0.5B-GGUF/resolve/2eb8d37c7f10672e69c8aa33091baa04c461b66c/ming-3.0-tts-0.5b-bf16.gguf")!,
        size: 2_998_284_288,
        sha256: "43f108a4e6bb54af13071d0cb345a094e0b011b3b8318d8fb2c61753733f5312")
}

// URLSessionDownloadTask uses an OS temporary file. This data delegate instead
// writes chunks directly to the selected volume, including when resuming.
final class ModelTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let artifact: ModelArtifact
    private let partial: URL
    private let destination: URL
    private let onProgress: @Sendable (Int64, Bool) -> Void
    private let completion: @Sendable (Result<URL, Error>) -> Void
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var offset: Int64 = 0
    private var failure: Error?
    private var lastProgress = Date.distantPast
    private var destinationExists: Bool = false
    init(artifact: ModelArtifact, destination: URL, progress: @escaping @Sendable (Int64, Bool) -> Void, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.artifact = artifact; self.destination = destination
        self.partial = destination.appendingPathExtension("partial")
        self.onProgress = progress; self.completion = completion
    }
    func start() {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 12 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            destinationExists = FileManager.default.fileExists(atPath: destination.path)
            if destinationExists {
                // A full existing model is verified in place, never overwritten.
                queue.addOperation { self.verify(existing: true) }
                return
            }
            offset = ((try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber)?.int64Value ?? 0
            if offset > artifact.size { throw StudioError.message("The partial download is larger than expected. Choose another folder or remove that partial file.") }
            received = offset
            if offset == artifact.size { queue.addOperation { self.verify(existing: false) }; return }
            if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
            handle = try FileHandle(forWritingTo: partial)
            try handle?.seekToEnd()
            var request = URLRequest(url: artifact.url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
            onProgress(received, false)
            task = session.dataTask(with: request)
            task?.resume()
        } catch { finish(.failure(error)) }
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, [200,206].contains(response.statusCode) else {
            failure = StudioError.message("The model host returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). Try again later.")
            completionHandler(.cancel); return
        }
        do {
            if response.statusCode == 206 {
                guard response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(offset)-") == true else { throw StudioError.message("The server returned an unexpected resume range.") }
            } else if offset > 0 {
                try handle?.truncate(atOffset: 0); try handle?.seek(toOffset: 0)
                offset = 0; received = 0
            }
            completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard received + Int64(data.count) <= artifact.size else { throw StudioError.message("The download is larger than the pinned model. Installation stopped.") }
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            if Date().timeIntervalSince(lastProgress) > 0.15 { onProgress(received, false); lastProgress = Date() }
        } catch { failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close(); handle = nil
        if let error = failure ?? error { finish(.failure(error)); return }
        verify(existing: false)
    }
    private func verify(existing: Bool) {
        let file = existing ? destination : partial
        do {
            let size = ((try FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0
            guard size == artifact.size else { throw StudioError.message("Download incomplete. Choose Download model again to resume.") }
            onProgress(size, true)
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            var hash = SHA256()
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == artifact.sha256 else {
                if !existing { try? FileManager.default.removeItem(at: partial) }
                throw StudioError.message("Checksum mismatch. The model was not installed. \(existing ? "Your existing file was preserved." : "Retry to download a fresh copy.")")
            }
            if !existing { try FileManager.default.moveItem(at: partial, to: destination) }
            finish(.success(destination))
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<URL, Error>) {
        try? handle?.close(); handle = nil
        session?.finishTasksAndInvalidate()
        completion(result)
    }
}

@MainActor @Observable final class ModelInstaller {
    var busy = false
    var verifying = false
    var bytes: Int64 = 0
    var message = ""
    var error: String?
    @ObservationIgnored private var transfer: ModelTransfer?
    var progress: Double { min(1, Double(bytes) / Double(ModelArtifact.ming.size)) }
    func download(to destination: URL, completed: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true; verifying = false; error = nil; message = "Connecting to model host…"
        let worker = ModelTransfer(artifact: .ming, destination: destination, progress: { [weak self] count, checking in
            Task { @MainActor in
                self?.bytes = count; self?.verifying = checking
                self?.message = checking ? "Verifying model checksum…" : "Downloading model — \(ByteCountFormatter.string(fromByteCount: count, countStyle: .file)) of 3 GB"
            }
        }, completion: { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false; self.transfer = nil
                switch result {
                case .success: self.message = "Model installed and verified."; completed()
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorCancelled { self.message = "Download paused. Resume whenever you’re ready." }
                    else { self.error = error.localizedDescription; self.message = "Installation did not finish." }
                }
            }
        })
        transfer = worker
        worker.start()
    }
    func cancel() { if !verifying { transfer?.cancel() } }
}

import Foundation

/// Serializes settings snapshots away from the main thread. A slow external-volume
/// write must never stop controls, playback, or the recording UI from responding.
final class SettingsWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ravenvo.settings", qos: .utility)
    private let write: @Sendable (Data, URL) throws -> Void
    init(write: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }) { self.write = write }

    func submit(_ files: [(Data, URL)], completion: @escaping @MainActor @Sendable (String?) -> Void) {
        queue.async { [write] in
            let message: String?
            do {
                for (data, url) in files { try write(data, url) }
                message = nil
            } catch { message = error.localizedDescription }
            Task { @MainActor in completion(message) }
        }
    }
    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}

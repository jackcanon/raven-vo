import Foundation

@main struct SettingsWriterChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("draft.json")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let slow = SettingsWriter { data, url in
            entered.signal()
            release.wait()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        var completed = false
        slow.submit([(Data("saved after delay".utf8), target)]) { error in
            precondition(error == nil); completed = true
        }
        let didEnter = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: entered.wait(timeout: .now() + 2) == .success) }
        }
        precondition(didEnter)
        // The same actor driving the UI must keep making progress while disk I/O stalls.
        var ticks = 0
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)); ticks += 1 }
        precondition(ticks == 10 && !completed)
        release.signal()
        await slow.flush()
        let delayed = try String(contentsOf: target, encoding: .utf8)
        precondition(delayed == "saved after delay")
        let writer = SettingsWriter()
        for index in 0..<50 { writer.submit([(Data("snapshot-\(index)".utf8), target)]) { _ in } }
        await writer.flush()
        let last = try String(contentsOf: target, encoding: .utf8)
        precondition(last == "snapshot-49")
        var failure: String?
        let failing = SettingsWriter { _, _ in throw NSError(domain: "SettingsWriterTest", code: 1) }
        failing.submit([(Data(), target)]) { failure = $0 }
        await failing.flush()
        for _ in 0..<50 { if failure != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(failure != nil)
        try FileManager.default.removeItem(at: root)
        print("SETTINGS_WRITER_CHECKS_PASSED: UI actor responsive during blocked disk write, ordered snapshots, flush, errors")
    }
}

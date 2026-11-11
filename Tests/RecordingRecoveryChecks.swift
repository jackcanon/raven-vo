import Foundation
import AVFoundation

@main struct RecordingRecoveryChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("interrupted")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = NarrationRecordingRecovery(started: Date(), deviceName: "Test input", script: "Preserved script", localeID: "en-US", folder: folder)
        try marker.write()
        let pending = try NarrationRecordingRecovery.pending(in: root)
        precondition(pending.count == 1 && pending[0].script == marker.script)
        // A moved project must use its discovered location, never serialized paths.
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: folder, to: moved)
        let relocated = try NarrationRecordingRecovery.pending(in: root)
        precondition(relocated.count == 1 && relocated[0].folder.standardizedFileURL.path == moved.standardizedFileURL.path)
        let source = moved.appendingPathComponent("original.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let block = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            block.frameLength = 48000
            for i in 0..<48000 { block.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000)) * 0.2 }
            for _ in 0..<600 { try file.write(from: block) }
        }
        let originalSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let edit = NarrationEdit(sourceName: "original.wav", duration: 600,
            kept: [.init(start: 0, end: 200), .init(start: 200.1, end: 400), .init(start: 400.1, end: 600)], joinCrossfadeMS: 5)
        let output = moved.appendingPathComponent("long-edit.wav")
        try NarrationRenderer.render(source: source, edit: edit, destination: output)
        let rendered = try AVAudioFile(forReading: output)
        precondition(rendered.length == 28_789_920)
        precondition(abs(Double(rendered.length) / 48000 - edit.outputDuration) < 0.000001)
        precondition(trySize(source) == originalSize)
        let metadata = moved.appendingPathComponent("project.ravenvo.json")
        try JSONEncoder().encode(edit).write(to: metadata, options: .atomic)
        let reopened = try JSONDecoder().decode(NarrationEdit.self, from: Data(contentsOf: metadata))
        precondition(reopened == edit)
        try relocated[0].complete()
        precondition(tryPending(root).isEmpty)
        precondition(FileManager.default.fileExists(atPath: source.path))
        // Incomplete/corrupt markers do not prevent other projects being scanned.
        try Data("invalid".utf8).write(to: moved.appendingPathComponent(NarrationRecordingRecovery.markerName))
        precondition(tryPending(root).isEmpty)
        var malicious = marker; malicious.folder = moved; malicious.audioName = "../outside.wav"
        do { try malicious.write(); fatalError("Unsafe media path accepted") } catch { }
        try FileManager.default.removeItem(at: root)
        print("PASS: recovery journal, moved-folder safety, source retention, corrupt markers; ten-minute render, exact frames, crossfades and project reopen")
    }
    static func tryPending(_ root: URL) -> [NarrationRecordingRecovery] { (try? NarrationRecordingRecovery.pending(in: root)) ?? [] }
    static func trySize(_ url: URL) -> Int? { try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize }
}

import Foundation
import AVFoundation

@main struct RecordingRecoveryModelChecks {
    @MainActor static func main() async throws {
        guard StoragePreference.mounted, let storage = StoragePreference.folder else { fatalError("Selected external storage must be mounted") }
        let folder = storage.appendingPathComponent("studio").appendingPathComponent("recovery-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("original.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            buffer.floatChannelData![0].initialize(repeating: 0.1, count: 48000)
            try file.write(from: buffer)
        }
        let original = try Data(contentsOf: audio)
        let item = NarrationRecordingRecovery(started: Date(), deviceName: "Synthetic test", script: "Recovery test script", localeID: "en-US", folder: folder)
        try item.write()
        let model = NarrationStudioModel()
        model.findInterruptedRecordings()
        precondition(model.pendingRecordings.contains { $0.folder.path == folder.path })
        model.recoverRecording(item)
        for _ in 0..<500 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard let recovered = model.project else { fatalError(model.status) }
        defer { model.stop(); try? FileManager.default.removeItem(at: recovered) }
        precondition(!model.busy && recovered.path != folder.path)
        precondition(model.edit?.duration == 1 && model.promptScript == item.script && model.recordingWarning != nil)
        let copied = try Data(contentsOf: recovered.appendingPathComponent("original.wav"))
        let preserved = try Data(contentsOf: audio)
        precondition(copied == original && preserved == original)
        precondition(FileManager.default.fileExists(atPath: recovered.appendingPathComponent("project.ravenvo.json").path))
        precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(NarrationRecordingRecovery.markerName).path))
        let second = NarrationStudioModel()
        second.openProject(at: recovered.appendingPathComponent("project.ravenvo.json"))
        for _ in 0..<100 { if !second.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(second.edit == model.edit)
        second.stop()
        print("PASS: recovery model copies into new project, preserves original bytes/script, clears completed journal and reopens project; no microphone used")
    }
}

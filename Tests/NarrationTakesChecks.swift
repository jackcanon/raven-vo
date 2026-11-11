import Foundation
import AVFoundation

@main struct NarrationTakesChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/take-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "RavenVO.take-checks.\(UUID().uuidString)"
        StoragePreference.preferences = UserDefaults(suiteName: suite)!
        defer { StoragePreference.preferences.removePersistentDomain(forName: suite) }
        try StoragePreference.choose(root)
        let model = NarrationStudioModel()
        model.promptScript = "Record this line twice."
        func captured(_ sample: Float, folder: URL) throws -> URL {
            let url = folder.appendingPathComponent("original.wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            buffer.floatChannelData![0].initialize(repeating: sample, count: 48000)
            try file.write(from: buffer)
            return url
        }
        let first = try model.nextRecordingFolder()
        let raw = try captured(0.001, folder: first)
        try model.loadAudio(raw, folder: first)
        model.selection = .init(start: 0.2, end: 0.5)
        model.cutSelection()
        model.renameTake(1, to: "Warm reading")
        model.toggleFavorite(1)
        let second = try model.nextRecordingFolder()
        let rawB = try captured(0.002, folder: second)
        try model.loadAudio(rawB, folder: second)
        precondition(model.takes.map(\.name) == ["Warm reading", "Take 2"] && model.favoriteTake == 1)
        let originalEdit = model.edit
        model.audition(model.takes[0])
        precondition(model.auditioningTake == 1 && model.playing)
        model.audition(model.takes[1])
        precondition(model.auditioningTake == 2 && model.edit == originalEdit)
        model.stop()
        model.renameTake(2, to: "Bright reading")
        model.toggleFavorite(2)
        model.editTake(model.takes[0])
        while model.busy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(abs((model.edit?.outputDuration ?? 0) - 0.695) < 0.000001)
        model.promptScript = "A revised line."
        model.savePromptScript()
        let reopened = NarrationStudioModel()
        reopened.openProject(at: second.appendingPathComponent("project.ravenvo.json"))
        while reopened.busy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(reopened.promptScript == "A revised line." && reopened.favoriteTake == 2 && reopened.currentTake?.name == "Bright reading")
        precondition(reopened.edit == originalEdit && reopened.takes.count == 2)
        let bytesA = try Data(contentsOf: raw), bytesB = try Data(contentsOf: rawB)
        precondition(bytesA != bytesB)
        let third = try reopened.nextRecordingFolder()
        let marker = NarrationRecordingRecovery(started: Date(), deviceName: "test", script: reopened.promptScript, localeID: "en-US", folder: third)
        try marker.write()
        reopened.findInterruptedRecordings()
        precondition(reopened.pendingRecordings.contains { $0.folder.path == third.path })
        precondition(reopened.newScript() && reopened.takes.isEmpty && reopened.favoriteTake == nil)
        let fresh = try reopened.nextRecordingFolder()
        precondition(fresh.deletingLastPathComponent().path == first.deletingLastPathComponent().path && fresh.path != first.path)
        print("PASS: independent takes and edits, original auditions, names, favorite, shared script, reopen, nested recovery and new-script isolation")
    }
}

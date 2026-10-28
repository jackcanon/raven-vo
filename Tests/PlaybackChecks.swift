import Foundation
import AVFoundation

@main struct PlaybackChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("samples"), withIntermediateDirectories: true)
        let suite = "RavenVO.PlaybackTests.\(UUID())"
        StoragePreference.preferences = UserDefaults(suiteName: suite)!
        defer { StoragePreference.preferences.removePersistentDomain(forName: suite); StoragePreference.preferences = .standard }
        try StoragePreference.choose(root)
        let url = root.appendingPathComponent("samples/fixture.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 144000)!
        buffer.frameLength = 144000
        for frame in 0..<144000 { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 220 / 24000) * 0.05) }
        try autoreleasepool { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let model = StudioModel()
        model.playbackVolume = 0; model.yourVoice.previewVolume = 0
        model.select(url.path)
        precondition(abs(model.duration - 6) < 0.02)
        model.seek(-10); precondition(model.position == 0)
        model.seek(100); precondition(model.position == model.duration)
        model.seek(.nan); precondition(model.position == model.duration)
        model.seek(1); model.playPause()
        try await Task.sleep(for: .milliseconds(300))
        precondition(model.isPlaying && model.position > 1)
        model.playPause(); let paused = model.position
        try await Task.sleep(for: .milliseconds(200))
        precondition(!model.isPlaying && model.position == paused)
        model.yourVoice.install(url)
        for _ in 0..<200 { if !model.yourVoice.busy { break }; try await Task.sleep(for: .milliseconds(20)) }
        precondition(model.yourVoice.ready)
        model.playPause(); precondition(model.isPlaying)
        model.yourVoice.playOriginalSample()
        precondition(!model.isPlaying && model.yourVoice.previewActive && model.yourVoice.previewIsPlaying)
        model.yourVoice.seekPreview(-1); precondition(model.yourVoice.previewPosition == 0)
        model.yourVoice.seekPreview(999); precondition(model.yourVoice.previewPosition == model.yourVoice.previewDuration)
        model.yourVoice.previewPlayPause()
        model.yourVoice.seekPreview(1)
        model.yourVoice.previewPlayPause()
        try await Task.sleep(for: .milliseconds(150))
        precondition(model.yourVoice.previewIsPlaying && model.yourVoice.previewPosition > 1)
        model.select(url.path)
        precondition(!model.yourVoice.previewActive && !model.yourVoice.previewIsPlaying)
        model.seek(model.duration - 0.1); model.playPause()
        try await Task.sleep(for: .milliseconds(500))
        precondition(!model.isPlaying && model.position == model.duration)
        model.playPause(); precondition(model.isPlaying && model.position == 0)
        model.select(nil); precondition(model.duration == 0 && !model.isPlaying && model.waveform.peaks.isEmpty)
        model.shutdown(); await model.flushSettings()
        try FileManager.default.removeItem(at: root)
        print("PLAYBACK_CHECKS_PASSED: seek bounds, pause/resume, end/replay, preview/take exclusivity, waveform clearing, settings flush; muted synthetic audio")
    }
}

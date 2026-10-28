import Foundation
import AVFoundation

@main struct WaveformChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("stereo-impulses.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: 48000) }
        buffer.floatChannelData![0][1000] = 0.25
        buffer.floatChannelData![1][36000] = -0.8
        try autoreleasepool { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let values = try await Task.detached { try AudioWaveform.peaks(from: url, bins: 48) }.value
        precondition(values.count == 48 && abs(values[1] - 0.25) < 0.001 && abs(values[36] - 0.8) < 0.001)
        precondition(values.enumerated().filter { ![1,36].contains($0.offset) }.allSatisfy { $0.element == 0 })
        let empty = try AudioWaveform.peaks(from: url, bins: 0); precondition(empty.isEmpty)
        let model = WaveformModel()
        model.load(url); model.load(nil)
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.peaks.isEmpty && !model.loading && model.error == nil)
        model.load(url)
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.peaks.count == 640 && model.error == nil)
        model.load(root.appendingPathComponent("missing.wav"))
        for _ in 0..<100 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.peaks.isEmpty && model.error != nil)
        try FileManager.default.removeItem(at: root)
        print("WAVEFORM_CHECKS_PASSED: stereo peaks, correct time buckets, bounded envelope, cancellation, stale-result rejection, missing audio")
    }
}

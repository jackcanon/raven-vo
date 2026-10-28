import Foundation
import AVFoundation

struct SampleQuality: Codable, Sendable {
    let levelDBFS: Double
    let peakDBFS: Double
    let noiseDBFS: Double
    let clippedPercent: Double
    var guidance: String {
        if clippedPercent > 0.1 { return "Clipping detected. Lower the microphone input level and record again; noise reduction cannot repair clipping." }
        if levelDBFS < -35 { return "Recording level is low. Move closer to the microphone or raise the input level gently." }
        if noiseDBFS > -40 { return "Background noise is noticeable. Compare the original and cleaned test before recording your voice sample." }
        return "Recording levels look usable. Compare the original and cleaned test, and keep cleanup enabled only if it helps."
    }
    static func measure(_ url: URL, roomToneAtStart: Bool) throws -> SampleQuality {
        let file = try AVAudioFile(forReading: url)
        let buffer = try VoiceSampleAudio.readAll(file)
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { throw StudioError.message("No audio to evaluate.") }
        let count = Int(buffer.frameLength), rate = file.processingFormat.sampleRate
        var power = 0.0, peak = 0.0, clipped = 0
        var frames: [Double] = [], framePower = 0.0, frameCount = 0
        let window = max(1, Int(rate * 0.05))
        for i in 0..<count {
            let x = Double(samples[i]); power += x*x; peak = max(peak, abs(x))
            if abs(x) >= 0.999 { clipped += 1 }
            framePower += x*x; frameCount += 1
            if frameCount == window { frames.append(framePower / Double(frameCount)); framePower = 0; frameCount = 0 }
        }
        let noise: Double
        if roomToneAtStart {
            let first = frames.prefix(max(1, Int(1.5 / 0.05)))
            noise = first.reduce(0,+) / Double(max(1,first.count))
        } else {
            let quiet = frames.sorted().prefix(max(1,frames.count / 10))
            noise = quiet.reduce(0,+) / Double(max(1,quiet.count))
        }
        func db(_ value: Double) -> Double { 10 * log10(max(value,1e-12)) }
        return SampleQuality(levelDBFS: db(power / Double(count)), peakDBFS: 20 * log10(max(peak,1e-6)), noiseDBFS: db(noise), clippedPercent: Double(clipped) * 100 / Double(count))
    }
}

enum VoiceSampleCleanup {
    static func denoise(_ source: URL, to destination: URL, helper: URL) throws -> Double {
        return try autoreleasepool {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw StudioError.message("The noise cleanup engine is missing. Reinstall Raven VO, or turn off cleanup to use an unprocessed sample.") }
        let root = destination.deletingLastPathComponent()
        let id = UUID().uuidString
        let resampled = root.appendingPathComponent(".Cleanup-\(id).wav")
        let raw = root.appendingPathComponent(".Cleanup-\(id).pcm")
        let cleaned = root.appendingPathComponent(".Cleanup-\(id)-clean.pcm")
        defer { for url in [resampled,raw,cleaned] { try? FileManager.default.removeItem(at: url) } }
        _ = try VoiceSampleAudio.normalize(source, to: resampled, sampleRate: 48000)
        let input = try AVAudioFile(forReading: resampled)
        let buffer = try VoiceSampleAudio.readAll(input)
        guard let samples = buffer.floatChannelData?[0] else { throw StudioError.message("Cannot read audio for cleanup.") }
        let pcm = (0..<Int(buffer.frameLength)).map { Int16(max(-32768,min(32767,Double(samples[$0]) * 32768))) }
        try pcm.withUnsafeBytes { try Data($0).write(to: raw) }
        let process = Process(); process.executableURL = helper; process.arguments = [raw.path,cleaned.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw StudioError.message("Noise reduction did not finish. Your original recording is preserved.") }
        let data = try Data(contentsOf: cleaned)
        guard data.count == pcm.count * MemoryLayout<Int16>.size,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)) else { throw StudioError.message("Noise reduction returned incomplete audio.") }
        output.frameLength = AVAudioFrameCount(pcm.count)
        data.withUnsafeBytes { bytes in
            let input = bytes.bindMemory(to: Int16.self)
            for i in 0..<pcm.count { output.floatChannelData![0][i] = Float(input[i]) / 32768 }
        }
        let file = try AVAudioFile(forWriting: destination, settings: format.settings)
        try file.write(from: output)
        return Double(output.frameLength) / format.sampleRate
        }
    }
}

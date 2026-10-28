import Foundation
import AVFoundation
@main struct VoiceSampleChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        func fixture(_ name: String, seconds: Double, clipped: Bool = false, silent: Bool = false) throws -> URL {
            let count = Int(seconds * 48000), buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            var state: UInt64 = 42
            for i in 0..<count {
                state = state &* 6364136223846793005 &+ 1
                let noise = Float(Double(state >> 32) / Double(UInt32.max) * 2 - 1) * 0.035
                for channel in 0..<2 { buffer.floatChannelData![channel][i] = silent ? 0 : (clipped ? 1 : noise) }
            }
            let url=root.appendingPathComponent(name);try autoreleasepool { let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer) };return url
        }
        let source = try fixture("noise.wav", seconds: 4)
        let raw=root.appendingPathComponent("normalized.wav")
        let duration=try VoiceSampleAudio.normalize(source,to:raw)
        let file=try AVAudioFile(forReading:raw)
        precondition(file.processingFormat.sampleRate == 24000 && file.processingFormat.channelCount == 1 && abs(duration-4)<0.02)
        let before=try SampleQuality.measure(raw,roomToneAtStart:true)
        let cleaned=root.appendingPathComponent("cleaned.wav")
        let outputDuration=try VoiceSampleCleanup.denoise(raw,to:cleaned,helper:URL(fileURLWithPath:CommandLine.arguments[2]))
        let after=try SampleQuality.measure(cleaned,roomToneAtStart:true)
        precondition(abs(duration-outputDuration)<0.02)
        precondition(before.noiseDBFS-after.noiseDBFS>3, "Expected measurable noise suppression")
        let clipped=try fixture("clipped.wav",seconds:4,clipped:true)
        let clipping=try SampleQuality.measure(clipped,roomToneAtStart:true)
        precondition(clipping.clippedPercent>0.1)
        for input in [try fixture("too-short.wav",seconds:1),try fixture("silence.wav",seconds:4,silent:true)] {
            do { _=try VoiceSampleAudio.normalize(input,to:root.appendingPathComponent(UUID().uuidString+".wav"));fatalError("Invalid sample accepted") } catch { }
        }
        let old=Data(#"{"fileName":"old.wav","duration":5,"transcript":"hello"}"#.utf8)
        let legacy=try JSONDecoder().decode(VoiceSampleProfile.self,from:old)
        precondition(legacy.cleanupApplied == nil)
        print("VOICE_SAMPLE_CHECKS_PASSED: duration guards, silence rejection, stereo conversion, metadata compatibility, clipping, noise reduction",before.noiseDBFS-after.noiseDBFS,"dB, frame count preserved")
    }
}

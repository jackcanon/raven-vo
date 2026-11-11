import AVFoundation
import Foundation

enum StudioError: Error { case message(String) }
@main struct CapturePCMChecks {
    static func sample(format: AVAudioFormat, samples: [Float]) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
        var block: CMBlockBuffer?
        let bytes = samples.count * MemoryLayout<Float>.size
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr)
        samples.withUnsafeBytes { raw in precondition(CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes) == noErr) }
        var sample: CMSampleBuffer?
        precondition(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block!, formatDescription: description!, sampleCount: samples.count / Int(format.channelCount), presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        return sample!
    }
    static func main() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: true)!
        let samples = (0..<480).map { Float($0) / 1000 }
        let captured = try sample(format: format, samples: samples)
        let buffer = MicrophoneCapture.audioBuffer(from: captured)!
        precondition(buffer.frameLength == 480 && buffer.format.sampleRate == 48000)
        for i in samples.indices { precondition(buffer.floatChannelData![0][i] == samples[i]) }
        let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!
        let pair = try sample(format: stereo, samples: samples)
        precondition(MicrophoneCapture.audioBuffer(from: pair)?.frameLength == 240)
        var empty: CMSampleBuffer?
        precondition(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &empty) == noErr)
        precondition(MicrophoneCapture.audioBuffer(from: empty!) == nil)
        print("PASS: capture PCM copy, mono values, interleaved stereo frames, missing format rejected before allocation")
    }
}

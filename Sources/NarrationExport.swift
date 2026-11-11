import Foundation
import AVFoundation

enum NarrationExportEncoding: String, CaseIterable, Sendable {
    case pcm16 = "16-bit PCM", pcm24 = "24-bit PCM", float32 = "32-bit Float"
    var bits: Int { self == .pcm16 ? 16 : self == .pcm24 ? 24 : 32 }
}
struct NarrationExportLevels: Sendable {
    var peak: Double
    var rms: Double
    var frames: Int64
    var sampleRate: Double
    var channels: Int
    var peakDB: Double { peak > 0 ? 20 * log10(peak) : -.infinity }
    var rmsDB: Double { rms > 0 ? 20 * log10(rms) : -.infinity }
}
enum NarrationExport {
    static func analyze(_ source: URL) throws -> NarrationExportLevels {
        let file = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw ExportError.invalidAudio }
        var peak = 0.0, squares = 0.0
        var count: Int64 = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, file.length - file.framePosition)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw ExportError.invalidAudio }
            for channel in 0..<Int(file.processingFormat.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(channels[channel][frame])
                    guard value.isFinite else { throw ExportError.invalidAudio }
                    peak = max(peak, abs(value)); squares += value * value; count += 1
                }
            }
        }
        guard count > 0 else { throw ExportError.invalidAudio }
        return .init(peak: peak, rms: sqrt(squares / Double(count)), frames: file.length, sampleRate: file.processingFormat.sampleRate, channels: Int(file.processingFormat.channelCount))
    }
    static func gain(levels: NarrationExportLevels, gainDB: Double, ceiling: Bool) throws -> Double {
        guard gainDB.isFinite, (-24...12).contains(gainDB) else { throw ExportError.invalidGain }
        let requested = pow(10, gainDB / 20)
        return ceiling && levels.peak > 0 ? min(requested, pow(10, -1 / 20.0) / levels.peak) : requested
    }
    static func write(source: URL, destination: URL, encoding: NarrationExportEncoding, gainDB: Double, ceiling: Bool) throws -> NarrationExportLevels {
        let levels = try analyze(source)
        let scale = try gain(levels: levels, gainDB: gainDB, ceiling: ceiling)
        guard encoding == .float32 || levels.peak * scale < 1 else { throw ExportError.clipping }
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        let output = try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: encoding.bits, AVLinearPCMIsFloatKey: encoding == .float32, AVLinearPCMIsBigEndianKey: false])
        defer { if #available(macOS 15.0, *) { output.close() } }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw ExportError.invalidAudio }
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, input.length - input.framePosition)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw ExportError.invalidAudio }
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) { channels[channel][frame] *= Float(scale) }
            }
            try output.write(from: buffer)
        }
        return .init(peak: levels.peak * scale, rms: levels.rms * scale, frames: levels.frames, sampleRate: levels.sampleRate, channels: levels.channels)
    }
    enum ExportError: LocalizedError {
        case invalidAudio, invalidGain, clipping
        var errorDescription: String? {
            switch self {
            case .invalidAudio: "The export contains empty or invalid audio."
            case .invalidGain: "Output gain must be between −24 and +12 dB."
            case .clipping: "PCM export would clip. Lower output gain or enable the −1 dBFS peak ceiling."
            }
        }
    }
}

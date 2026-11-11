import Foundation
import AVFoundation

@main struct ExportChecks {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("float-source.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            for frame in 0..<48000 { buffer.floatChannelData![0][frame] = 0.1234567; buffer.floatChannelData![1][frame] = -0.25 }
            try file.write(from: buffer)
        }
        let original = try Data(contentsOf: source)
        let levels = try NarrationExport.analyze(source)
        precondition(levels.frames == 48000 && levels.channels == 2 && levels.sampleRate == 48000)
        precondition(abs(levels.peakDB + 12.0412) < 0.0001)
        precondition(abs(levels.rms - sqrt((pow(0.1234567, 2) + 0.0625) / 2)) < 0.000001)
        for encoding in NarrationExportEncoding.allCases {
            let output = folder.appendingPathComponent("\(encoding.bits).wav")
            _ = try NarrationExport.write(source: source, destination: output, encoding: encoding, gainDB: 0, ceiling: false)
            let file = try AVAudioFile(forReading: output)
            precondition(file.length == 48000 && file.fileFormat.streamDescription.pointee.mBitsPerChannel == encoding.bits)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1)!
            try file.read(into: buffer, frameCount: 1)
            let error = abs(buffer.floatChannelData![0][0] - 0.1234567)
            precondition(error < (encoding == .pcm16 ? 0.00004 : 0.0000002))
        }
        // A float intermediate must preserve headroom for post-effect level checks.
        let hot = folder.appendingPathComponent("hot.wav")
        do {
            let file = try AVAudioFile(forWriting: hot, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
            buffer.frameLength = 16
            for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 1.5, count: 16) }
            try file.write(from: buffer)
        }
        do {
            _ = try NarrationExport.write(source: hot, destination: folder.appendingPathComponent("clip.wav"), encoding: .pcm16, gainDB: 0, ceiling: false)
            fatalError("Clipping PCM accepted")
        } catch NarrationExport.ExportError.clipping { }
        let safe = folder.appendingPathComponent("ceiling.wav")
        _ = try NarrationExport.write(source: hot, destination: safe, encoding: .pcm24, gainDB: 6, ceiling: true)
        let safeLevels = try NarrationExport.analyze(safe)
        precondition(abs(safeLevels.peakDB + 1) < 0.00001 && safeLevels.frames == 16)
        let floating = folder.appendingPathComponent("headroom.wav")
        _ = try NarrationExport.write(source: hot, destination: floating, encoding: .float32, gainDB: 0, ceiling: false)
        let headroom = try NarrationExport.analyze(floating)
        precondition(headroom.peak == 1.5)
        let floatEdit = NarrationEdit(sourceName: "hot.wav", duration: 16.0 / 48000, kept: [.init(start: 0, end: 16.0 / 48000)])
        let intermediate = folder.appendingPathComponent("edit-intermediate.wav")
        try NarrationRenderer.render(source: hot, edit: floatEdit, destination: intermediate, floatingPoint: true)
        let intermediateLevels = try NarrationExport.analyze(intermediate)
        precondition(intermediateLevels.peak == 1.5 && intermediateLevels.frames == 16)
        let finalOriginal = try Data(contentsOf: source)
        precondition(finalOriginal == original)
        do { _ = try NarrationExport.gain(levels: levels, gainDB: .nan, ceiling: false); fatalError("Invalid gain accepted") } catch { }
        print("PASS: export encodings/precision, stereo frames, sample peak/RMS, float headroom, clipping rejection, -1 dBFS attenuation and source preservation")
    }
}

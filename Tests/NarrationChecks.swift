import Foundation
import AVFoundation

@main struct NarrationChecks {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("original.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            for i in 0..<48000 {
                buffer.floatChannelData![0][i] = Float(i) / 48000 * 0.5
                buffer.floatChannelData![1][i] = -Float(i) / 48000 * 0.5
            }
            try file.write(from: buffer)
        }
        let originalBytes = try Data(contentsOf: source)
        var edit = NarrationEdit(sourceName: "original.wav", duration: 1, kept: [.init(start: 0, end: 1)],
            words: [.init(text: "one", start: 0.1, end: 0.2), .init(text: "two", start: 0.4, end: 0.6)])
        let before = edit
        edit.cut(.init(start: 0.25, end: 0.75))
        precondition(edit.kept == [.init(start: 0, end: 0.25), .init(start: 0.75, end: 1)])
        precondition(abs(edit.outputDuration - 0.5) < 0.00001)
        precondition(edit.contains(edit.words[0]) && !edit.contains(edit.words[1]))
        precondition(abs(edit.sourceTime(at: 0.3) - 0.8) < 0.00001)
        precondition(abs(edit.outputTime(at: 0.8) - 0.3) < 0.00001)
        let output = folder.appendingPathComponent("edited.wav")
        try NarrationRenderer.render(source: source, edit: edit, destination: output)
        let rendered = try AVAudioFile(forReading: output)
        precondition(rendered.length == 24000 && rendered.processingFormat.channelCount == 2)
        rendered.framePosition = 12000
        let check = AVAudioPCMBuffer(pcmFormat: rendered.processingFormat, frameCapacity: 1)!
        try rendered.read(into: check, frameCount: 1)
        precondition(abs(check.floatChannelData![0][0] - 0.375) < 0.0001)
        precondition(abs(check.floatChannelData![1][0] + 0.375) < 0.0001)
        let afterBytes = try Data(contentsOf: source)
        precondition(afterBytes == originalBytes)
        let saved = folder.appendingPathComponent("project.ravenvo.json")
        try JSONEncoder().encode(edit).write(to: saved)
        let reopened = try JSONDecoder().decode(NarrationEdit.self, from: Data(contentsOf: saved))
        precondition(reopened == edit)
        try reopened.validate()
        var restored = before
        restored.cut(.init(start: -10, end: 0.1))
        precondition(restored.kept.first?.start == 0.1)
        restored.cut(.init(start: 0, end: 10))
        precondition(restored.kept.isEmpty)
        var invalid = before; invalid.sourceName = "../outside.wav"
        do { try invalid.validate(); fatalError("Traversal accepted") } catch { }
        invalid = before; invalid.kept = [.init(start: 0, end: .infinity)]
        do { try invalid.validate(); fatalError("Invalid timing accepted") } catch { }
        // A deliberate discontinuity: the legacy cut jumps 0.25; a 5 ms
        // linear overlap spreads that transition without boosting either channel.
        var faded = edit; faded.joinCrossfadeMS = 5
        let fadedURL = folder.appendingPathComponent("crossfaded.wav")
        try NarrationRenderer.render(source: source, edit: faded, destination: fadedURL)
        let fadeFile = try AVAudioFile(forReading: fadedURL)
        precondition(fadeFile.length == 24000 - 240)
        precondition(abs(faded.outputDuration - 0.495) < 0.000001)
        let all = AVAudioPCMBuffer(pcmFormat: fadeFile.processingFormat, frameCapacity: AVAudioFrameCount(fadeFile.length))!
        try fadeFile.read(into: all)
        var maximumJump: Float = 0
        for i in 1..<Int(all.frameLength) {
            maximumJump = max(maximumJump, abs(all.floatChannelData![0][i] - all.floatChannelData![0][i - 1]))
            precondition(abs(all.floatChannelData![0][i] + all.floatChannelData![1][i]) < 0.0001)
        }
        precondition(maximumJump < 0.002)
        // The same processor must remain identical across tiny streaming blocks.
        let input = try AVAudioFile(forReading: source)
        let joins = NarrationJoinProcessor(edit: faded, format: input.processingFormat)
        var streamed: [Float] = []
        for (index, range) in faded.kept.enumerated() {
            input.framePosition = Int64((range.start * 48000).rounded())
            let end = Int64((range.end * 48000).rounded())
            while input.framePosition < end {
                let block = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 37)!
                let first = input.framePosition
                try input.read(into: block, frameCount: AVAudioFrameCount(min(37, end - first)))
                if let result = try joins.process(block, firstFrame: first, rangeIndex: index) {
                    streamed.append(contentsOf: UnsafeBufferPointer(start: result.floatChannelData![0], count: Int(result.frameLength)))
                }
            }
        }
        precondition(streamed.count == Int(fadeFile.length))
        for i in streamed.indices { precondition(abs(streamed[i] - all.floatChannelData![0][i]) < 0.00004) }
        let fadeJSON = try JSONEncoder().encode(faded)
        let decodedFade = try JSONDecoder().decode(NarrationEdit.self, from: fadeJSON)
        precondition(decodedFade.joinCrossfadeMS == 5)
        precondition(reopened.joinCrossfadeMS == nil) // Old projects retain exact hard cuts.
        for value in [Double.nan, -1, 21] {
            var bad = edit; bad.joinCrossfadeMS = value
            do { try bad.validate(); fatalError("Invalid crossfade accepted") } catch { }
        }
        var tiny = faded; tiny.kept = [.init(start: 0, end: 0.0001), .init(start: 0.5, end: 0.5001), .init(start: 0.8, end: 0.8001)]
        let tinyURL = folder.appendingPathComponent("tiny-crossfades.wav")
        try NarrationRenderer.render(source: source, edit: tiny, destination: tinyURL)
        let tinyFile = try AVAudioFile(forReading: tinyURL)
        precondition(tinyFile.length == 11) // 5+5+5 minus two 2-frame overlaps.
        let preserved = try Data(contentsOf: source)
        precondition(preserved == originalBytes)
        print("PASS: crossfade discontinuity reduction, stereo, exact frames, streaming/offline agreement, short ranges, compatibility and validation")
        print("PASS: cut mapping, stereo rendered sample continuity, frame count, source preservation, save/reopen, boundaries, malformed project rejection")
    }
}

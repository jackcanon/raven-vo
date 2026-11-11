import Foundation
import AVFoundation

struct NarrationRange: Codable, Equatable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}
struct NarrationWord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var start: Double
    var end: Double
}
/// Source coordinates never change. The retained ranges are the edit decision list.
struct NarrationEdit: Codable, Equatable, Sendable {
    var version = 1
    var sourceName: String
    var duration: Double
    var kept: [NarrationRange]
    var words: [NarrationWord] = []
    var cleanedSourceName: String?
    var useCleanedAudio: Bool?
    var roomToneName: String?
    var roomToneDeviceID: String?
    var cleanupAmount: Double?
    var cleanupSettings: NarrationCleanupSettings?
    var promptScript: String?
    var plugins: [NarrationPluginState]?
    var joinCrossfadeMS: Double?
    /// Linear crossfades only at discontinuous source boundaries. Half-range caps
    /// keep neighboring crossfades from consuming the same samples.
    func overlap(before index: Int) -> Double {
        guard index > 0, index < kept.count, kept[index].start > kept[index - 1].end else { return 0 }
        return min((joinCrossfadeMS ?? 0) / 1000, kept[index - 1].duration / 2, kept[index].duration / 2)
    }
    var outputDuration: Double { kept.enumerated().reduce(0) { $0 + $1.element.duration - overlap(before: $1.offset) } }
    func contains(_ word: NarrationWord) -> Bool {
        kept.contains { word.start >= $0.start - 0.001 && word.end <= $0.end + 0.001 }
    }
    mutating func cut(_ range: NarrationRange) {
        guard range.start.isFinite, range.end.isFinite, range.end > range.start else { return }
        kept = kept.flatMap { part -> [NarrationRange] in
            guard range.end > part.start, range.start < part.end else { return [part] }
            var result: [NarrationRange] = []
            if range.start > part.start { result.append(.init(start: part.start, end: min(part.end, range.start))) }
            if range.end < part.end { result.append(.init(start: max(part.start, range.end), end: part.end)) }
            return result.filter { $0.duration > 0.00001 }
        }
    }
    func sourceTime(at outputTime: Double) -> Double {
        var elapsed = 0.0
        for (index, range) in kept.enumerated() {
            elapsed -= overlap(before: index)
            if outputTime < elapsed + range.duration { return range.start + max(0, outputTime - elapsed) }
            elapsed += range.duration
        }
        return kept.last?.end ?? 0
    }
    func outputTime(at sourceTime: Double) -> Double {
        var elapsed = 0.0
        for (index, range) in kept.enumerated() {
            elapsed -= overlap(before: index)
            if sourceTime <= range.end { return elapsed + max(0, sourceTime - range.start) }
            elapsed += range.duration
        }
        return elapsed
    }
    func validate() throws {
        guard version == 1, duration.isFinite, duration > 0,
              sourceName == URL(fileURLWithPath: sourceName).lastPathComponent, !sourceName.isEmpty, sourceName != ".", sourceName != ".." else {
            throw NSError(domain: "Narration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid studio project."])
        }
        for name in [cleanedSourceName, roomToneName].compactMap({ $0 }) {
            guard !name.isEmpty, name != ".", name != "..", name == URL(fileURLWithPath: name).lastPathComponent else {
                throw NSError(domain: "Narration", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid project media path."])
            }
        }
        if let fade = joinCrossfadeMS, !fade.isFinite || fade < 0 || fade > 20 {
            throw NSError(domain: "Narration", code: 8, userInfo: [NSLocalizedDescriptionKey: "Crossfade must be between 0 and 20 milliseconds."])
        }
        try cleanupSettings?.validate()
        var end = 0.0
        for range in kept {
            guard range.start.isFinite, range.end.isFinite, range.start >= end, range.end > range.start,
                  range.end <= duration + 0.001 else { throw NSError(domain: "Narration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid audio edit ranges."]) }
            end = range.end
        }
        guard Set(words.map(\.id)).count == words.count, words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= duration + 0.1 }) else {
            throw NSError(domain: "Narration", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid transcript timing."])
        }
    }
}

enum NarrationRenderer {
    /// Reads bounded blocks, preserving source sample rate and channel count.
    static func render(source: URL, edit: NarrationEdit, destination: URL, floatingPoint: Bool = false) throws {
        try autoreleasepool { try process(source: source, edit: edit, destination: destination, floatingPoint: floatingPoint) }
    }
    private static func process(source: URL, edit: NarrationEdit, destination: URL, floatingPoint: Bool) throws {
        try edit.validate()
        guard edit.outputDuration > 0 else { throw NSError(domain: "Narration", code: 4, userInfo: [NSLocalizedDescriptionKey: "The edit contains no audio."]) }
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        guard abs(Double(input.length) / format.sampleRate - edit.duration) < 0.1 else {
            throw NSError(domain: "Narration", code: 6, userInfo: [NSLocalizedDescriptionKey: "The original audio duration has changed. Reimport the recording before editing."])
        }
        let output = try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: floatingPoint ? 32 : 16, AVLinearPCMIsFloatKey: floatingPoint, AVLinearPCMIsBigEndianKey: false])
        defer { if #available(macOS 15.0, *) { output.close() } }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return }
        let joins = NarrationJoinProcessor(edit: edit, format: format)
        for (index, range) in edit.kept.enumerated() {
            let first = min(input.length, Int64((range.start * format.sampleRate).rounded()))
            let last = min(input.length, Int64((range.end * format.sampleRate).rounded()))
            input.framePosition = first
            var remaining = last - first
            while remaining > 0 {
                try Task.checkCancellation()
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, remaining)))
                guard buffer.frameLength > 0 else { throw NSError(domain: "Narration", code: 5, userInfo: [NSLocalizedDescriptionKey: "Audio ended before the edit was rendered."]) }
                if let joined = try joins.process(buffer, firstFrame: input.framePosition - Int64(buffer.frameLength), rangeIndex: index) {
                    try output.write(from: joined)
                }
                remaining -= Int64(buffer.frameLength)
            }
        }
    }
}

/// Bounded streaming join processor shared by offline rendering and live cleanup.
/// Holds only the outgoing crossfade tail (at most 20 ms per channel).
// Confined to one render worker; the stream callback runs synchronously there.
final class NarrationJoinProcessor: @unchecked Sendable {
    private let edit: NarrationEdit
    private let format: AVAudioFormat
    private var tail: [[Float]]
    init(edit: NarrationEdit, format: AVAudioFormat) {
        self.edit = edit; self.format = format
        tail = Array(repeating: [], count: Int(format.channelCount))
    }
    private func frames(before index: Int) -> Int {
        guard index > 0, index < edit.kept.count else { return 0 }
        let rate = format.sampleRate
        let previous = edit.kept[index - 1], next = edit.kept[index]
        let a = Int((previous.end * rate).rounded() - (previous.start * rate).rounded())
        let b = Int((next.end * rate).rounded() - (next.start * rate).rounded())
        return min(Int((edit.overlap(before: index) * rate).rounded()), a / 2, b / 2)
    }
    func process(_ buffer: AVAudioPCMBuffer, firstFrame: Int64, rangeIndex: Int) throws -> AVAudioPCMBuffer? {
        let range = edit.kept[rangeIndex], rate = format.sampleRate
        let start = Int64((range.start * rate).rounded()), end = Int64((range.end * rate).rounded())
        let incoming = frames(before: rangeIndex), outgoing = frames(before: rangeIndex + 1)
        guard let source = buffer.floatChannelData else { throw StudioErrorForJoin.invalidBuffer }
        var result = Array(repeating: [Float](), count: Int(format.channelCount))
        for frame in 0..<Int(buffer.frameLength) {
            let position = firstFrame + Int64(frame)
            let headOffset = Int(position - start)
            let hold = outgoing > 0 && position >= end - Int64(outgoing)
            for channel in result.indices {
                let sample = source[channel][frame]
                if hold { tail[channel].append(sample) }
                else if incoming > 0 && headOffset < incoming {
                    guard tail[channel].count == incoming else { throw StudioErrorForJoin.invalidBuffer }
                    let weight = Float(headOffset + 1) / Float(incoming + 1)
                    result[channel].append(tail[channel][headOffset] * (1 - weight) + sample * weight)
                } else { result[channel].append(sample) }
            }
            if incoming > 0 && headOffset == incoming - 1 { for channel in tail.indices { tail[channel].removeAll(keepingCapacity: true) } }
        }
        guard let count = result.first?.count, count > 0 else { return nil }
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)), let data = output.floatChannelData else { throw StudioErrorForJoin.invalidBuffer }
        output.frameLength = AVAudioFrameCount(count)
        for channel in result.indices { result[channel].withUnsafeBufferPointer { data[channel].update(from: $0.baseAddress!, count: count) } }
        return output
    }
    private enum StudioErrorForJoin: Error { case invalidBuffer }
}

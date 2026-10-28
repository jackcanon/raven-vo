import AVFoundation
import Observation

/// Bounded-memory envelope; reads blocks rather than loading the entire take.
enum AudioWaveform {
    static func peaks(from url: URL, bins: Int = 640) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, bins > 0 else { return [] }
        let count = min(bins, Int(file.length))
        var peaks = [Float](repeating: 0, count: count)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { return [] }
        var offset: AVAudioFramePosition = 0
        while offset < file.length {
            if Task.isCancelled { throw CancellationError() }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, file.length - offset)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let bucket = min(count - 1, Int((offset + Int64(frame)) * Int64(count) / file.length))
                for channel in 0..<Int(format.channelCount) {
                    let amplitude = abs(channels[channel][frame])
                    if amplitude.isFinite { peaks[bucket] = max(peaks[bucket], min(1, amplitude)) }
                }
            }
            offset += Int64(buffer.frameLength)
        }
        return peaks
    }
}

@MainActor @Observable final class WaveformModel {
    var peaks: [Float] = []
    var loading = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    func load(_ url: URL?) {
        task?.cancel(); task = nil
        request = UUID(); peaks = []; error = nil; loading = url != nil
        guard let url else { return }
        let id = request
        task = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { try AudioWaveform.peaks(from: url) }
            do {
                let values = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self, self.request == id else { return }
                self.peaks = values; self.loading = false
            } catch {
                guard !Task.isCancelled, let self, self.request == id else { return }
                self.loading = false; self.error = "Waveform unavailable. Playback controls are still available."
            }
        }
    }
}

import Foundation
import AVFoundation

/// Worker-to-player queue bounded to four 1024-frame buffers (~85 ms at 48 kHz).
/// Only value snapshots cross the UI/worker boundary; no UI access on the audio callback.
final class NarrationPreviewState: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = NarrationCleanupSettings.referenceA
    private var cancelled = false
    private var position = 0.0
    private var peak: Float = 0
    func update(_ value: NarrationCleanupSettings, original: Bool) {
        lock.withLock { settings = value; if original { settings.mix = 0 } }
    }
    func snapshot() -> NarrationCleanupSettings { lock.withLock { settings } }
    func cancel() { lock.withLock { cancelled = true } }
    var stopped: Bool { lock.withLock { cancelled } }
    func setPosition(_ value: Double) { lock.withLock { position = value } }
    var time: Double { lock.withLock { position } }
    func setPeak(_ value: Float) { lock.withLock { peak = value } }
    var samplePeak: Float { lock.withLock { peak } }
}

@MainActor final class NarrationLivePreview {
    let state = NarrationPreviewState()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let monitor = AVAudioUnitEQ(numberOfBands: 0)
    private let worker = DispatchQueue(label: "app.ravenvo.live-cleanup", qos: .userInitiated)
    private let slots = DispatchSemaphore(value: 4)
    private(set) var running = false
    var time: Double { state.time }
    func setMonitorDB(_ value: Double) { monitor.globalGain = Float(max(-24, min(18, value))) }
    func start(source: URL, roomTone: URL, directory: URL, format: AVAudioFormat, edit: NarrationEdit,
               settings: NarrationCleanupSettings, monitorDB: Double,
               onError: @escaping @MainActor @Sendable (String) -> Void) throws {
        state.update(settings, original: false)
        engine.attach(player); engine.attach(monitor)
        engine.connect(player, to: monitor, format: format)
        engine.connect(monitor, to: engine.mainMixerNode, format: format)
        setMonitorDB(monitorDB)
        try engine.start(); player.play(); running = true
        let state = state, player = player, slots = slots
        worker.async {
            do {
                while !state.stopped {
                    let joins = NarrationJoinProcessor(edit: edit, format: format)
                    try NarrationNoiseCleanup.stream(source: source, roomTone: roomTone, workingDirectory: directory,
                        settings: { state.snapshot() }, onBuffer: { buffer, time in
                            let rate = buffer.format.sampleRate
                            let first = Int64((time * rate).rounded())
                            let last = first + Int64(buffer.frameLength)
                            for (rangeIndex, range) in edit.kept.enumerated() {
                                let begin = max(first, Int64((range.start * rate).rounded()))
                                let end = min(last, Int64((range.end * rate).rounded()))
                                guard end > begin else { continue }
                                while slots.wait(timeout: .now() + 0.05) == .timedOut {
                                    if state.stopped { throw CancellationError() }
                                }
                                guard !state.stopped else { slots.signal(); throw CancellationError() }
                                let frames = AVAudioFrameCount(end - begin), offset = Int(begin - first)
                                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames),
                                      let from = buffer.floatChannelData, let to = copy.floatChannelData else {
                                    slots.signal(); throw StudioError.message("Could not buffer the cleanup preview.")
                                }
                                copy.frameLength = frames
                                var peak: Float = 0
                                for channel in 0..<Int(buffer.format.channelCount) {
                                    to[channel].update(from: from[channel].advanced(by: offset), count: Int(frames))
                                    for frame in 0..<Int(frames) { peak = max(peak, abs(to[channel][frame])) }
                                }
                                guard let joined = try joins.process(copy, firstFrame: begin, rangeIndex: rangeIndex) else { slots.signal(); continue }
                                peak = 0
                                if let samples = joined.floatChannelData {
                                    for channel in 0..<Int(joined.format.channelCount) {
                                        for frame in 0..<Int(joined.frameLength) { peak = max(peak, abs(samples[channel][frame])) }
                                    }
                                }
                                state.setPeak(peak)
                                let endTime = edit.outputTime(at: Double(end) / rate)
                                player.scheduleBuffer(joined, completionCallbackType: .dataPlayedBack) { _ in
                                    state.setPosition(endTime)
                                    slots.signal()
                                }
                            }
                            if state.stopped { throw CancellationError() }
                        })
                }
            } catch {
                if !state.stopped { let message = error.localizedDescription; Task { @MainActor in onError(message) } }
            }
        }
    }
    func stop() {
        running = false; state.cancel(); player.stop(); engine.stop()
        for _ in 0..<4 { slots.signal() }
    }
}

import AVFoundation
import Accelerate

/// Offline, profile-based spectral attenuation. No live microphone processing.
/// Bounded buffers and overlap-add preserve the source frame count and timing.
enum NarrationNoiseCleanup {
    static func render(source: URL, roomTone: URL, destination: URL, amount: Float) throws {
        try render(source: source, roomTone: roomTone, destination: destination, amount: amount, settings: nil)
    }
    static func render(source: URL, roomTone: URL, destination: URL, settings: NarrationCleanupSettings) throws {
        try settings.validate()
        try render(source: source, roomTone: roomTone, destination: destination, amount: Float(settings.strength), settings: settings)
    }
    private static func render(source: URL, roomTone: URL, destination: URL, amount: Float, settings: NarrationCleanupSettings?) throws {
        try autoreleasepool {
            let rate = try AVAudioFile(forReading: source).processingFormat.sampleRate
            let noiseRate = try AVAudioFile(forReading: roomTone).processingFormat.sampleRate
            let converted = destination.deletingLastPathComponent().appendingPathComponent("noise-profile-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: converted) }
            if rate != noiseRate {
                try convertProfile(roomTone, to: converted, sampleRate: rate)
                try process(source: source, roomTone: converted, destination: destination, amount: amount, settings: settings)
            } else {
                try process(source: source, roomTone: roomTone, destination: destination, amount: amount, settings: settings)
            }
        }
    }
    /// Produces short blocks on the caller's worker queue. No DSP or file I/O runs on the device callback.
    static func stream(source: URL, roomTone: URL, workingDirectory: URL,
                       settings: @escaping @Sendable () -> NarrationCleanupSettings,
                       onBuffer: @escaping @Sendable (AVAudioPCMBuffer, Double) throws -> Void) throws {
        try autoreleasepool {
            let rate = try AVAudioFile(forReading: source).processingFormat.sampleRate
            let noiseRate = try AVAudioFile(forReading: roomTone).processingFormat.sampleRate
            let converted = workingDirectory.appendingPathComponent("preview-profile-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: converted) }
            if rate != noiseRate { try convertProfile(roomTone, to: converted, sampleRate: rate) }
            try process(source: source, roomTone: rate == noiseRate ? roomTone : converted, destination: nil, amount: 0,
                        settings: .referenceA, settingsProvider: settings, outputHandler: onBuffer)
        }
    }
    /// Convert only the short room profile; never resample the narration or its edit timing.
    private static func convertProfile(_ source: URL, to destination: URL, sampleRate: Double) throws {
        let input = try AVAudioFile(forReading: source)
        let duration = Double(input.length) / input.processingFormat.sampleRate
        guard duration > 0, duration <= 10,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: input.processingFormat.channelCount),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let scratch = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw StudioError.message("Cannot convert this room-noise profile.")
        }
        converter.primeMethod = .none
        let output = try AVAudioFile(forWriting: destination, settings: format.settings)
        defer { if #available(macOS 15.0, *) { output.close() } }
        for _ in 0..<1000 {
            try Task.checkCancellation()
            var error: NSError?
            var readError: Error?
            let status = converter.convert(to: buffer, error: &error) { requested, state in
                if input.framePosition >= input.length { state.pointee = .endOfStream; return nil }
                do {
                    try input.read(into: scratch, frameCount: min(requested, scratch.frameCapacity, AVAudioFrameCount(input.length - input.framePosition)))
                    state.pointee = scratch.frameLength > 0 ? .haveData : .endOfStream
                    return scratch.frameLength > 0 ? scratch : nil
                } catch { readError = error; state.pointee = .noDataNow; return nil }
            }
            if let readError { throw readError }
            if let error { throw error }
            guard status != .error else { throw StudioError.message("Room-noise conversion failed.") }
            if buffer.frameLength > 0 { try output.write(from: buffer) }
            if status == .endOfStream { return }
        }
        throw StudioError.message("Room-noise conversion did not finish.")
    }
    private static func process(source: URL, roomTone: URL, destination: URL?, amount: Float, settings: NarrationCleanupSettings?,
                                settingsProvider: (@Sendable () -> NarrationCleanupSettings)? = nil,
                                outputHandler: (@Sendable (AVAudioPCMBuffer, Double) throws -> Void)? = nil) throws {
        let n = 2048, hop = 1024
        let input = try AVAudioFile(forReading: source)
        let noise = try AVAudioFile(forReading: roomTone)
        let format = input.processingFormat
        guard noise.processingFormat.sampleRate == format.sampleRate else { throw StudioError.message("Capture room noise again for this recording's sample rate.") }
        guard noise.length >= Int64(n), Double(noise.length) / format.sampleRate <= 10 else { throw StudioError.message("Capture 3 seconds of room noise before cleanup.") }
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD),
              let inverse = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .INVERSE) else { throw StudioError.message("Could not initialize native noise cleanup.") }
        defer { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(inverse) }
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * (Double($0) + 0.5) / Double(n))) }
        let zero = [Float](repeating: 0, count: n)
        var real = zero, imag = zero, restored = zero, restoredImag = zero
        var noisePower = zero
        guard let noiseBuffer = AVAudioPCMBuffer(pcmFormat: noise.processingFormat, frameCapacity: AVAudioFrameCount(n)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(hop)) else { throw StudioError.message("Could not allocate noise cleanup buffers.") }
        var count: Float = 0
        while noise.framePosition + Int64(n) <= noise.length {
            try noise.read(into: noiseBuffer, frameCount: AVAudioFrameCount(n))
            guard let channels = noiseBuffer.floatChannelData else { throw StudioError.message("Room noise must be PCM audio.") }
            let mono = (0..<n).map { index in (0..<Int(noise.processingFormat.channelCount)).reduce(Float(0)) { $0 + channels[$1][index] } / Float(noise.processingFormat.channelCount) * window[index] }
            vDSP_DFT_Execute(forward, mono, zero, &real, &imag)
            for i in 0..<n { noisePower[i] += real[i] * real[i] + imag[i] * imag[i] }
            count += 1
        }
        guard count > 0 else { throw StudioError.message("Room noise sample was too short.") }
        for i in 0..<n { noisePower[i] /= count }
        let output = try destination.map { try AVAudioFile(forWriting: $0, settings: format.settings) }
        defer { if #available(macOS 15.0, *) { output?.close() } }
        var accumulation = Array(repeating: zero, count: Int(format.channelCount))
        var weights = zero
        var previousGains = Array(repeating: [Float](repeating: 1, count: n), count: Int(format.channelCount))
        var start = -Int64(hop)
        var written: Int64 = 0
        while start < input.length {
            try Task.checkCancellation()
            let currentSettings = settingsProvider?() ?? settings
            try currentSettings?.validate()
            let prefix = Int(max(0, -start))
            input.framePosition = max(0, start)
            let available = AVAudioFrameCount(min(Int64(n - prefix), input.length - input.framePosition))
            try input.read(into: buffer, frameCount: available)
            guard let channels = buffer.floatChannelData, let out = outputBuffer.floatChannelData else { throw StudioError.message("Recording must be PCM audio.") }
            for channel in 0..<Int(format.channelCount) {
                var signal = zero
                for i in 0..<Int(buffer.frameLength) { signal[i + prefix] = channels[channel][i] * window[i + prefix] }
                vDSP_DFT_Execute(forward, signal, zero, &real, &imag)
                if let settings = currentSettings {
                    let powers = (0..<n).map { real[$0] * real[$0] + imag[$0] * imag[$0] }
                    var gains = zero
                    let radius = Int((settings.smoothing * 6).rounded())
                    let floor = Float(pow(10, -settings.maximumReductionDB / 20))
                    for i in 0..<n {
                        var power: Float = 0, noise: Float = 0
                        for delta in -radius...radius {
                            let bin = (i + delta + n) % n
                            power += powers[bin]; noise += noisePower[bin]
                        }
                        let frequency = Double(min(i, n - i)) * format.sampleRate / Double(n)
                        let strength = Float(settings.strength * settings.focus(at: frequency))
                        let target = max(floor, 1 - strength * noise / max(power, 1e-12))
                        let previous = previousGains[channel][i]
                        let weight: Float = target > previous ? Float(1 - settings.smoothing * 0.3) : Float(max(0.05, 1 - settings.smoothing * 1.4))
                        gains[i] = weight * target + (1 - weight) * previous
                    }
                    previousGains[channel] = gains
                    for i in 0..<n {
                        let gain = Float(1 - settings.mix) + Float(settings.mix) * gains[i]
                        real[i] *= gain; imag[i] *= gain
                    }
                } else {
                for i in 0..<n {
                    let power = real[i] * real[i] + imag[i] * imag[i]
                    let floor: Float = 0.08
                    let gain = sqrt(max(floor * floor, 1 - max(0, min(3, amount)) * noisePower[i] / max(power, 1e-12)))
                    real[i] *= gain; imag[i] *= gain
                }
                }
                vDSP_DFT_Execute(inverse, real, imag, &restored, &restoredImag)
                for i in 0..<n { accumulation[channel][i] += restored[i] / Float(n) * window[i] }
            }
            for i in 0..<n { weights[i] += window[i] * window[i] }
            if start >= 0 {
                let frames = Int(min(Int64(hop), input.length - start))
                outputBuffer.frameLength = AVAudioFrameCount(frames)
                for channel in 0..<Int(format.channelCount) {
                    for i in 0..<frames { out[channel][i] = accumulation[channel][i] / max(weights[i], 1e-12) }
                }
                try output?.write(from: outputBuffer)
                try outputHandler?(outputBuffer, Double(start) / format.sampleRate)
                written += Int64(frames)
            }
            for channel in 0..<Int(format.channelCount) { accumulation[channel] = Array(accumulation[channel][hop...]) + [Float](repeating: 0, count: hop) }
            weights = Array(weights[hop...]) + [Float](repeating: 0, count: hop)
            start += Int64(hop)
        }
        guard written == input.length else { throw StudioError.message("Noise cleanup returned incomplete audio. Original preserved.") }
    }
}

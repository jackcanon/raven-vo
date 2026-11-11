import Foundation
import AVFoundation
import AudioToolbox

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
final class CleanupStreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let changing: Bool
    init(changing: Bool = false) { self.changing = changing }
    func settings() -> NarrationCleanupSettings {
        lock.withLock {
            var result = NarrationCleanupSettings.referenceB
            if changing && samples.count < 12000 { result.mix = 0 }
            return result
        }
    }
    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))) }
    }
    var values: [Float] { lock.withLock { samples } }
}
@main struct StudioProcessingChecks {
    static func write(_ url: URL, _ samples: [Float], rate: Double = 48000) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for i in samples.indices { buffer.floatChannelData![0][i] = samples[i] }
        try file.write(from: buffer)
        if #available(macOS 15.0, *) { file.close() }
    }
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
        var samples: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, file.length - file.framePosition)))
            guard buffer.frameLength > 0 else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        return samples
    }
    static func rms(_ samples: ArraySlice<Float>) -> Double { sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count)) }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var seed: UInt64 = 42
        func noise() -> Float { seed = seed &* 6364136223846793005 &+ 1; return (Float((seed >> 32) & 65535) / 32768 - 1) * 0.025 }
        let room = (0..<144000).map { _ in noise() }
        let samples = (0..<96000).map { i in noise() + (i > 24000 ? 0.2 * sin(Float(i) * 2 * .pi * 1000 / 48000) : 0) }
        let source = root.appendingPathComponent("noisy.wav"), profile = root.appendingPathComponent("room.wav")
        try write(source, samples); try write(profile, room)
        let original = try Data(contentsOf: source)
        let clean = root.appendingPathComponent("clean.wav"), unity = root.appendingPathComponent("unity.wav")
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: unity, amount: 0)
        let passthrough = try read(unity)
        precondition(passthrough.count == samples.count)
        precondition(zip(samples, passthrough).allSatisfy { abs($0 - $1) < 0.00001 }, "Overlap-add changed unprocessed samples")
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: clean, amount: 1.2)
        let cleaned = try read(clean)
        precondition(cleaned.count == samples.count && cleaned.allSatisfy(\.isFinite))
        let reduction = 20 * log10(rms(samples[4096..<20000]) / rms(cleaned[4096..<20000]))
        let speechRatio = rms(cleaned[30000..<90000]) / rms(samples[30000..<90000])
        precondition(reduction > 2, "Noise attenuation insufficient")
        precondition(speechRatio > 0.8 && speechRatio < 1.1, "Tone was damaged")
        let after = try Data(contentsOf: source); precondition(original == after)
        print("PASS: native noise profile; attenuation \(reduction) dB, tone RMS ratio \(speechRatio); exact frame count, unity reconstruction, original preserved")

        let mismatched = root.appendingPathComponent("room-44100.wav")
        try write(mismatched, room, rate: 44100)
        let convertedClean = root.appendingPathComponent("clean-resampled-profile.wav")
        try NarrationNoiseCleanup.render(source: source, roomTone: mismatched, destination: convertedClean, amount: 1.2)
        let converted = try read(convertedClean)
        precondition(converted.count == samples.count && converted.allSatisfy(\.isFinite))
        precondition(rms(converted[4096..<20000]) < rms(samples[4096..<20000]))
        print("PASS: 44.1 kHz room profile with 48 kHz narration; profile conversion, denoising and narration frame count")
        let adjusted = root.appendingPathComponent("adjustable.wav")
        var settings = NarrationCleanupSettings.referenceA
        settings.mix = 0
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: adjusted, settings: settings)
        let dryMix = try read(adjusted)
        precondition(dryMix.count == samples.count && zip(dryMix, samples).allSatisfy { abs($0 - $1) < 0.00001 })
        settings = .referenceA; settings.strength = 0
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: adjusted, settings: settings)
        let zeroStrength = try read(adjusted)
        precondition(zip(zeroStrength, samples).allSatisfy { abs($0 - $1) < 0.00001 })
        settings = .referenceA; settings.maximumReductionDB = 0
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: adjusted, settings: settings)
        let zeroReduction = try read(adjusted)
        precondition(zip(zeroReduction, samples).allSatisfy { abs($0 - $1) < 0.00001 })
        settings = .referenceA; settings.low = 0; settings.mid = 0; settings.high = 0
        try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: adjusted, settings: settings)
        let zeroBands = try read(adjusted)
        precondition(zip(zeroBands, samples).allSatisfy { abs($0 - $1) < 0.00001 })
        var quietLevels: [Double] = []
        for preset in [NarrationCleanupSettings.referenceA, .referenceB] {
            try NarrationNoiseCleanup.render(source: source, roomTone: profile, destination: adjusted, settings: preset)
            let values = try read(adjusted)
            precondition(values.count == samples.count && values.allSatisfy(\.isFinite))
            quietLevels.append(rms(values[4096..<20000]))
        }
        precondition(quietLevels[1] < quietLevels[0], "Stronger preset should reduce this fixture's noise further")
        var invalid = NarrationCleanupSettings.referenceA; invalid.smoothing = .nan
        do { try invalid.validate(); fatalError("NaN settings accepted") } catch { }
        let lowProfile = root.appendingPathComponent("low-profile.wav")
        try write(lowProfile, (0..<144000).map { 0.02 * sin(Float($0) * 2 * .pi * 100 / 48000) })
        let analysis = try NarrationNoiseAnalysis.analyze(lowProfile)
        precondition(analysis.bandFractions[0] > 0.9 && analysis.suggested.low > analysis.suggested.high)
        precondition(analysis.spectrum.count == 24 && analysis.spectrum.allSatisfy(\.isFinite))
        let settingsJSON = try JSONEncoder().encode(analysis.suggested)
        let restoredSettings = try JSONDecoder().decode(NarrationCleanupSettings.self, from: settingsJSON)
        precondition(restoredSettings == analysis.suggested)
        print("PASS: adjustable cleanup dry mix, zero reduction/bands, A/B strength, finite output, invalid settings, low-frequency suggestion and settings persistence")
        let streamed = CleanupStreamProbe()
        try NarrationNoiseCleanup.stream(source: source, roomTone: profile, workingDirectory: root,
            settings: { streamed.settings() }, onBuffer: { buffer, _ in streamed.receive(buffer) })
        let liveValues = streamed.values
        precondition(liveValues.count == samples.count)
        let offlineB = try read(adjusted)
        precondition(zip(liveValues, offlineB).allSatisfy { abs($0 - $1) < 0.00001 }, "Streaming and fixed offline B must match")
        let changing = CleanupStreamProbe(changing: true)
        try NarrationNoiseCleanup.stream(source: source, roomTone: profile, workingDirectory: root,
            settings: { changing.settings() }, onBuffer: { buffer, _ in changing.receive(buffer) })
        let changed = changing.values
        precondition(changed.count == samples.count)
        precondition(zip(changed.prefix(8192), samples.prefix(8192)).allSatisfy { abs($0 - $1) < 0.00001 })
        precondition(rms(changed[15000..<22000]) < rms(samples[15000..<22000]) * 0.5, "Updated mix must take effect during one stream")
        print("PASS: streaming/offline sample equivalence and settings changed during a single stream, with exact frame count")
        let host = NarrationAudioUnits()
        print("Installed AU effects: \(host.choices.count); non-Apple: \(host.choices.filter { $0.description.componentManufacturer != kAudioUnitManufacturer_Apple }.map(\.name))")
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_HighPassFilter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let unit = try await AVAudioUnit.instantiate(with: description, options: [])
        unit.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(kHipassParam_CutoffFrequency))?.value = 8000
        let state = try PropertyListSerialization.data(fromPropertyList: unit.auAudioUnit.fullStateForDocument!, format: .binary, options: 0)
        let plugin = NarrationPluginState(name: "Apple Highpass Test", type: description.componentType, subtype: description.componentSubType, manufacturer: description.componentManufacturer, state: state)
        let fx = root.appendingPathComponent("effect.wav")
        try await NarrationAudioUnits.render(source: source, destination: fx, plugins: [plugin])
        let floatFX = root.appendingPathComponent("effect-float.wav")
        try await NarrationAudioUnits.render(source: source, destination: floatFX, plugins: [plugin], floatingPoint: true)
        let floatFile = try AVAudioFile(forReading: floatFX)
        precondition(floatFile.fileFormat.streamDescription.pointee.mBitsPerChannel == 32)
        let floatSamples = try read(floatFX)
        precondition(floatSamples.count >= samples.count && floatSamples.allSatisfy(\.isFinite))
        let processed = try read(fx)
        precondition(processed.count >= samples.count)
        precondition(rms(processed[30000..<90000]) < rms(samples[30000..<90000]) * 0.5, "AU state or processing not applied")
        let bypass = root.appendingPathComponent("bypass.wav")
        var bypassed = plugin; bypassed.bypass = true
        try await NarrationAudioUnits.render(source: source, destination: bypass, plugins: [bypassed])
        let dry = try read(bypass)
        precondition(abs(rms(dry[30000..<90000]) - rms(samples[30000..<90000])) < 0.001)
        await host.restore([plugin]); let saved = try host.snapshot()
        precondition(saved.count == 1 && saved[0].state != nil)
        let json = try JSONEncoder().encode(saved)
        let reopened = try JSONDecoder().decode([NarrationPluginState].self, from: json)
        precondition(reopened == saved)
        print("PASS: AU discovery, native instantiate, saved parameter state, offline effect render, bypass and project state round trip")
    }
}

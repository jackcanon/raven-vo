import Foundation
import AVFoundation
import Accelerate

struct NarrationCleanupSettings: Codable, Equatable, Sendable {
    var strength = 2.5
    var maximumReductionDB = 40.0
    var smoothing = 0.5
    var low = 1.0
    var mid = 1.0
    var high = 1.0
    var mix = 1.0
    static let referenceA = Self()
    static let referenceB = Self(strength: 5)
    static let gentle = Self(strength: 1.5, maximumReductionDB: 24, smoothing: 0.65)
    static let fan = Self(strength: 3.5, maximumReductionDB: 38, smoothing: 0.8, low: 1.5, mid: 1.2)
    static let hiss = Self(strength: 2.8, maximumReductionDB: 32, smoothing: 0.65, low: 0.8, high: 1.5)
    func validate() throws {
        for (value, range) in [(strength, 0.0...8), (maximumReductionDB, 0.0...48), (smoothing, 0.0...1), (low, 0.0...2), (mid, 0.0...2), (high, 0.0...2), (mix, 0.0...1)] {
            guard value.isFinite, range.contains(value) else { throw NSError(domain: "Cleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid noise-cleanup settings."]) }
        }
    }
    func focus(at frequency: Double) -> Double {
        let lowWeight = 1 / (1 + pow(frequency / 250, 4))
        let highWeight = 1 / (1 + pow(4000 / max(1, frequency), 4))
        return low * lowWeight + high * highWeight + mid * max(0, 1 - lowWeight - highWeight)
    }
}
struct NarrationNoiseAnalysis: Sendable {
    let spectrum: [Double]
    let bandFractions: [Double]
    let levelDBFS: Double
    let suggested: NarrationCleanupSettings
    var recommendedPreset: (name: String, settings: NarrationCleanupSettings) {
        if bandFractions[0] > 0.55 { return ("Fan / AC", .fan) }
        if bandFractions[2] > 0.35 { return ("Hiss", .hiss) }
        if levelDBFS > -42 { return ("B · Stronger AC Reduction", .referenceB) }
        return ("A · Smoother AC Reduction", .referenceA)
    }
    var explanation: String {
        let names = ["low-frequency rumble", "midrange room noise", "high-frequency hiss"]
        let index = bandFractions.indices.max(by: { bandFractions[$0] < bandFractions[$1] }) ?? 1
        return "The sample has most energy in \(names[index]) (\(Int(bandFractions[index] * 100))%). Suggested settings are a starting point; compare the voice and remaining noise by ear."
    }
    static func analyze(_ url: URL) throws -> Self {
        let file = try AVAudioFile(forReading: url)
        let n = 2048, rate = file.processingFormat.sampleRate
        guard rate.isFinite, rate > 0, file.length >= Int64(n), Double(file.length) / rate <= 10,
              let transform = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n)) else {
            throw NSError(domain: "Cleanup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capture a short room-noise sample before suggesting settings."])
        }
        defer { vDSP_DFT_DestroySetup(transform) }
        let zero = [Float](repeating: 0, count: n)
        var real = zero, imaginary = zero
        var power = [Double](repeating: 0, count: n / 2)
        var squares = 0.0, samples = 0
        while file.framePosition + Int64(n) <= file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(n))
            guard buffer.frameLength == n, let channels = buffer.floatChannelData else { break }
            var mono = zero
            for i in 0..<n {
                let x = (0..<Int(file.processingFormat.channelCount)).reduce(Float(0)) { $0 + channels[$1][i] } / Float(file.processingFormat.channelCount)
                guard x.isFinite else { throw NSError(domain: "Cleanup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Noise sample contains invalid audio."]) }
                squares += Double(x * x); samples += 1
                mono[i] = x * Float(0.5 - 0.5 * cos(2 * Double.pi * (Double(i) + 0.5) / Double(n)))
            }
            vDSP_DFT_Execute(transform, mono, zero, &real, &imaginary)
            for i in power.indices { power[i] += Double(real[i] * real[i] + imaginary[i] * imaginary[i]) }
        }
        guard samples > 0, squares / Double(samples) > 1e-12 else { throw NSError(domain: "Cleanup", code: 4, userInfo: [NSLocalizedDescriptionKey: "The sample is silent or too short to suggest useful settings."]) }
        var bands = [Double](repeating: 0, count: 3), bins = [Double](repeating: 0, count: 24)
        for i in 1..<power.count {
            let frequency = Double(i) * rate / Double(n)
            bands[frequency < 250 ? 0 : frequency < 4000 ? 1 : 2] += power[i]
            if frequency >= 20 && frequency <= 20000 {
                let bin = min(23, max(0, Int(log(frequency / 20) / log(1000) * 24)))
                bins[bin] += power[i]
            }
        }
        let total = max(bands.reduce(0, +), 1e-20)
        let fractions = bands.map { $0 / total }
        let maxBin = max(bins.max() ?? 0, 1e-20)
        let spectrum = bins.map { max(-60, 10 * log10(max($0, 1e-20) / maxBin)) }
        var settings = NarrationCleanupSettings.referenceA
        settings.smoothing = 0.65
        if fractions[0] > 0.6 { settings.low = 1.5; settings.high = 0.85 }
        if fractions[2] > 0.35 { settings.high = 1.4 }
        let level = 10 * log10(squares / Double(samples))
        settings.maximumReductionDB = level > -45 ? 40 : 32
        return Self(spectrum: spectrum, bandFractions: fractions, levelDBFS: level, suggested: settings)
    }
}

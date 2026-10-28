import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

struct VoiceSampleProfile: Codable, Sendable {
    let fileName: String
    let duration: Double
    var transcript: String
    var rawFileName: String?
    var cleanupApplied: Bool?
    var quality: SampleQuality?
}

enum VoiceSampleAudio {
    static func readAll(_ file: AVAudioFile) throws -> AVAudioPCMBuffer {
        guard let result = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let target = result.floatChannelData else { throw StudioError.message("Cannot read this audio format.") }
        file.framePosition = 0
        var count = 0
        while count < Int(file.length) {
            chunk.frameLength = 0
            try file.read(into: chunk, frameCount: AVAudioFrameCount(min(4096,Int(file.length)-count)))
            if chunk.frameLength == 0 { break }
            for channel in 0..<Int(file.processingFormat.channelCount) {
                target[channel].advanced(by: count).update(from: chunk.floatChannelData![channel], count: Int(chunk.frameLength))
            }
            count += Int(chunk.frameLength)
        }
        result.frameLength = AVAudioFrameCount(count)
        return result
    }
    static func normalize(_ source: URL, to destination: URL, sampleRate: Double = 24000) throws -> Double {
        return try autoreleasepool {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let seconds = Double(input.length) / input.processingFormat.sampleRate
        guard seconds >= 2.98 && seconds <= 15.02 else { throw StudioError.message("Choose a recording between 3 and 15 seconds long.") }
        let sourceBuffer = try readAll(input)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let scratch = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16384) else {
            throw StudioError.message("This recording could not be converted to a voice sample.")
        }
        converter.primeMethod = .none
        var inputOffset = 0
        var ended = false
        var total: AVAudioFramePosition = 0
        var peak: Float = 0
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        var file: AVAudioFile? = try AVAudioFile(forWriting: destination, settings: settings)
        for _ in 0..<1000 {
            var failure: NSError?
            output.frameLength = 0
            let status = converter.convert(to: output, error: &failure) { requested, state in
                let remaining = Int(sourceBuffer.frameLength) - inputOffset
                if remaining <= 0 { state.pointee = .endOfStream; return nil }
                let count = min(Int(requested), remaining, Int(scratch.frameCapacity))
                scratch.frameLength = AVAudioFrameCount(count)
                for channel in 0..<Int(input.processingFormat.channelCount) {
                    scratch.floatChannelData![channel].update(from: sourceBuffer.floatChannelData![channel].advanced(by: inputOffset), count: count)
                }
                inputOffset += count; state.pointee = .haveData; return scratch
            }
            if let failure { throw failure }
            guard status != .error else { throw StudioError.message("Audio conversion failed.") }
            if output.frameLength > 0 {
                if let channel = output.floatChannelData?[0] {
                    for i in 0..<Int(output.frameLength) {
                        guard channel[i].isFinite else { throw StudioError.message("This sample contains invalid audio values.") }
                        peak = max(peak,abs(channel[i]))
                    }
                }
                try file?.write(from: output)
                total += AVAudioFramePosition(output.frameLength)
            }
            if status == .endOfStream { ended = true; break }
        }
        file = nil
        guard ended, total > 0 else { throw StudioError.message("Audio conversion did not finish.") }
        guard peak > 0.0001 else { throw StudioError.message("This sample is silent or too quiet. Record again closer to the microphone.") }
        return Double(total) / format.sampleRate
        }
    }
}

@MainActor @Observable final class YourVoiceStore {
    var profile: VoiceSampleProfile?
    var micCheck: VoiceSampleProfile?
    var recordingIsMicCheck = false
    var denoiseEnabled = StoragePreference.preferences.bool(forKey: "RavenVO.cleanup.v1") {
        didSet { StoragePreference.preferences.set(denoiseEnabled, forKey: "RavenVO.cleanup.v1") }
    }
    var transcript = "" {
        didSet { if !loading { scheduleSave() } }
    }
    var isRecording = false
    var busy = false
    var elapsed: Double = 0
    var error: String?
    @ObservationIgnored private let denoiserOverride: URL?
    @ObservationIgnored private var samplePlayer: AVAudioPlayer?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loading = false
    private var base: URL? { StoragePreference.folder }
    private var checkIndex: URL? { base?.appendingPathComponent("app-data/mic-check.json") }
    private var index: URL? { base?.appendingPathComponent("app-data/your-voice.json") }
    var samples: URL? { base?.appendingPathComponent("voice-references", isDirectory: true) }
    var sampleURL: URL? {
        guard let profile, profile.fileName == URL(fileURLWithPath: profile.fileName).lastPathComponent,
              profile.fileName.hasSuffix(".wav") else { return nil }
        return samples?.appendingPathComponent(profile.fileName)
    }
    var ready: Bool { StoragePreference.mounted && sampleURL.map { FileManager.default.fileExists(atPath: $0.path) } == true }
    init(denoiserOverride: URL? = nil) { self.denoiserOverride = denoiserOverride; reload() }
    func reload() {
        loading = true
        defer { loading = false }
        guard StoragePreference.mounted else { profile = nil; transcript = ""; return }
        profile = index.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(VoiceSampleProfile.self, from: $0) }
        micCheck = checkIndex.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(VoiceSampleProfile.self, from: $0) }
        transcript = profile?.transcript ?? ""
    }
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func save() {
        guard var profile, let index, StoragePreference.mounted else { return }
        profile.transcript = transcript
        do {
            try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(profile).write(to: index, options: .atomic)
            if let sampleURL { try JSONEncoder().encode(profile).write(to: sampleURL.deletingPathExtension().appendingPathExtension("json"), options: .atomic) }
            self.profile = profile
        } catch { self.error = "Could not save your voice settings: \(error.localizedDescription)" }
    }
    func importSample() {
        guard !isRecording && !busy && StoragePreference.mounted else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose 3–15 seconds of clean speech in your own voice."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        install(url)
    }
    func install(_ source: URL, micCheck: Bool = false) {
        guard !busy, StoragePreference.mounted, let samples else { return }
        busy = true; error = nil
        let id = UUID().uuidString
        let raw = samples.appendingPathComponent("Voice-Raw-\(id).wav")
        let cleaned = samples.appendingPathComponent("Voice-Clean-\(id).wav")
        let applyCleanup = micCheck || denoiseEnabled
        let helper = denoiserOverride ?? Bundle.main.url(forResource: "raven-denoise", withExtension: nil, subdirectory: "Engine") ?? StudioModel.base.appendingPathComponent("DesktopApp/.build/raven-denoise")
        Task {
            defer { busy = false }
            do {
                try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
                let prepared = try await Task.detached {
                    var duration = try VoiceSampleAudio.normalize(source, to: raw)
                    let quality = try SampleQuality.measure(raw, roomToneAtStart: micCheck)
                    if applyCleanup { duration = try VoiceSampleCleanup.denoise(raw, to: cleaned, helper: helper) }
                    return VoiceSampleProfile(fileName: applyCleanup ? cleaned.lastPathComponent : raw.lastPathComponent, duration: duration, transcript: "", rawFileName: raw.lastPathComponent, cleanupApplied: applyCleanup, quality: quality)
                }.value
                if micCheck {
                    self.micCheck = prepared
                    denoiseEnabled = true
                    if let checkIndex {
                        try FileManager.default.createDirectory(at: checkIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try JSONEncoder().encode(prepared).write(to: checkIndex, options: .atomic)
                    }
                    AccessibilityAnnouncement.post("Microphone check ready. Compare the original and cleaned sample, then record your voice sample.")
                } else {
                    profile = prepared; transcript = ""; save()
                    AccessibilityAnnouncement.post("Your voice sample is ready.")
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func selectSavedSample(_ name: String, transcript: String) {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".wav"),
              let url = samples?.appendingPathComponent(name), StoragePreference.mounted,
              let file = try? AVAudioFile(forReading: url) else { error = "The voice sample for this saved script is unavailable."; return }
        profile = (try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))).flatMap { try? JSONDecoder().decode(VoiceSampleProfile.self, from: $0) } ?? VoiceSampleProfile(fileName: name, duration: Double(file.length) / file.processingFormat.sampleRate, transcript: transcript)
        self.transcript = transcript
        save()
    }
    func playMicCheck(cleaned: Bool) {
        guard let check = micCheck, let fileName = cleaned ? Optional(check.fileName) : check.rawFileName,
              let url = samples?.appendingPathComponent(fileName) else { return }
        play(url)
    }
    func playOriginalSample() {
        guard let name = profile?.rawFileName, let url = samples?.appendingPathComponent(name) else { return }
        play(url)
    }
    func playSample() {
        guard ready, let url = sampleURL else { return }
        play(url)
    }
    private func play(_ url: URL) {
        do { samplePlayer?.stop(); samplePlayer = try AVAudioPlayer(contentsOf: url); samplePlayer?.play() }
        catch { self.error = "Could not play the sample: \(error.localizedDescription)" }
    }
    func startRecording(micCheck: Bool = false) {
        guard !busy && !isRecording && StoragePreference.mounted else { return }
        samplePlayer?.stop()
        busy = true; error = nil
        Task { [self] in
            defer { busy = false }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                error = "Microphone access is off. Allow Raven VO in System Settings → Privacy & Security → Microphone, or import a recording."
                return
            }
            do {
                guard StoragePreference.mounted, let samples else { throw StudioError.message("Reconnect your storage volume before recording.") }
                try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
                let url = samples.appendingPathComponent("Recording-\(UUID().uuidString).wav")
                let audio = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
                guard audio.record(forDuration: 12) else { throw StudioError.message("The microphone could not start recording.") }
                recorder = audio; recordingURL = url; recordingIsMicCheck = micCheck; elapsed = 0; isRecording = true
                timer = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled, let self, self.isRecording else { return }
                        self.elapsed = self.recorder?.currentTime ?? 0
                        if self.elapsed >= 12 || self.recorder?.isRecording != true { self.stopRecording(); return }
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func stopRecording() {
        guard isRecording else { return }
        timer?.cancel(); timer = nil
        recorder?.stop(); recorder = nil; isRecording = false
        guard let url = recordingURL else { return }
        recordingURL = nil
        guard StoragePreference.mounted else { error = "Storage was disconnected. Reconnect it to recover any recording that was saved."; return }
        install(url, micCheck: recordingIsMicCheck)
    }
    func flush() { saveTask?.cancel(); save() }
}

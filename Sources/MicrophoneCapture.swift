import AVFoundation

struct MicrophoneChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// All capture configuration, start/stop, and device I/O stay on this serial queue.
/// Delegate completion is delivered only after the WAV has finished writing.
final class MicrophoneCapture: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ravenvo.microphone", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var dataOutput: AVCaptureAudioDataOutput?
    private var onAudio: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var meter: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var interruptionMessage: String?
    private var finish: (@MainActor @Sendable (URL, String?) -> Void)?

    static func choices() -> [MicrophoneChoice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.filter { $0.hasMediaType(.audio) }.map { MicrophoneChoice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func defaultName() -> String { AVCaptureDevice.default(for: .audio)?.localizedName ?? "No input available" }

    func start(deviceID: String, url: URL, maximumDuration: Double = 12, sampleRate: Double = 24000,
               onAudio: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil,
               onLevel: @escaping @MainActor @Sendable (Double, Double) -> Void,
               onFinish: @escaping @MainActor @Sendable (URL, String?) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let device = deviceID.isEmpty ? AVCaptureDevice.default(for: .audio) : AVCaptureDevice(uniqueID: deviceID)
                    guard let device, device.hasMediaType(.audio) else {
                        throw StudioError.message("The selected microphone is unavailable. Reconnect it or choose another input.")
                    }
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw StudioError.message("This microphone could not be configured for recording.")
                    }
                    session.addInput(input); session.addOutput(output)
                    if let onAudio {
                        let data = AVCaptureAudioDataOutput()
                        if session.canAddOutput(data) {
                            session.addOutput(data)
                            data.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                AVLinearPCMIsNonInterleaved: false]
                            data.setSampleBufferDelegate(self, queue: queue)
                            self.dataOutput = data; self.onAudio = onAudio
                        }
                        // If simultaneous data output is unavailable, preserve recording;
                        // the empty background stream triggers saved-file transcription.
                    }
                    output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                    output.maxRecordedDuration = maximumDuration > 0 ? CMTime(seconds: maximumDuration, preferredTimescale: 48000) : .invalid
                    session.commitConfiguration()
                    finish = onFinish
                    interruptionMessage = nil
                    for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                        let token = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                            guard let self else { return }
                            self.queue.async { [self] in
                                interruptionMessage = "The microphone session was interrupted or became unavailable."
                                if output.isRecording { output.stopRecording() }
                            }
                        }
                        observers.append(token)
                    }
                    session.startRunning()
                    guard session.isRunning else { throw StudioError.message("The selected microphone did not start.") }
                    output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
                    timer.setEventHandler { [weak self] in
                        guard let self else { return }
                        let channels = self.output.connection(with: .audio)?.audioChannels ?? []
                        let db = Double(channels.map(\.averagePowerLevel).max() ?? -80)
                        let seconds = CMTimeGetSeconds(self.output.recordedDuration)
                        Task { @MainActor in onLevel(db.isFinite ? max(-80, min(0, db)) : -80, seconds.isFinite ? max(0, seconds) : 0) }
                    }
                    meter = timer; timer.resume()
                    continuation.resume()
                } catch {
                    clearObservers()
                    session.stopRunning()
                    finish = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output.isRecording, let onAudio, let buffer = Self.audioBuffer(from: sampleBuffer) else { return }
        onAudio(buffer)
    }
    /// A capture format description is not necessarily PCM. Reject unusable formats
    /// before AVAudioPCMBuffer allocation rather than trusting an imported nonoptional initializer.
    static func audioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM,
              asbd.pointee.mSampleRate.isFinite, asbd.pointee.mSampleRate > 0,
              asbd.pointee.mChannelsPerFrame > 0, asbd.pointee.mChannelsPerFrame <= 64,
              asbd.pointee.mBytesPerFrame > 0 else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, frames <= 65536,
              let format = AVAudioFormat(streamDescription: asbd), format.commonFormat != .otherFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList) == noErr else { return nil }
        return buffer
    }
    private func clearObservers() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers = []
    }
    deinit { for token in observers { NotificationCenter.default.removeObserver(token) } }
    func stop() { queue.async { [self] in output.stopRecording() } }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let ns = error as NSError?
        let success = error == nil || ns?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        let message = success ? nil : error?.localizedDescription
        queue.async { [self] in
            meter?.cancel(); meter = nil
            clearObservers()
            session.stopRunning()
            onAudio = nil; dataOutput?.setSampleBufferDelegate(nil, queue: nil)
            let callback = finish; finish = nil
            let result = message ?? interruptionMessage
            Task { @MainActor in callback?(url, result) }
        }
    }
}

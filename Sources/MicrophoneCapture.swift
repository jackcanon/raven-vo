import AVFoundation

struct MicrophoneChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// All capture configuration, start/stop, and device I/O stay on this serial queue.
/// Delegate completion is delivered only after the WAV has finished writing.
final class MicrophoneCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ravenvo.microphone", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var meter: DispatchSourceTimer?
    private var finish: (@MainActor @Sendable (URL, String?) -> Void)?

    static func choices() -> [MicrophoneChoice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.filter { $0.hasMediaType(.audio) }.map { MicrophoneChoice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func defaultName() -> String { AVCaptureDevice.default(for: .audio)?.localizedName ?? "No input available" }

    func start(deviceID: String, url: URL,
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
                    output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000,
                        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                    output.maxRecordedDuration = CMTime(seconds: 12, preferredTimescale: 24000)
                    session.commitConfiguration()
                    finish = onFinish
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
                    session.stopRunning()
                    finish = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func stop() { queue.async { [self] in output.stopRecording() } }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let ns = error as NSError?
        let success = error == nil || ns?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        let message = success ? nil : error?.localizedDescription
        queue.async { [self] in
            meter?.cancel(); meter = nil
            session.stopRunning()
            let callback = finish; finish = nil
            Task { @MainActor in callback?(url, message) }
        }
    }
}

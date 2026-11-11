import AVFoundation
import Speech

/// Called serially by the capture queue; keeps work off the UI actor.
@available(macOS 26.0, *)
final class NarrationSpeechFeed: @unchecked Sendable {
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var frames: Int64 = 0
    private let lock = NSLock()
    private var failure: String?
    var error: String? { lock.withLock { failure } }
    init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.format = format; self.continuation = continuation
    }
    func append(_ input: AVAudioPCMBuffer) {
        do {
            if converter == nil { converter = AVAudioConverter(from: input.format, to: format); converter?.primeMethod = .none }
            guard let converter,
                  let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 256) else { throw StudioError.message("Cannot convert microphone audio for transcription.") }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return input
            }
            if let conversionError { throw conversionError }
            guard status != .error else { throw StudioError.message("Microphone transcription conversion failed.") }
            guard output.frameLength > 0 else { return }
            let time = CMTime(value: frames, timescale: CMTimeScale(format.sampleRate))
            frames += Int64(output.frameLength)
            if case .dropped = continuation.yield(AnalyzerInput(buffer: output, bufferStartTime: time)) {
                throw StudioError.message("Background transcription could not keep up; the saved recording will be transcribed after stopping.")
            }
        } catch { lock.withLock { failure = error.localizedDescription } }
    }
    func finish() { continuation.finish() }
}

@available(macOS 26.0, *)
@MainActor final class NarrationLiveTranscription {
    let feed: NarrationSpeechFeed
    private let analyzer: SpeechAnalyzer
    private var analysis: Task<Void, Error>?
    private var results: Task<[NarrationWord], Error>?
    private init(feed: NarrationSpeechFeed, analyzer: SpeechAnalyzer) { self.feed = feed; self.analyzer = analyzer }
    static func prepare(localeID: String) async throws -> NarrationLiveTranscription {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw StudioError.message("Apple transcription is unavailable for this Mac or language.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw StudioError.message("Apple transcription has no compatible audio format.") }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(128))
        let session = NarrationLiveTranscription(feed: NarrationSpeechFeed(format: format, continuation: continuation), analyzer: analyzer)
        session.results = Task {
            var words: [NarrationWord] = []
            for try await result in transcriber.results {
                guard result.isFinal else { continue }
                for run in result.text.runs {
                    guard let time = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = time.start.seconds, end = CMTimeRangeGetEnd(time).seconds
                    if !text.isEmpty, start.isFinite, end.isFinite, end > start { words.append(.init(text: text, start: start, end: end)) }
                }
            }
            return words
        }
        session.analysis = Task {
            _ = try await analyzer.analyzeSequence(stream)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        return session
    }
    func finish() async throws -> [NarrationWord] {
        feed.finish()
        do {
            try await analysis?.value
            let words = try await results?.value ?? []
            if let error = feed.error { throw StudioError.message(error) }
            guard !words.isEmpty else { throw StudioError.message("No speech recognized during recording.") }
            return words
        } catch { await cancel(); throw error }
    }
    func cancel() async {
        feed.finish(); analysis?.cancel(); results?.cancel(); await analyzer.cancelAndFinishNow()
    }
}
